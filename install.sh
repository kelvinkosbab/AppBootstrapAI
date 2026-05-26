#!/usr/bin/env bash
# AppBootstrapAI installer — see lib/help.txt for the full --help text.
# Architecture: install.sh is the CLI dispatcher; the modes live in lib/.
#
#   lib/help.txt           — full --help documentation (this file's head comment used to be here)
#   lib/predicates.sh      — file_category, should_install_*, sha256_file, concat helpers
#   lib/detect_platform.sh — --platform auto-detection from TARGET dir signals
#   lib/list_modes.sh      — --list and --list-mcps handlers
#   lib/upgrade_mode.sh    — bash wrapper for --upgrade (calls lib/upgrade.py)
#   lib/install_mode.sh    — the install path (skills, rules, agents, gitignore, manifest)
#   lib/install_mcps.sh    — --with-mcps install merge (calls lib/mcp_merge.py)
#   lib/upgrade.py         — Python: upgrade plan/apply executor
#   lib/uninstall.py       — Python: --uninstall executor
#   lib/mcp_merge.py       — Python: MCP merge into settings.local.json
#   lib/inherit_selection.py — Python: read selection fields from a manifest


set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MCP_RECIPES_DIR="$SCRIPT_DIR/mcp-recipes"
TARGET="${1:-.}"
# Empty PLATFORM = auto-detect from TARGET dir after arg parsing.
# Explicit --platform <value> sets it and bypasses detection.
PLATFORM=""
APPLE_LANG="swift"
FEATURES_INPUT="recommended"
WITH_MCPS=""
AGENTS_INPUT="claude"
ACTION="install"
DRY_RUN="false"
# shellcheck disable=SC2034   # read by lib/list_modes.sh (--list --json branch)
JSON_OUTPUT="false"
# Phase 3 upgrade-apply flags. Each requires --upgrade + --apply (validated below).
APPLY="false"
FORCE_CONFLICTS="false"
PRUNE="false"
MIGRATE_MANIFEST="false"
# Phase 5b uninstall flags.
PURGE="false"
KEEP_MCPS="false"

# Track whether the user explicitly passed each flag. Used by --upgrade to
# inherit selection from the manifest when the user didn't override.
APPLE_LANG_EXPLICIT="false"
FEATURES_EXPLICIT="false"
AGENTS_EXPLICIT="false"

# --- Argument parsing ---------------------------------------------------------

while [[ $# -gt 0 ]]; do
    case "$1" in
        --platform)
            PLATFORM="$2"
            shift 2
            ;;
        --apple-language)
            APPLE_LANG="$2"
            APPLE_LANG_EXPLICIT="true"
            shift 2
            ;;
        --features)
            FEATURES_INPUT="$2"
            FEATURES_EXPLICIT="true"
            shift 2
            ;;
        --list)
            ACTION="list"
            shift
            ;;
        --list-mcps)
            ACTION="list-mcps"
            shift
            ;;
        --upgrade)
            ACTION="upgrade"
            shift
            ;;
        --uninstall)
            ACTION="uninstall"
            shift
            ;;
        --purge)
            PURGE="true"
            shift
            ;;
        --keep-mcps)
            KEEP_MCPS="true"
            shift
            ;;
        --apply)
            APPLY="true"
            shift
            ;;
        --force-conflicts)
            FORCE_CONFLICTS="true"
            shift
            ;;
        --prune)
            PRUNE="true"
            shift
            ;;
        --migrate-manifest)
            MIGRATE_MANIFEST="true"
            shift
            ;;
        --with-mcps)
            WITH_MCPS="$2"
            shift 2
            ;;
        --agents|--agent)
            AGENTS_INPUT="$2"
            AGENTS_EXPLICIT="true"
            shift 2
            ;;
        --dry-run)
            DRY_RUN="true"
            shift
            ;;
        --json)
            JSON_OUTPUT="true"
            shift
            ;;
        -h|--help)
            cat "$SCRIPT_DIR/lib/help.txt"
            exit 0
            ;;
        *)
            TARGET="$1"
            shift
            ;;
    esac
done

# --- Phase 3 / 5b flag validation ---------------------------------------------
# --apply only combines with --upgrade.
if [[ "$APPLY" == "true" && "$ACTION" != "upgrade" ]]; then
    echo "error: --apply requires --upgrade" >&2
    exit 1
fi
# --force-conflicts is meaningful under --upgrade --apply OR --uninstall (where it
# means "delete user-edited files anyway"). Reject otherwise.
if [[ "$FORCE_CONFLICTS" == "true" && "$APPLY" != "true" && "$ACTION" != "uninstall" ]]; then
    echo "error: --force-conflicts requires --upgrade --apply or --uninstall" >&2
    exit 1
fi
if [[ "$PRUNE" == "true" && "$APPLY" != "true" ]]; then
    echo "error: --prune requires --upgrade --apply" >&2
    exit 1
fi
if [[ "$MIGRATE_MANIFEST" == "true" && "$APPLY" != "true" ]]; then
    echo "error: --migrate-manifest requires --upgrade --apply" >&2
    exit 1
fi
if [[ "$PURGE" == "true" && "$ACTION" != "uninstall" ]]; then
    echo "error: --purge requires --uninstall" >&2
    exit 1
fi
if [[ "$KEEP_MCPS" == "true" && "$ACTION" != "uninstall" ]]; then
    echo "error: --keep-mcps requires --uninstall" >&2
    exit 1
fi

# --- Agents catalog + resolver -----------------------------------------------
# Defined here (before upgrade-inherit) because upgrade-inherit needs to call
# resolve_agents() on the manifest-recorded agents_input. The SELECTED_AGENTS
# value and validation happen later in the script alongside --features.
ALL_AGENTS="claude copilot cursor gemini codex"

resolve_agents() {
    local input="$1"
    local out="" token expanded a
    for token in $(echo "$input" | tr ',' ' '); do
        case "$token" in
            all)    expanded="$ALL_AGENTS" ;;
            *)      expanded="$token" ;;
        esac
        for a in $expanded; do
            # De-dupe.
            case " $out " in
                *" $a "*) ;;
                *) out="$out $a" ;;
            esac
        done
    done
    echo "${out# }"
}

# --- Upgrade: inherit selection from manifest --------------------------------
#
# For --upgrade, default the selection flags to what was recorded at install
# time (so re-running `./install.sh /target --upgrade` Just Works without the
# user having to remember every flag). Explicit flags on this invocation still
# win — that's how users opt into new feature categories at upgrade time.

# shellcheck disable=SC2034   # read by lib/upgrade_mode.sh's plan header
UPGRADE_INHERITED_FROM_MANIFEST="false"
if [[ "$ACTION" == "upgrade" ]]; then
    upgrade_manifest_path="${TARGET}/.claude/.appbootstrap-manifest.json"
    if [[ -f "$upgrade_manifest_path" ]]; then
        # Read selection fields; tolerant of v1 manifests (which still have the
        # same selection shape, just no per-file hashes). See lib/inherit_selection.py.
        if inherited="$(python3 "$SCRIPT_DIR/lib/inherit_selection.py" "$upgrade_manifest_path" 2>/dev/null)"; then
            IFS='|' read -r m_platform m_apple m_features m_agents <<<"$inherited"
            if [[ -z "$PLATFORM" && -n "$m_platform" ]]; then
                PLATFORM="$m_platform"
                # shellcheck disable=SC2034   # read by lib/upgrade_mode.sh
                UPGRADE_INHERITED_FROM_MANIFEST="true"
            fi
            if [[ "$APPLE_LANG_EXPLICIT" != "true" && -n "$m_apple" ]]; then
                APPLE_LANG="$m_apple"
                # shellcheck disable=SC2034
                UPGRADE_INHERITED_FROM_MANIFEST="true"
            fi
            if [[ "$FEATURES_EXPLICIT" != "true" && -n "$m_features" ]]; then
                FEATURES_INPUT="$m_features"
                # shellcheck disable=SC2034
                UPGRADE_INHERITED_FROM_MANIFEST="true"
            fi
            if [[ "$AGENTS_EXPLICIT" != "true" && -n "$m_agents" ]]; then
                AGENTS_INPUT="$m_agents"
                # Re-resolve SELECTED_AGENTS from the inherited value.
                SELECTED_AGENTS="$(resolve_agents "$AGENTS_INPUT")"
                # shellcheck disable=SC2034
                UPGRADE_INHERITED_FROM_MANIFEST="true"
            fi
        fi
    fi
fi

# Platform autodetect + the autodetect block itself live in lib/detect_platform.sh.
# shellcheck source=lib/detect_platform.sh
source "$SCRIPT_DIR/lib/detect_platform.sh"


# --- Feature categories -------------------------------------------------------

ALL_CATEGORIES="core concurrency ui testing docs error-handling packaging logging localization persistence ai migration shrinking"
RECOMMENDED_CATEGORIES="core concurrency ui testing docs error-handling packaging logging localization"

# Resolve --features input into a space-separated list of category names.
# Supports composition: each comma-separated token expands independently, so
# --features recommended,ai,persistence works (recommended subset + two extras),
# and --features all is the union of every category. Tokens are de-duplicated.
resolve_features() {
    local input="$1"
    local out=""
    local token expanded c
    # Tokenize on commas via tr; the loop relies on default whitespace word-splitting.
    # Don't touch IFS — that would affect the inner loop too.
    for token in $(echo "$input" | tr ',' ' '); do
        case "$token" in
            all)         expanded="$ALL_CATEGORIES" ;;
            recommended) expanded="$RECOMMENDED_CATEGORIES" ;;
            *)           expanded="$token" ;;
        esac
        for c in $expanded; do
            # De-dupe — skip if already present.
            case " $out " in
                *" $c "*) ;;
                *) out="$out $c" ;;
            esac
        done
    done
    # Strip leading space.
    echo "${out# }"
}

SELECTED_FEATURES="$(resolve_features "$FEATURES_INPUT")"

# Validate every selected category is known.
for f in $SELECTED_FEATURES; do
    found=0
    for valid in $ALL_CATEGORIES; do
        if [[ "$f" == "$valid" ]]; then found=1; break; fi
    done
    if [[ "$found" != "1" ]]; then
        echo "error: unknown feature category: $f" >&2
        echo "       valid categories: $ALL_CATEGORIES" >&2
        echo "       presets: all, recommended" >&2
        exit 1
    fi
done

# --- --agents resolution ------------------------------------------------------
#
# AGENTS_INPUT is CSV of: claude (default), copilot, cursor, gemini, codex, all.
# Resolve into SELECTED_AGENTS as a space-separated set, validate, de-dupe.
# (Function defined earlier near arg-parse so upgrade-inherit can call it.)

SELECTED_AGENTS="$(resolve_agents "$AGENTS_INPUT")"
for a in $SELECTED_AGENTS; do
    valid=0
    for known in $ALL_AGENTS; do
        if [[ "$a" == "$known" ]]; then valid=1; break; fi
    done
    if [[ "$valid" != "1" ]]; then
        echo "error: unknown agent: $a" >&2
        echo "       valid agents: $ALL_AGENTS" >&2
        echo "       presets: all" >&2
        exit 1
    fi
done

# Convenience helper used throughout the install + upgrade paths.
agents_has() {
    case " $SELECTED_AGENTS " in
        *" $1 "*) return 0 ;;
        *) return 1 ;;
    esac
}

# Validate --with-mcps recipe names early (before any writes). Each name must
# match an mcp-recipes/<name>.json file. Empty input is fine (no MCPs requested).
SELECTED_MCPS=""
if [[ -n "$WITH_MCPS" ]]; then
    if ! command -v python3 >/dev/null 2>&1; then
        echo "error: --with-mcps requires python3 on PATH (JSON merge is done in Python)." >&2
        exit 1
    fi
    SELECTED_MCPS="$(echo "$WITH_MCPS" | tr ',' ' ')"
    for mcp_name in $SELECTED_MCPS; do
        if [[ ! -f "$MCP_RECIPES_DIR/$mcp_name.json" ]]; then
            echo "error: unknown MCP recipe: $mcp_name" >&2
            echo "       run --list-mcps to see available recipes" >&2
            exit 1
        fi
    done
fi

# Inclusion predicates + helpers live in lib/predicates.sh — sourced here
# so the rest of this script (and the mode files) can call them.
# shellcheck source=lib/predicates.sh
source "$SCRIPT_DIR/lib/predicates.sh"


# --- Mutation wrapper for --dry-run support -----------------------------------

# Run a command, or print what would have run under --dry-run.
# Usage: act "human-readable description" <command> <args...>
act() {
    local desc="$1"; shift
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "[dry-run] $desc"
    else
        "$@"
    fi
}

# Best-effort: capture the AppBootstrapAI git HEAD. Falls back to "unknown" if
# the bundle was extracted from a tarball or git isn't on PATH. Purely informational —
# the upgrade flow uses content hashes, not commit SHAs.
# Defined here so both install AND upgrade flows can stamp it into the manifest.
# shellcheck disable=SC2034   # read by lib/install_mode.sh (write_manifest) and lib/upgrade_mode.sh
if command -v git >/dev/null 2>&1; then
    BUNDLE_COMMIT="$(git -C "$SCRIPT_DIR" rev-parse HEAD 2>/dev/null || echo "unknown")"
else
    BUNDLE_COMMIT="unknown"
fi

# Detect the bundle's GitHub remote (owner/repo) so the upgrade plan can print
# a compare URL like https://github.com/owner/repo/compare/<old>...<new>.
# Empty string if SCRIPT_DIR isn't a git checkout, has no `origin` remote, or
# the remote isn't on github.com.
# shellcheck disable=SC2034   # read by lib/upgrade_mode.sh
BUNDLE_GH_REMOTE=""
if command -v git >/dev/null 2>&1; then
    _remote_url="$(git -C "$SCRIPT_DIR" remote get-url origin 2>/dev/null || echo "")"
    if [[ -n "$_remote_url" ]]; then
        # Match SSH (git@github.com:owner/repo[.git]) and HTTPS forms.
        if [[ "$_remote_url" =~ github\.com[:/]([^/]+)/([^/]+)$ ]]; then
            _owner="${BASH_REMATCH[1]}"
            _repo="${BASH_REMATCH[2]%.git}"
            # shellcheck disable=SC2034
            BUNDLE_GH_REMOTE="$_owner/$_repo"
        fi
    fi
fi

# --list-mcps and --list handlers — both exit 0 after printing.
# shellcheck source=lib/list_modes.sh
source "$SCRIPT_DIR/lib/list_modes.sh"

# --upgrade dispatch — assembles inputs for lib/upgrade.py, exits after.
# shellcheck source=lib/upgrade_mode.sh
source "$SCRIPT_DIR/lib/upgrade_mode.sh"

# --- --uninstall mode ---------------------------------------------------------
#
# Walks the manifest, classifies each tracked file (safe-delete / user-edited /
# user-protected), removes the safe ones, strips the .gitignore block, removes
# the manifest itself. MCP entries get the same 3-way safety: removed if
# unchanged since install, skipped otherwise unless --force.

if [[ "$ACTION" == "uninstall" ]]; then
    if [[ ! -d "$TARGET" ]]; then
        echo "error: target directory does not exist: $TARGET" >&2
        exit 1
    fi
    TARGET="$(cd "$TARGET" && pwd)"
    manifest_path="$TARGET/.claude/.appbootstrap-manifest.json"

    if [[ ! -f "$manifest_path" ]]; then
        echo "error: no manifest at $manifest_path" >&2
        echo "       This target does not appear to be an AppBootstrapAI install." >&2
        echo "       Nothing to uninstall." >&2
        exit 1
    fi

    echo "==> Uninstalling AppBootstrapAI from $TARGET"
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "    [DRY RUN] No files will be deleted. Re-run without --dry-run to apply."
    fi

    settings_local_path="$TARGET/.claude/settings.local.json"

    # All uninstall logic — file classification, deletion, MCP cleanup,
    # gitignore strip, manifest removal. See lib/uninstall.py.
    python3 "$SCRIPT_DIR/lib/uninstall.py" \
        "$manifest_path" "$TARGET" "$settings_local_path" \
        "$FORCE_CONFLICTS" "$PURGE" "$KEEP_MCPS" "$DRY_RUN"

    exit 0
fi

# Install mode — the default path. Skills + rules + agents + manifest setup.
# shellcheck source=lib/install_mode.sh
source "$SCRIPT_DIR/lib/install_mode.sh"


# --with-mcps merge — calls lib/mcp_merge.py, parses output, prints setup notes.
# shellcheck source=lib/install_mcps.sh
source "$SCRIPT_DIR/lib/install_mcps.sh"

# --- Token-saving tips (only fires when there's actually room to optimize) ---
#
# AI agents pay for every token of installed context. Suggest narrower flags
# when the chosen ones bring in rules the project probably doesn't need.
TOKEN_TIPS=()
if [[ "$PLATFORM" == "both" ]]; then
    TOKEN_TIPS+=("Targeting only one platform? Re-run with --platform apple (or android) to skip the other side's rules entirely. Example: an iOS-only app doesn't need Android rules — even though they wouldn't fire on .swift files, omitting them keeps the installed catalog leaner.")
fi
if [[ "$FEATURES_INPUT" == "all" ]]; then
    TOKEN_TIPS+=("--features all installs every category, including specialized opt-ins (persistence/Core Data, ai/Foundation Models, migration/XML→Compose, shrinking/R8) you may not use. --features recommended (default) is leaner; opt into specifics explicitly: --features recommended,ai.")
fi
if [[ "$APPLE_LANG" == "both" ]] && [[ "$PLATFORM" != "android" ]]; then
    TOKEN_TIPS+=("Pure-Swift project? --apple-language swift (default) skips the two apple-objc-* rules. Only use 'both' if you actually have .h/.m/.mm sources.")
fi

if [[ "${#TOKEN_TIPS[@]}" -gt 0 ]]; then
    echo ""
    echo "Token-saving tips (you're paying for AI context — narrow scope = leaner bill):"
    for tip in "${TOKEN_TIPS[@]}"; do
        echo "  - $tip"
    done
    echo "  See the README 'Saving AI tokens' section for prompt-discipline tips."
fi
