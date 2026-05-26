#!/usr/bin/env bash
# AppBootstrapAI installer — copies the Claude Code bundle into a target repo.
#
# Usage:
#   ./install.sh [TARGET_DIR] [--platform apple|android|both]
#                             [--apple-language swift|objc|both]
#                             [--features all|recommended|<csv>]
#                             [--with-mcps <csv>]
#                             [--dry-run]
#   ./install.sh --list [--json] [--features ...] [--platform ...]
#   ./install.sh --list-mcps
#   ./install.sh --help
#
# Defaults: TARGET_DIR=.  --platform <auto-detected>  --apple-language swift
#           --features recommended
#
# Flags:
#   --platform           Which platform's rules and skills to install.
#                        - apple   → install apple-* rules + Apple skills
#                        - android → install android-* rules + Android skills
#                        - both    → install everything (intersected with --features)
#                        If unset, the installer auto-detects from the TARGET_DIR:
#                          - Package.swift / *.xcodeproj / *.xcworkspace → apple
#                          - build.gradle* / settings.gradle* / gradlew  → android
#                          - both present                                → both
#                          - neither (fresh / empty dir)                 → both (fallback)
#                        The detection result + which signals matched are
#                        printed in the install header so you can verify.
#
#   --apple-language     When --platform is apple or both, narrows the Apple
#                        side to a specific language:
#                        - swift (default) → all apple- rules except apple-objc-*
#                                            + Apple skills (skills are Swift-tied)
#                        - objc            → apple-objc-* only, no Apple skills
#                        - both            → all apple- rules + Apple skills
#
#   --features           Comma-separated list of feature categories, or one of:
#                        - recommended (default) → curated subset for most apps:
#                            core, concurrency, ui, testing, docs,
#                            error-handling, packaging, logging, localization
#                        - all                   → every category
#                        - custom CSV, e.g. --features core,testing,docs
#                        - composable, e.g. --features recommended,ai,persistence
#                          (each token expands independently; preset + extras OK)
#
#                        Available categories (each spans Apple + Android where applicable):
#                          core             project-level README/CHANGELOG/ADR patterns
#                          concurrency      Swift concurrency / Kotlin coroutines
#                          ui               SwiftUI/MVVM / Jetpack Compose + accessibility
#                          testing          test strategy + coverage gates
#                          docs             DocC / KDoc documentation strategy
#                          error-handling   Swift typed throws / Result / LocalizedError
#                          packaging        Package.swift / Gradle / SPM authoring
#                          logging          os.Logger discipline
#                          localization     String Catalogs / strings.xml / RTL
#                          persistence      Core Data under Swift 6
#                          ai               Apple Foundation Models (iOS 26+)
#                          migration        XML/Fragment → Compose migration
#                          shrinking        R8 / ProGuard
#
#                        Note: apple-objc-best-practices.md is gated solely by
#                        --apple-language, not --features.
#
#   --dry-run            Show what would be installed without writing any files.
#                        Useful for previewing an upgrade or auditing a re-run on
#                        an existing adopter site.
#
#   --list               Print the catalog of available rules and skills with
#                        one-line descriptions and category tags, and exit.
#                        Use this to preview what a given flag combo would install.
#
#   --json               Only valid with --list. Produce a machine-readable
#                        catalog (stable schema for the MCP server and any
#                        other automation that wants to consume the catalog).
#
#   --list-mcps          List available MCP-server recipes (name, platform,
#                        description, homepage) that --with-mcps can install.
#                        Exits after printing.
#
#   --agents <csv>       Comma-separated list of AI agents to install for.
#                        Default: claude. Additive — pass multiple to cover a
#                        mixed team in one install. Accepted tokens:
#                          claude   → .claude/rules/, .claude/skills/, CLAUDE.md  (today's default)
#                          copilot  → .github/copilot-instructions.md  (concat of in-scope rules)
#                          cursor   → .cursor/rules/<name>.mdc          (per-rule files)
#                          gemini   → GEMINI.md                          (concat of in-scope rules)
#                          codex    → AGENTS.md                          (concat of in-scope rules)
#                          all      → every agent above
#                        Skills are Claude-only — non-Claude agents get rules
#                        only. Existing agent files are NEVER overwritten by
#                        install; --upgrade does 3-way diff like any other
#                        tracked file. Concat files are deterministic for
#                        the same --platform / --apple-language / --features.
#
#   --with-mcps <csv>    Comma-separated list of MCP recipes to add to the
#                        target's .claude/settings.local.json. Each recipe
#                        contributes one entry under "mcpServers". Existing
#                        entries with the same name are NEVER overwritten —
#                        skipped entries are listed in the install output.
#                        Setup steps for each newly-added MCP (auth, env vars,
#                        prerequisite binaries) print at the end of install.
#                        Recipe names come from --list-mcps; unknown names
#                        fail cleanly. Requires python3 on PATH (JSON merge is
#                        done in Python to avoid bash fragility).
#
#   --upgrade            Compare an existing install against the current bundle
#                        and print an upgrade plan. By default writes nothing —
#                        pair with --apply to execute. Reads the manifest at
#                        .claude/.appbootstrap-manifest.json and classifies
#                        every tracked file into one of:
#                          - up to date (installed hash matches bundle)
#                          - safe update (no local edits, bundle has new content)
#                          - local edits (file modified after install — left alone)
#                          - conflict (both local and bundle changed)
#                          - retired (file removed upstream — orphan)
#                          - addition (new in bundle, fits --features)
#                          - out-of-scope (manifest tracks, current --features doesn't include)
#                          - renamed (via RENAMES.md)
#                        Requires schema_version 2 manifest; v1 manifests
#                        (older installs without hashes) get a migration hint
#                        unless --migrate-manifest is also passed.
#
#   --apply              Execute the upgrade plan. Only valid with --upgrade.
#                        Writes safe updates, copies in additions, refreshes
#                        the manifest with fresh hashes + bundle_commit. By
#                        default, conflicts are SKIPPED with a warning and
#                        orphans/out-of-scope files are LEFT ALONE — opt into
#                        more aggressive behavior with --force-conflicts /
#                        --prune. Combine with --dry-run to preview without
#                        writing.
#
#   --force-conflicts    Only valid with --upgrade --apply. Overwrite files
#                        that were locally edited AND changed upstream. Your
#                        local changes are lost — do this only when you've
#                        already preserved what you wanted (diff against
#                        git history, save a copy, etc.).
#
#   --prune              Only valid with --upgrade --apply. Delete files
#                        that are listed as orphans (retired upstream) or
#                        out-of-scope (under the current --features). The
#                        manifest entries are also dropped.
#
#   --migrate-manifest   Only valid with --upgrade --apply. Rewrites a v1
#                        manifest (older install, no hashes recorded) as a v2
#                        manifest using current disk contents as the installed
#                        baseline. No file content is touched. After migration,
#                        future --upgrade runs can do real 3-way diffs.
#
#   --uninstall          Reverse of install — removes everything AppBootstrapAI
#                        wrote into the target, based on the manifest. By default:
#                          - Tracked files whose current hash matches what we
#                            wrote are DELETED.
#                          - Tracked files the user edited (current hash differs)
#                            are SKIPPED with a warning. Pass --force to delete
#                            them anyway.
#                          - CLAUDE.md and settings.json are SKIPPED unconditionally
#                            (user-owned by then). Pass --purge to delete them too.
#                          - MCP entries in settings.local.json that match what
#                            we installed are removed; modified ones are skipped
#                            unless --force. Pass --keep-mcps to leave them all.
#                        Combine with --dry-run to preview without writing.
#                        Final step removes the .gitignore block and the
#                        manifest itself.
#
#   -h, --help           Print this help and exit.
#
# What it does:
#   - Copies skills matching the platform/language/features intersection.
#   - Copies rules matching the same intersection.
#   - Copies .claude/settings.json if none exists in TARGET_DIR.
#   - Renders the platform-appropriate CLAUDE template into TARGET_DIR/CLAUDE.md
#     (apple → CLAUDE.template.apple.md, android → CLAUDE.template.android.md,
#      both → CLAUDE.template.md). Only if CLAUDE.md does not already exist —
#      it never overwrites.
#   - Appends recommended .gitignore entries for the chosen platform(s).
#   - Writes a manifest at .claude/.appbootstrap-manifest.json listing every
#     file that was installed (used by future --upgrade / --uninstall flows).
#
# It never overwrites an existing CLAUDE.md or settings.json; it prints what
# it skipped so you can merge manually.

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
            sed -n '2,180p' "${BASH_SOURCE[0]}"
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

UPGRADE_INHERITED_FROM_MANIFEST="false"
if [[ "$ACTION" == "upgrade" ]]; then
    upgrade_manifest_path="${TARGET}/.claude/.appbootstrap-manifest.json"
    if [[ -f "$upgrade_manifest_path" ]]; then
        # Read selection fields; tolerant of v1 manifests (which still have the
        # same selection shape, just no per-file hashes).
        if inherited="$(python3 - "$upgrade_manifest_path" <<'PYTHON' 2>/dev/null
import json, sys
m = json.load(open(sys.argv[1]))
s = m.get("selection", {})
# Print pipe-separated: platform|apple_language|features_input|agents_input
print(f"{s.get('platform','')}|{s.get('apple_language','')}|{s.get('features_input','')}|{s.get('agents_input','')}")
PYTHON
        )"; then
            IFS='|' read -r m_platform m_apple m_features m_agents <<<"$inherited"
            if [[ -z "$PLATFORM" && -n "$m_platform" ]]; then
                PLATFORM="$m_platform"
                UPGRADE_INHERITED_FROM_MANIFEST="true"
            fi
            if [[ "$APPLE_LANG_EXPLICIT" != "true" && -n "$m_apple" ]]; then
                APPLE_LANG="$m_apple"
                UPGRADE_INHERITED_FROM_MANIFEST="true"
            fi
            if [[ "$FEATURES_EXPLICIT" != "true" && -n "$m_features" ]]; then
                FEATURES_INPUT="$m_features"
                UPGRADE_INHERITED_FROM_MANIFEST="true"
            fi
            if [[ "$AGENTS_EXPLICIT" != "true" && -n "$m_agents" ]]; then
                AGENTS_INPUT="$m_agents"
                # Re-resolve SELECTED_AGENTS from the inherited value.
                SELECTED_AGENTS="$(resolve_agents "$AGENTS_INPUT")"
                UPGRADE_INHERITED_FROM_MANIFEST="true"
            fi
        fi
    fi
fi

# --- Platform auto-detection --------------------------------------------------
#
# When --platform isn't explicitly set, look at the TARGET directory for
# canonical project files and pick the dominant platform. Falls back to "both"
# if nothing matches (fresh / empty repo). An explicit --platform always wins.
#
# Signals checked:
#   Apple:   Package.swift, *.xcodeproj/, *.xcworkspace/
#   Android: build.gradle{,.kts}, settings.gradle{,.kts}, gradlew

# Globals populated by detect_platform. Set as side effects of calling the
# function (not via command substitution, because subshell assignments don't
# propagate). Read these after the call.
#   DETECTED_PLATFORM         — "apple" | "android" | "both" | "" (no signals)
#   DETECTED_APPLE_SIGNALS    — space-separated filenames that matched
#   DETECTED_ANDROID_SIGNALS  — same, for Android
DETECTED_PLATFORM=""
DETECTED_APPLE_SIGNALS=""
DETECTED_ANDROID_SIGNALS=""

detect_platform() {
    local target="$1"
    local apple=""
    local android=""

    # Apple signals.
    [[ -f "$target/Package.swift" ]] && apple="$apple Package.swift"

    # Glob expansion for *.xcodeproj / *.xcworkspace. nullglob makes the loop
    # skip cleanly when nothing matches; basename trims the path back to the
    # bare filename for printing.
    shopt -s nullglob
    local match
    for match in "$target"/*.xcodeproj "$target"/*.xcworkspace; do
        apple="$apple $(basename "$match")"
    done

    # Android signals.
    [[ -f "$target/build.gradle"      ]] && android="$android build.gradle"
    [[ -f "$target/build.gradle.kts"  ]] && android="$android build.gradle.kts"
    [[ -f "$target/settings.gradle"   ]] && android="$android settings.gradle"
    [[ -f "$target/settings.gradle.kts" ]] && android="$android settings.gradle.kts"
    [[ -f "$target/gradlew"           ]] && android="$android gradlew"

    DETECTED_APPLE_SIGNALS="${apple# }"
    DETECTED_ANDROID_SIGNALS="${android# }"

    if [[ -n "$DETECTED_APPLE_SIGNALS" && -n "$DETECTED_ANDROID_SIGNALS" ]]; then
        DETECTED_PLATFORM="both"
    elif [[ -n "$DETECTED_APPLE_SIGNALS" ]]; then
        DETECTED_PLATFORM="apple"
    elif [[ -n "$DETECTED_ANDROID_SIGNALS" ]]; then
        DETECTED_PLATFORM="android"
    else
        DETECTED_PLATFORM=""
    fi
}

# Auto-detect if PLATFORM wasn't set explicitly on the command line. Two
# outcomes:
#   - detection finds signals → use them, flag PLATFORM_AUTODETECTED for the header
#   - detection finds nothing → fall back to "both", flag PLATFORM_AUTODETECT_FALLBACK
PLATFORM_AUTODETECTED="false"
PLATFORM_AUTODETECT_FALLBACK="false"
if [[ -z "$PLATFORM" ]]; then
    # Resolve target to an absolute path for detection. Don't error here on a
    # missing dir — the install path below produces a better error message.
    if [[ -d "$TARGET" ]]; then
        detect_target="$(cd "$TARGET" && pwd)"
    else
        detect_target="$TARGET"
    fi
    detect_platform "$detect_target"
    if [[ -n "$DETECTED_PLATFORM" ]]; then
        PLATFORM="$DETECTED_PLATFORM"
        PLATFORM_AUTODETECTED="true"
    else
        PLATFORM="both"
        PLATFORM_AUTODETECT_FALLBACK="true"
    fi
fi

case "$PLATFORM" in
    apple|android|both) ;;
    *)
        echo "error: --platform must be apple, android, or both (got: $PLATFORM)" >&2
        exit 1
        ;;
esac

case "$APPLE_LANG" in
    swift|objc|both) ;;
    *)
        echo "error: --apple-language must be swift, objc, or both (got: $APPLE_LANG)" >&2
        exit 1
        ;;
esac

if [[ "$JSON_OUTPUT" == "true" ]] && [[ "$ACTION" != "list" ]]; then
    echo "error: --json is only valid with --list" >&2
    exit 1
fi

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

# Map a rule/skill basename to its category. Returns empty string if uncategorized
# (uncategorized files install unconditionally — used for things not yet
# slotted into a category, though there shouldn't be any in practice).
# Returns "objc-gated" for apple-objc-best-practices.md — it's filtered by
# --apple-language, not --features.
file_category() {
    case "$1" in
        project-documentation.md)
            echo "core" ;;
        apple-swift6-strict-concurrency.md|swift-concurrency-pro|android-coroutines-best-practices.md)
            echo "concurrency" ;;
        apple-swiftui-mvvm.md|apple-accessibility-best-practices.md|apple-objc-accessibility-best-practices.md|swiftui-pro|android-compose-best-practices.md|android-accessibility-best-practices.md)
            echo "ui" ;;
        apple-testing-strategy.md|swift-testing-pro|android-testing-strategy.md)
            echo "testing" ;;
        apple-documentation-strategy.md|swift-docc-pro|android-documentation-strategy.md)
            echo "docs" ;;
        swift-error-handling-pro)
            echo "error-handling" ;;
        apple-spm-package-conventions.md|swift-package-pro|android-gradle-conventions.md|android-project-rules.md|android-gradle-architecture-pro)
            echo "packaging" ;;
        swift-logging-pro)
            echo "logging" ;;
        apple-localization-best-practices.md|android-localization-best-practices.md)
            echo "localization" ;;
        coredata-swift6-pro)
            echo "persistence" ;;
        apple-foundation-models.md)
            echo "ai" ;;
        xml-to-compose-migration-pro)
            echo "migration" ;;
        r8-shrink-pro)
            echo "shrinking" ;;
        apple-objc-best-practices.md)
            echo "objc-gated" ;;
        *)
            echo "" ;;
    esac
}

# Check whether a file's category is enabled under --features.
is_in_features() {
    local cat feature
    cat="$(file_category "$1")"
    # objc-gated and uncategorized files bypass the --features filter.
    [[ "$cat" == "objc-gated" || -z "$cat" ]] && return 0
    for feature in $SELECTED_FEATURES; do
        if [[ "$feature" == "$cat" ]]; then return 0; fi
    done
    return 1
}

# --- Inclusion predicates -----------------------------------------------------
# Decide whether a given rule file should be installed for the current
# (PLATFORM, APPLE_LANG, FEATURES) combination.

should_install_rule() {
    local name="$1"
    case "$name" in
        apple-objc-best-practices.md)
            # The core "modern ObjC" rule — gated *only* by --apple-language,
            # not --features. If you opted into ObjC at all, you want this.
            [[ "$PLATFORM" != "android" ]] && [[ "$APPLE_LANG" != "swift" ]]
            ;;
        apple-objc-*)
            # Other ObjC-specific rules (e.g., apple-objc-accessibility-best-practices.md)
            # are categorized — gated by BOTH --apple-language AND --features.
            [[ "$PLATFORM" != "android" ]] && [[ "$APPLE_LANG" != "swift" ]] && is_in_features "$name"
            ;;
        apple-*)
            # Other apple-* rules are Swift-side: include if Apple in scope and
            # language is swift or both AND the rule's category is selected.
            [[ "$PLATFORM" != "android" ]] && [[ "$APPLE_LANG" != "objc" ]] && is_in_features "$name"
            ;;
        android-*)
            [[ "$PLATFORM" != "apple" ]] && is_in_features "$name"
            ;;
        *)
            # Unprefixed rules (like project-documentation.md) — gated by --features only.
            is_in_features "$name"
            ;;
    esac
}

# Per-skill inclusion.
should_install_skill() {
    local name="$1"
    case "$name" in
        android-*|xml-to-compose-*|r8-shrink-*)
            # Android skill — install when Android is in scope AND feature selected.
            [[ "$PLATFORM" != "apple" ]] && is_in_features "$name"
            ;;
        *)
            # Apple/Swift skill — install when Apple+Swift is in scope AND feature selected.
            [[ "$PLATFORM" != "android" ]] && [[ "$APPLE_LANG" != "objc" ]] && is_in_features "$name"
            ;;
    esac
}

# Whether ANY skills will install — drives the "Copying skills" log message.
should_install_any_skills() {
    local skill_dir
    shopt -s nullglob
    for skill_dir in "$SCRIPT_DIR/.claude/skills/"*/; do
        if should_install_skill "$(basename "$skill_dir")"; then
            return 0
        fi
    done
    return 1
}

# Pull the `description:` line out of a rule's YAML frontmatter (best-effort).
rule_description() {
    awk '
        /^---$/ { if (seen) exit; seen=1; next }
        /^description:/ { sub(/^description:[[:space:]]*/, ""); print; exit }
    ' "$1"
}

skill_description() {
    rule_description "$1/SKILL.md"
}

# JSON-escape a string from stdin. Handles backslash, double-quote, tab.
# Strips newlines (descriptions should be single-line; if they aren't, this
# prevents invalid JSON).
json_escape() {
    tr -d '\n' | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/	/\\t/g'
}

# Portable SHA-256 of a file. macOS ships `shasum`; many Linux images ship
# `sha256sum`. Returns just the hex digest with no trailing filename.
# Returns empty string if the file is missing (caller can record null).
sha256_file() {
    local path="$1"
    [[ -f "$path" ]] || { echo ""; return; }
    if command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$path" | awk '{print $1}'
    elif command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$path" | awk '{print $1}'
    else
        echo "error: need shasum or sha256sum on PATH for manifest hashing" >&2
        exit 1
    fi
}

# Emit a deterministic concatenation of every in-scope rule. Used for the
# single-file non-Claude agents (Copilot, Gemini, Codex). Output is identical
# given the same SCRIPT_DIR contents + --platform / --apple-language / --features,
# so hashing the output gives a stable bundle hash across install/upgrade.
#
# The first line of the output is a generated-banner identifying the source
# and disclaiming hand-edits. Each rule is delimited by an HR + the basename
# as a heading, so a human reading the concat can navigate.
#
# Usage: concat_in_scope_rules <banner_purpose>   →  prints to stdout
#   banner_purpose is a short label like "GitHub Copilot" / "Gemini CLI" /
#   "Codex (AGENTS.md)" that gets baked into the header so the generated
#   file's first line tells you what tool it's for.
concat_in_scope_rules() {
    local banner_purpose="$1"
    echo "<!-- Generated by AppBootstrapAI install.sh for ${banner_purpose}. -->"
    echo "<!-- Do not edit this file directly. Edit .claude/rules/ in the bundle and re-run install.sh / --upgrade --apply. -->"
    echo "<!-- Source of truth: https://github.com/kelvinkosbab/AppBootstrapAI -->"
    echo ""
    # Iterate alphabetically — that's what shell glob already does, but be explicit so
    # the contract "deterministic output" doesn't depend on filesystem ordering.
    shopt -s nullglob
    local f name
    for f in $(printf '%s\n' "$SCRIPT_DIR/.claude/rules/"*.md | LC_ALL=C sort); do
        name="$(basename "$f")"
        if should_install_rule "$name"; then
            echo "## $name"
            echo ""
            cat "$f"
            echo ""
            echo ""
            echo "---"
            echo ""
        fi
    done
}

# Print a JSON-array of strings from a space-separated list.
json_string_array() {
    local items="$1"
    local first=1 item
    printf '['
    for item in $items; do
        if [[ "$first" -eq 1 ]]; then first=0; else printf ', '; fi
        printf '"%s"' "$item"
    done
    printf ']'
}

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
if command -v git >/dev/null 2>&1; then
    BUNDLE_COMMIT="$(git -C "$SCRIPT_DIR" rev-parse HEAD 2>/dev/null || echo "unknown")"
else
    BUNDLE_COMMIT="unknown"
fi

# Detect the bundle's GitHub remote (owner/repo) so the upgrade plan can print
# a compare URL like https://github.com/owner/repo/compare/<old>...<new>.
# Empty string if SCRIPT_DIR isn't a git checkout, has no `origin` remote, or
# the remote isn't on github.com.
BUNDLE_GH_REMOTE=""
if command -v git >/dev/null 2>&1; then
    _remote_url="$(git -C "$SCRIPT_DIR" remote get-url origin 2>/dev/null || echo "")"
    if [[ -n "$_remote_url" ]]; then
        # Match SSH (git@github.com:owner/repo[.git]) and HTTPS forms.
        if [[ "$_remote_url" =~ github\.com[:/]([^/]+)/([^/]+)$ ]]; then
            _owner="${BASH_REMATCH[1]}"
            _repo="${BASH_REMATCH[2]%.git}"
            BUNDLE_GH_REMOTE="$_owner/$_repo"
        fi
    fi
fi

# --- --list-mcps mode ---------------------------------------------------------

if [[ "$ACTION" == "list-mcps" ]]; then
    echo "AppBootstrapAI MCP recipes"
    echo "  Add one or more to your repo with: --with-mcps <name1>,<name2>"
    echo "  Each recipe writes one entry under .claude/settings.local.json's"
    echo "  \"mcpServers\" key. Existing entries are never overwritten."
    echo ""
    if [[ ! -d "$MCP_RECIPES_DIR" ]]; then
        echo "  (no recipes directory at $MCP_RECIPES_DIR)"
        exit 0
    fi
    shopt -s nullglob
    for recipe in "$MCP_RECIPES_DIR"/*.json; do
        python3 - "$recipe" <<'PYTHON'
import json, sys, textwrap
with open(sys.argv[1]) as f:
    r = json.load(f)
plat = r.get("platform", "-")
name = r.get("name", "?")
display = r.get("display_name", name)
desc = r.get("description", "")
homepage = r.get("homepage", "")
print(f"  [{plat:14s}] {name}")
print(f"      {display}")
for line in textwrap.wrap(desc, width=76, initial_indent="      ", subsequent_indent="      "):
    print(line)
if homepage:
    print(f"      {homepage}")
print()
PYTHON
    done
    exit 0
fi

# --- --list mode --------------------------------------------------------------

if [[ "$ACTION" == "list" ]]; then
    if [[ "$JSON_OUTPUT" == "true" ]]; then
        # Machine-readable catalog. Stable schema for automation / MCP consumers.
        printf '{\n'
        printf '  "selection": {\n'
        printf '    "platform": "%s",\n' "$PLATFORM"
        printf '    "apple_language": "%s",\n' "$APPLE_LANG"
        printf '    "features_input": "%s",\n' "$FEATURES_INPUT"
        printf '    "features_resolved": '
        json_string_array "$SELECTED_FEATURES"
        printf ',\n'
        printf '    "agents_input": "%s",\n' "$AGENTS_INPUT"
        printf '    "agents_resolved": '
        json_string_array "$SELECTED_AGENTS"
        printf '\n  },\n'

        printf '  "rules": [\n'
        shopt -s nullglob
        first_rule=1
        for f in "$SCRIPT_DIR/.claude/rules/"*.md; do
            name="$(basename "$f")"
            cat="$(file_category "$name")"
            [[ -z "$cat" ]] && cat="-"
            if should_install_rule "$name"; then installed="true"; else installed="false"; fi
            desc="$(rule_description "$f" | json_escape)"
            if [[ "$first_rule" -eq 1 ]]; then first_rule=0; else printf ',\n'; fi
            printf '    {"filename": "%s", "category": "%s", "installed": %s, "description": "%s"}' \
                "$name" "$cat" "$installed" "$desc"
        done
        printf '\n  ],\n'

        printf '  "skills": [\n'
        first_skill=1
        for d in "$SCRIPT_DIR/.claude/skills/"*/; do
            name="$(basename "$d")"
            cat="$(file_category "$name")"
            [[ -z "$cat" ]] && cat="-"
            if should_install_skill "$name"; then installed="true"; else installed="false"; fi
            desc="$(skill_description "$d" | json_escape)"
            if [[ "$first_skill" -eq 1 ]]; then first_skill=0; else printf ',\n'; fi
            printf '    {"name": "%s", "category": "%s", "installed": %s, "description": "%s"}' \
                "$name" "$cat" "$installed" "$desc"
        done
        printf '\n  ]\n'
        printf '}\n'
        exit 0
    fi

    # Human-readable catalog.
    echo "AppBootstrapAI catalog"
    echo "  current selection: --platform $PLATFORM --apple-language $APPLE_LANG --features $FEATURES_INPUT"
    echo "  resolved features: $SELECTED_FEATURES"
    echo ""
    echo "Rules:"
    shopt -s nullglob
    for f in "$SCRIPT_DIR/.claude/rules/"*.md; do
        name="$(basename "$f")"
        if should_install_rule "$name"; then mark="✓"; else mark=" "; fi
        cat="$(file_category "$name")"
        [[ -z "$cat" ]] && cat="-"
        printf "  [%s] %-50s  (%s)\n        %s\n" "$mark" "$name" "$cat" "$(rule_description "$f")"
    done
    echo ""
    echo "Skills:"
    for d in "$SCRIPT_DIR/.claude/skills/"*/; do
        name="$(basename "$d")"
        if should_install_skill "$name"; then mark="✓"; else mark=" "; fi
        cat="$(file_category "$name")"
        [[ -z "$cat" ]] && cat="-"
        printf "  [%s] %-40s  (%s)\n        %s\n" "$mark" "$name" "$cat" "$(skill_description "$d")"
    done
    echo ""
    echo "Legend: [✓] = installed under current selection, [ ] = skipped."
    echo "        Category in parentheses is what --features gates the file by."
    echo "        Pass --json for machine-readable output."
    exit 0
fi

# --- --upgrade mode -----------------------------------------------------------
#
# Plan-only — reads the manifest, compares every tracked file against the
# bundle (3-way: installed hash vs. current disk vs. bundle), and prints what
# WOULD change. Writes nothing. Phase 3 will add --apply.

if [[ "$ACTION" == "upgrade" ]]; then
    if [[ ! -d "$TARGET" ]]; then
        echo "error: target directory does not exist: $TARGET" >&2
        exit 1
    fi
    TARGET="$(cd "$TARGET" && pwd)"
    manifest_path="$TARGET/.claude/.appbootstrap-manifest.json"

    if [[ ! -f "$manifest_path" ]]; then
        echo "error: no manifest at $manifest_path" >&2
        echo "       This target does not appear to be an AppBootstrapAI install." >&2
        echo "       Run install.sh first to create a manifest, then re-run --upgrade." >&2
        exit 1
    fi

    echo "==> Upgrade plan for $TARGET"
    if [[ "$UPGRADE_INHERITED_FROM_MANIFEST" == "true" ]]; then
        echo "    selection (inherited from manifest): --platform $PLATFORM --apple-language $APPLE_LANG --features $FEATURES_INPUT --agents $AGENTS_INPUT"
        echo "    (override any of these on the command line to opt into new categories or agents)"
    else
        echo "    selection: --platform $PLATFORM --apple-language $APPLE_LANG --features $FEATURES_INPUT --agents $AGENTS_INPUT"
    fi
    echo ""

    # ----- Build BUNDLE_ALL and BUNDLE_IN_SCOPE files for Python --------------
    #
    # BUNDLE_ALL: every shippable file in the bundle, with rel_path + type +
    # category + sha256 + skill_name. This is the "could be installed" universe.
    #
    # BUNDLE_IN_SCOPE: subset of BUNDLE_ALL that the current --platform /
    # --apple-language / --features combination would actually install. Computed
    # by reusing should_install_rule / should_install_skill above.
    #
    # Stored in temp files (pipe-separated) so the Python heredoc can mmap them
    # without us having to escape multi-line strings inline.
    bundle_all_tmp="$(mktemp)"
    bundle_in_scope_tmp="$(mktemp)"
    # Overlay dir for agent-derived files (Cursor .mdc, Copilot/Gemini/Codex concat).
    # Python uses it as a source-of-truth when the rel_path isn't in $SCRIPT_DIR.
    bundle_overlay_dir="$(mktemp -d)"
    # shellcheck disable=SC2064
    trap "rm -rf '$bundle_overlay_dir' '$bundle_all_tmp' '$bundle_in_scope_tmp'" EXIT

    # Rules. Always in BUNDLE_ALL; in_scope gated by agents_has claude.
    shopt -s nullglob
    for f in "$SCRIPT_DIR/.claude/rules/"*.md; do
        name="$(basename "$f")"
        cat="$(file_category "$name")"; [[ -z "$cat" ]] && cat="-"
        hash="$(sha256_file "$f")"
        rel_path=".claude/rules/$name"
        echo "$rel_path|rule|$cat|$hash|" >> "$bundle_all_tmp"
        if agents_has claude && should_install_rule "$name"; then
            echo "$rel_path" >> "$bundle_in_scope_tmp"
        fi
    done

    # Skill files (one entry per file inside each skill dir).
    # Skills are Claude-only; gate in_scope on agents_has claude.
    for d in "$SCRIPT_DIR/.claude/skills/"*/; do
        skill_name="$(basename "$d")"
        cat="$(file_category "$skill_name")"; [[ -z "$cat" ]] && cat="-"
        skill_in_scope="false"
        if agents_has claude && should_install_skill "$skill_name"; then skill_in_scope="true"; fi
        while IFS= read -r -d '' src_file; do
            rel_path="${src_file#"$SCRIPT_DIR"/}"
            hash="$(sha256_file "$src_file")"
            echo "$rel_path|skill-file|$cat|$hash|$skill_name" >> "$bundle_all_tmp"
            if [[ "$skill_in_scope" == "true" ]]; then
                echo "$rel_path" >> "$bundle_in_scope_tmp"
            fi
        done < <(find "$d" -type f -print0)
    done

    # settings.json — Claude-only. In BUNDLE_ALL always so the manifest can
    # surface "you've stopped tracking this" diffs; in_scope only when claude
    # is selected.
    settings_hash="$(sha256_file "$SCRIPT_DIR/.claude/settings.json")"
    echo ".claude/settings.json|settings|-|$settings_hash|" >> "$bundle_all_tmp"
    if agents_has claude; then
        echo ".claude/settings.json" >> "$bundle_in_scope_tmp"
    fi

    # CLAUDE.md template — Claude-only too.
    case "$PLATFORM" in
        apple)   TEMPLATE_PATH="templates/CLAUDE.template.apple.md"   ;;
        android) TEMPLATE_PATH="templates/CLAUDE.template.android.md" ;;
        both)    TEMPLATE_PATH="templates/CLAUDE.template.md"         ;;
    esac
    template_hash="$(sha256_file "$SCRIPT_DIR/$TEMPLATE_PATH")"
    # The user's file on disk is CLAUDE.md; we tag the bundle-side path so the
    # plan can show "templates/CLAUDE.template.apple.md → CLAUDE.md".
    echo "CLAUDE.md|template|core|$template_hash|$TEMPLATE_PATH" >> "$bundle_all_tmp"
    if agents_has claude; then
        echo "CLAUDE.md" >> "$bundle_in_scope_tmp"
    fi

    # --- Agent-derived files (Phase 4) ---------------------------------------
    # For Cursor: each .claude/rules/<name>.md → .cursor/rules/<name>.mdc with
    # identical content (cp -p). For Copilot/Gemini/Codex: deterministic concat
    # of in-scope rules. Materialize all of these in the overlay dir so the
    # apply step has a real source path to copy from.

    if agents_has cursor; then
        mkdir -p "$bundle_overlay_dir/.cursor/rules"
        for f in "$SCRIPT_DIR/.claude/rules/"*.md; do
            name="$(basename "$f")"
            cat="$(file_category "$name")"; [[ -z "$cat" ]] && cat="-"
            mdc_name="${name%.md}.mdc"
            cp "$f" "$bundle_overlay_dir/.cursor/rules/$mdc_name"
            hash="$(sha256_file "$bundle_overlay_dir/.cursor/rules/$mdc_name")"
            rel_path=".cursor/rules/$mdc_name"
            echo "$rel_path|agent-file-cursor|$cat|$hash|" >> "$bundle_all_tmp"
            if should_install_rule "$name"; then
                echo "$rel_path" >> "$bundle_in_scope_tmp"
            fi
        done
    fi

    # Helper for the three concat agents.
    _materialize_concat() {
        local rel_path="$1" tag="$2" banner="$3"
        local dst="$bundle_overlay_dir/$rel_path"
        mkdir -p "$(dirname "$dst")"
        concat_in_scope_rules "$banner" > "$dst"
        local hash; hash="$(sha256_file "$dst")"
        echo "$rel_path|$tag|-|$hash|" >> "$bundle_all_tmp"
        echo "$rel_path" >> "$bundle_in_scope_tmp"
    }
    if agents_has copilot; then
        _materialize_concat ".github/copilot-instructions.md" "agent-file-copilot" "GitHub Copilot"
    fi
    if agents_has gemini; then
        _materialize_concat "GEMINI.md" "agent-file-gemini" "Gemini CLI"
    fi
    if agents_has codex; then
        _materialize_concat "AGENTS.md" "agent-file-codex" "Codex CLI and other AGENTS.md-aware tools"
    fi

    # RENAMES.md path (may not exist; Python tolerates missing file).
    renames_path="$SCRIPT_DIR/RENAMES.md"
    # MCP paths — settings.local.json on the target, recipes dir in the bundle.
    settings_local_path="$TARGET/.claude/settings.local.json"

    python3 - \
        "$manifest_path" "$TARGET" "$bundle_all_tmp" "$bundle_in_scope_tmp" "$renames_path" \
        "$PLATFORM" "$APPLE_LANG" "$FEATURES_INPUT" "$SCRIPT_DIR" \
        "$APPLY" "$FORCE_CONFLICTS" "$PRUNE" "$MIGRATE_MANIFEST" "$DRY_RUN" "$BUNDLE_COMMIT" \
        "$settings_local_path" "$MCP_RECIPES_DIR" "$bundle_overlay_dir" \
        "$AGENTS_INPUT" "$SELECTED_AGENTS" "$BUNDLE_GH_REMOTE" \
        <<'PYTHON'
import hashlib, json, os, shutil, sys, datetime

(manifest_path, target_root, bundle_all_path, in_scope_path, renames_path,
 platform, apple_lang, features, script_dir,
 apply_flag, force_conflicts_flag, prune_flag, migrate_manifest_flag, dry_run_flag,
 bundle_commit,
 settings_local_path, mcp_recipes_dir, bundle_overlay_dir,
 agents_input, agents_resolved_str, bundle_gh_remote) = sys.argv[1:22]
agents_resolved = agents_resolved_str.split() if agents_resolved_str else []

def bundle_source_for(rel_path):
    """Resolve the source for a given target-relative path.

    Agent-derived files (Cursor .mdc, Copilot/Gemini/Codex concat) live in the
    overlay dir — they're not directly on disk in the bundle. Everything else
    (rules, skills, settings.json, CLAUDE.md template) maps to script_dir.

    For CLAUDE.md specifically, the source is the platform-specific template
    under templates/, but we don't auto-apply CLAUDE.md anyway, so this never
    gets used for it.
    """
    overlay = os.path.join(bundle_overlay_dir, rel_path)
    if os.path.exists(overlay):
        return overlay
    return os.path.join(script_dir, rel_path)

APPLY            = (apply_flag           == "true")
FORCE_CONFLICTS  = (force_conflicts_flag == "true")
PRUNE            = (prune_flag           == "true")
MIGRATE_MANIFEST = (migrate_manifest_flag == "true")
DRY_RUN          = (dry_run_flag         == "true")

# ----- Read manifest --------------------------------------------------------
with open(manifest_path) as f:
    manifest = json.load(f)

schema = manifest.get("schema_version", 1)

if schema == 1:
    if not MIGRATE_MANIFEST:
        print("==> Manifest is schema v1 (no content hashes recorded at install).")
        print("    The plan-and-apply upgrade flow needs hashes to safely diff your tree.")
        print("")
        print("    Two ways forward:")
        print("    1. Re-run install.sh (without --upgrade) to write a fresh v2 manifest.")
        print("       Existing files are not overwritten — settings.json, CLAUDE.md, and")
        print("       any rules you edited are preserved (the installer never overwrites).")
        print("       This is the lowest-risk path.")
        print("")
        print("    2. Re-run as `--upgrade --apply --migrate-manifest` to rewrite the")
        print("       manifest from current disk contents as a v2 baseline. No file is")
        print("       touched; only the manifest changes. After that, future --upgrade")
        print("       runs can do real 3-way diffs.")
        print("")
        print("    Aborting plan — no v1 → v2 hash inference without --migrate-manifest.")
        sys.exit(0)
    # MIGRATE_MANIFEST + v1: rebuild manifest from disk and exit.
    def sha256_path(p):
        if not os.path.exists(p):
            return None
        h = hashlib.sha256()
        with open(p, "rb") as f:
            for chunk in iter(lambda: f.read(65536), b""):
                h.update(chunk)
        return h.hexdigest()

    new_files = []
    dropped = []
    for entry in manifest.get("files", []):
        rel = entry["path"]
        abs_p = os.path.join(target_root, rel)
        type_ = entry.get("type", "rule")
        # v1 sometimes had a single "skill" entry per directory; expand to one
        # per file by walking the on-disk skill dir.
        if type_ == "skill":
            skill_name = rel.rstrip("/").split("/")[-1]
            if os.path.isdir(abs_p):
                for root, _, fnames in os.walk(abs_p):
                    for fn in fnames:
                        ap = os.path.join(root, fn)
                        rp = os.path.relpath(ap, target_root).replace(os.sep, "/")
                        new_files.append({
                            "path": rp,
                            "type": "skill-file",
                            "category": entry.get("category", "-"),
                            "sha256": sha256_path(ap),
                            "skill": skill_name,
                        })
            else:
                dropped.append(rel)
            continue
        # Non-content entries (gitignore-block) → carry forward with null hash.
        if type_ == "gitignore-block":
            new_files.append({
                "path": rel,
                "type": "gitignore-block",
                "category": entry.get("category", "-"),
                "sha256": None,
            })
            continue
        if not os.path.exists(abs_p):
            dropped.append(rel)
            continue
        new_files.append({
            "path": rel,
            "type": type_,
            "category": entry.get("category", "-"),
            "sha256": sha256_path(abs_p),
        })

    sel = manifest.get("selection", {})
    new_manifest = {
        "schema_version": 2,
        "installed_at": datetime.datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ"),
        "bundle_commit": bundle_commit if bundle_commit else "unknown",
        "selection": {
            "platform": sel.get("platform", platform),
            "apple_language": sel.get("apple_language", apple_lang),
            "features_input": sel.get("features_input", features),
            "features_resolved": sel.get("features_resolved", []),
            # v1 didn't have agents — default to claude (the only agent v1 supported).
            "agents_input": "claude",
            "agents_resolved": ["claude"],
        },
        "files": new_files,
        "mcps_installed": [],   # v1 had string-array mcps_requested; not migrated automatically
    }
    if DRY_RUN:
        print(f"==> [dry-run] Would migrate v1 → v2 manifest at {manifest_path}.")
        print(f"               {len(new_files)} file entries; {len(dropped)} dropped (file missing on disk).")
        print("               (v1 mcps_requested not carried over — re-add MCPs via --with-mcps.)")
    else:
        with open(manifest_path, "w") as f:
            json.dump(new_manifest, f, indent=2)
            f.write("\n")
        print(f"==> Migrated manifest from v1 → v2: {manifest_path}")
        print(f"    Recorded {len(new_files)} file entries with sha256 baselines from current disk.")
        if dropped:
            print(f"    Dropped {len(dropped)} entries whose files are missing on disk:")
            for d in dropped[:10]:
                print(f"      {d}")
            if len(dropped) > 10:
                print(f"      … and {len(dropped) - 10} more")
        print("    Note: v1 mcps_requested was not migrated — re-add MCPs via --with-mcps if needed.")
        print("    Future --upgrade runs can now do real 3-way diffs.")
    sys.exit(0)

if schema > 2:
    print(f"error: manifest schema_version={schema} is newer than this installer understands.", file=sys.stderr)
    print(f"       Update install.sh from the bundle and retry.", file=sys.stderr)
    sys.exit(2)

# ----- Load bundle data ------------------------------------------------------
def load_pipe_file(path, n_fields):
    rows = []
    if not os.path.exists(path):
        return rows
    with open(path) as f:
        for line in f:
            line = line.rstrip("\n")
            if not line:
                continue
            parts = line.split("|", n_fields - 1)
            # pad to n_fields
            while len(parts) < n_fields:
                parts.append("")
            rows.append(parts)
    return rows

bundle_all_rows = load_pipe_file(bundle_all_path, 5)
# Map: rel_path → (type, category, sha256, skill_name_or_template_src)
bundle_all = {r[0]: (r[1], r[2], r[3], r[4]) for r in bundle_all_rows}

in_scope = set()
with open(in_scope_path) as f:
    for line in f:
        line = line.strip()
        if line:
            in_scope.add(line)

# ----- Parse RENAMES.md ------------------------------------------------------
# Two forms supported:
#   - `apple-old.md → apple-new.md`     — rule file rename. Resolves to
#                                          .claude/rules/apple-old.md →
#                                          .claude/rules/apple-new.md
#   - `swift-old-pro → swift-new-pro`   — skill directory rename. Applied as
#                                          a path-prefix substitution at
#                                          classification time, so every file
#                                          under .claude/skills/swift-old-pro/
#                                          folds to .claude/skills/swift-new-pro/<rest>.
renames = {}          # exact old_path → new_path for rule files
skill_renames = {}    # old_skill_name → new_skill_name (prefix-based)
if os.path.exists(renames_path):
    with open(renames_path) as f:
        for raw in f:
            line = raw.strip()
            if not line or line.startswith("#"):
                continue
            # Strip backticks if the line is fenced
            if line.startswith("```") or line == "```":
                continue
            # Accept either Unicode arrow or ASCII ->
            sep = None
            if "→" in line:
                sep = "→"
            elif "->" in line:
                sep = "->"
            else:
                continue
            old, new = [s.strip() for s in line.split(sep, 1)]
            if old.endswith(".md") and new.endswith(".md"):
                # Rule rename (file-level, exact match).
                renames[f".claude/rules/{old}"] = f".claude/rules/{new}"
            elif "/" not in old and "/" not in new and "." not in old and "." not in new:
                # Skill directory rename (bare names, no slashes / dots).
                skill_renames[old] = new

def resolve_rename(rel_path):
    """Apply rule-file + skill-dir renames; follow the chain to convergence."""
    cur = rel_path
    seen = set()
    while True:
        if cur in seen:
            break  # cycle guard
        seen.add(cur)
        # Exact-match rename takes priority.
        if cur in renames:
            cur = renames[cur]
            continue
        # Skill-dir prefix rewrite.
        rewritten = None
        for old_skill, new_skill in skill_renames.items():
            prefix = f".claude/skills/{old_skill}/"
            if cur.startswith(prefix):
                rewritten = f".claude/skills/{new_skill}/" + cur[len(prefix):]
                break
        if rewritten:
            cur = rewritten
            continue
        break
    return cur

# ----- Read every file's current disk hash from manifest -------------------
def sha256_path(p):
    if not os.path.exists(p):
        return None
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()

# ----- Classify each manifest entry ----------------------------------------
up_to_date = []
safe_updates = []
local_edits = []
conflicts = []
orphans = []
out_of_scope = []
renames_safe = []      # safe-to-execute renames: no local edit on old path
renames_conflict = []  # rename + (local edit OR bundle drift) → needs --force-conflicts

manifest_paths = set()
for entry in manifest.get("files", []):
    rel = entry["path"]
    manifest_paths.add(rel)
    installed_hash = entry.get("sha256")
    abs_path = os.path.join(target_root, rel)
    current_hash = sha256_path(abs_path) if installed_hash is not None else None

    # Rename: apply rule-file + skill-dir renames (chain followed to convergence).
    rename_target = resolve_rename(rel)
    is_renamed = rename_target != rel

    bundle_lookup_path = rename_target
    bundle_info = bundle_all.get(bundle_lookup_path)

    # Non-content entries (gitignore-block) — skip diff, leave for Phase 3.
    if installed_hash is None and entry.get("type") == "gitignore-block":
        continue

    if bundle_info is None:
        # File doesn't exist in bundle anymore → orphan.
        orphans.append({
            "path": rel,
            "type": entry.get("type"),
            "current_present": current_hash is not None,
        })
        continue

    bundle_hash = bundle_info[2]
    # Never auto-update CLAUDE.md (template) or settings.json — they're the
    # user's files even though we seeded them at install. Surface upstream
    # changes as informational notes; the user diffs manually.
    if entry.get("type") in ("template", "settings"):
        if installed_hash == bundle_hash:
            up_to_date.append({"path": rel, "type": entry.get("type")})
        else:
            note_target = bundle_info[3] if entry.get("type") == "template" else rel
            local_edits.append({
                "path": rel,
                "type": entry.get("type"),
                "note": f"yours — but {note_target} has advanced upstream. Diff manually if you want the new content.",
            })
        continue

    # Standard 4-case for content files.
    row = {
        "path": rel,
        "type": entry.get("type"),
        "category": entry.get("category"),
        "skill": entry.get("skill"),
        "renamed_to": rename_target if is_renamed else None,
    }

    # Renames are handled separately — apply writes the new path and deletes
    # the old one regardless of whether the file at the old path matches bundle.
    # Safety still matters: if the user has edited the file at the old path,
    # executing the rename would lose that edit.
    if is_renamed:
        # Detect collision: new path already exists on disk AND isn't itself in
        # the manifest. That's a user-authored file at the rename target —
        # never overwrite. Surface as a conflict so the user resolves manually.
        new_abs = os.path.join(target_root, rename_target)
        new_path_collision = (
            os.path.exists(new_abs)
            and rename_target not in {e["path"] for e in manifest.get("files", [])}
        )
        if new_path_collision:
            renames_conflict.append({**row, "note": f"target path already exists at {rename_target}"})
        elif current_hash == bundle_hash or current_hash == installed_hash:
            # No local edit at old path (current matches either installed-baseline
            # or the new bundle content) → safe to rename.
            renames_safe.append(row)
        else:
            # current_hash differs from BOTH installed AND bundle → user has
            # local edits that don't match bundle. Renaming loses them.
            renames_conflict.append(row)
        continue

    # Out-of-scope: bundle still has it but current selection wouldn't install it.
    if bundle_lookup_path not in in_scope:
        out_of_scope.append(row)
        continue

    # Classification — anchor on "is disk already at bundle?" first. This
    # correctly handles the case where the user upgraded once already (so disk
    # matches bundle even though installed_hash is stale).
    if current_hash == bundle_hash:
        # Disk is at latest — no work needed, manifest may be stale (refresh on apply).
        up_to_date.append(row)
    elif current_hash == installed_hash:
        # No local edits since install. Bundle has new content → safe update.
        safe_updates.append(row)
    elif installed_hash == bundle_hash:
        # Bundle unchanged from install, but disk differs → local edit only.
        local_edits.append(row)
    else:
        # current, installed, and bundle all differ → true conflict.
        conflicts.append(row)

# ----- Additions: bundle in-scope, not in manifest --------------------------
# (Skip rename targets — they're already accounted for as renames of an existing path.)
# For rule renames, that's just `renames.values()`. For skill renames, we
# need to apply the prefix to every manifest entry under the OLD skill dir
# so the corresponding NEW-dir file is marked as a rename target (not an addition).
rename_targets = set(renames.values())
for entry in manifest.get("files", []):
    resolved = resolve_rename(entry["path"])
    if resolved != entry["path"]:
        rename_targets.add(resolved)
additions = []
for rel in sorted(in_scope):
    if rel in manifest_paths:
        continue
    if rel in rename_targets:
        continue
    info = bundle_all.get(rel)
    if info is None:
        continue
    type_, cat, _, skill = info
    if type_ == "settings" and os.path.exists(os.path.join(target_root, rel)):
        # settings.json already exists on disk; install path would skip it.
        # We don't surface this as an addition in Phase 2.
        continue
    if type_ == "template" and os.path.exists(os.path.join(target_root, rel)):
        continue
    additions.append({"path": rel, "type": type_, "category": cat, "skill": skill})

# ----- MCP 3-way classification ---------------------------------------------
# For each MCP entry in mcps_installed, compute the same 3-way diff:
#   installed_hash  — from the manifest (config we wrote at install)
#   current_hash    — hash of the entry currently in settings.local.json
#   bundle_hash     — hash of the recipe's config in mcp-recipes/<name>.json
# The hash function must match the one in the MCP merge Python (stable sort,
# compact separators) so a recipe that hasn't actually changed produces the
# same hash on each install.

def mcp_config_hash(config):
    payload = json.dumps(config, sort_keys=True, separators=(",", ":")).encode()
    return hashlib.sha256(payload).hexdigest()

# Load settings.local.json (may be absent if the user never ran --with-mcps).
mcp_servers_current = {}
if os.path.exists(settings_local_path):
    try:
        with open(settings_local_path) as f:
            sl = json.load(f)
        mcp_servers_current = sl.get("mcpServers", {}) or {}
    except json.JSONDecodeError:
        # Malformed settings.local.json — surface as warning, treat as empty so
        # the rest of the upgrade can proceed.
        print(f"  warn: {settings_local_path} is not valid JSON — treating as empty for MCP diff")

# Index bundle recipes for fast lookup.
bundle_recipes = {}
if os.path.isdir(mcp_recipes_dir):
    for fn in os.listdir(mcp_recipes_dir):
        if not fn.endswith(".json"):
            continue
        try:
            with open(os.path.join(mcp_recipes_dir, fn)) as f:
                recipe = json.load(f)
            name = recipe.get("name")
            if name:
                bundle_recipes[name] = recipe
        except json.JSONDecodeError:
            continue

mcp_up_to_date = []
mcp_safe_updates = []
mcp_local_edits = []
mcp_conflicts = []
mcp_orphans = []
# We don't auto-add MCPs on upgrade — additions are an explicit --with-mcps op.

for installed in manifest.get("mcps_installed", []):
    name = installed["name"]
    installed_hash = installed.get("config_sha256")
    current_config = mcp_servers_current.get(name)
    bundle_recipe = bundle_recipes.get(name)
    current_hash = mcp_config_hash(current_config) if current_config is not None else None
    bundle_hash = mcp_config_hash(bundle_recipe["config"]) if (bundle_recipe and "config" in bundle_recipe) else None

    row = {"name": name, "installed_hash": installed_hash,
           "current_hash": current_hash, "bundle_hash": bundle_hash}

    if bundle_hash is None:
        # Recipe no longer ships in the bundle. The user's entry is still in
        # settings.local.json — they own it; we just stop tracking.
        mcp_orphans.append(row)
        continue
    if current_config is None:
        # Manifest says we installed it, but the entry is gone from
        # settings.local.json (user removed it manually). Drop from tracking.
        mcp_orphans.append({**row, "missing_from_settings": True})
        continue

    if current_hash == bundle_hash:
        mcp_up_to_date.append(row)
    elif current_hash == installed_hash and current_hash != bundle_hash:
        mcp_safe_updates.append(row)
    elif current_hash != installed_hash and installed_hash == bundle_hash:
        mcp_local_edits.append(row)
    else:
        mcp_conflicts.append(row)

# ----- Print plan ------------------------------------------------------------
def header(title, rows):
    if not rows:
        return
    print(f"  {title} ({len(rows)})")
    for r in rows[:50]:
        line = f"    {r['path']}"
        cat = r.get("category")
        skill = r.get("skill")
        extras = []
        if cat and cat != "-":
            extras.append(cat)
        if skill:
            extras.append(f"skill={skill}")
        if r.get("renamed_to"):
            extras.append(f"renamed→{r['renamed_to']}")
        if r.get("note"):
            extras.append(r["note"])
        if extras:
            line += "  (" + ", ".join(extras) + ")"
        print(line)
    if len(rows) > 50:
        print(f"    … and {len(rows) - 50} more")
    print("")

manifest_commit = manifest.get("bundle_commit", "unknown")
print(f"  installed bundle commit: {manifest_commit[:12] if manifest_commit != 'unknown' else 'unknown'}")
print(f"  current bundle commit:   {bundle_commit[:12] if bundle_commit != 'unknown' else 'unknown'}")
print(f"  installed at:            {manifest.get('installed_at', '?')}")
# Show a GitHub compare URL when we can — quick way to view exactly what
# changed in the bundle between install and now.
if (bundle_gh_remote
    and manifest_commit not in ("", "unknown")
    and bundle_commit not in ("", "unknown")
    and manifest_commit != bundle_commit):
    print(f"  changes between them:    https://github.com/{bundle_gh_remote}/compare/{manifest_commit}...{bundle_commit}")
print("")

header("Up to date (no action needed):", up_to_date)
header("Safe to update (no local edits, bundle has new content):", safe_updates)
header("Locally edited (left alone — your changes win):", local_edits)
header("Conflict (both local AND bundle changed — default SKIP, --force-conflicts to overwrite):", conflicts)
header("Out of scope (manifest tracks, current --features doesn't include):", out_of_scope)
header("Retired upstream (bundle no longer ships these files):", [{"path": o["path"], "type": o["type"]} for o in orphans])
header("Would add (new in bundle, fits current --features):", additions)

# Renames get their own section so users can see what's moving where. Apply
# treats them as (delete old, write new) atomic pairs.
def rename_header(title, rows):
    if not rows:
        return
    print(f"  {title} ({len(rows)})")
    for r in rows[:50]:
        note = ""
        if r.get("note"):
            note = f"  [{r['note']}]"
        print(f"    {r['path']} → {r['renamed_to']}{note}")
    if len(rows) > 50:
        print(f"    … and {len(rows) - 50} more")
    print("")

rename_header("Renames — safe (no local edits to the old path):", renames_safe)
rename_header("Renames — conflict (local edit at old path OR target path already exists; --force-conflicts to apply anyway):", renames_conflict)

# MCP plan section — only emit if there's anything to say (manifest has MCPs).
mcp_total_tracked = (len(mcp_up_to_date) + len(mcp_safe_updates) +
                     len(mcp_local_edits) + len(mcp_conflicts) + len(mcp_orphans))
if mcp_total_tracked > 0:
    def mcp_header(title, rows):
        if not rows:
            return
        print(f"  {title} ({len(rows)})")
        for r in rows:
            note = ""
            if r.get("missing_from_settings"):
                note = " — entry was removed from settings.local.json"
            print(f"    {r['name']}{note}")
        print("")

    print("MCP entries in .claude/settings.local.json:")
    print("")
    mcp_header("Up to date:", mcp_up_to_date)
    mcp_header("Safe to update (recipe changed upstream, no local edit):", mcp_safe_updates)
    mcp_header("Locally edited (you customized this entry — left alone):", mcp_local_edits)
    mcp_header("Conflict (you edited AND recipe changed — default SKIP, --force-conflicts to overwrite):", mcp_conflicts)
    mcp_header("Orphan (recipe no longer in bundle, or entry removed from settings.local.json):", mcp_orphans)

# Summary line
print(f"==> Plan: {len(safe_updates)} safe update(s), {len(conflicts)} conflict(s),")
print(f"          {len(orphans)} orphan(s), {len(additions)} addition(s),")
print(f"          {len(local_edits)} locally-edited (untouched), {len(up_to_date)} up to date.")
if renames_safe or renames_conflict:
    print(f"          Renames: {len(renames_safe)} safe, {len(renames_conflict)} conflict.")
if mcp_total_tracked > 0:
    print(f"          MCPs: {len(mcp_safe_updates)} safe update(s), {len(mcp_conflicts)} conflict(s),")
    print(f"                {len(mcp_orphans)} orphan(s), {len(mcp_local_edits)} locally-edited,")
    print(f"                {len(mcp_up_to_date)} up to date.")
print("")

if not APPLY:
    print("This is a plan-only preview. No files have been written.")
    print("Re-run with --apply to execute (add --force-conflicts / --prune to opt into the riskier rows).")
    sys.exit(0)

# ----- Apply phase -----------------------------------------------------------
# Skip safe_updates that target never-auto-update types (template / settings) —
# the classifier already routes them to local_edits, but be defensive.
def is_never_auto(row):
    return row.get("type") in ("template", "settings")

actions = []  # list of (kind, row) where kind ∈ {"update","add","delete","rename"}
for r in safe_updates:
    if is_never_auto(r):
        continue
    actions.append(("update", r))
if FORCE_CONFLICTS:
    for r in conflicts:
        if is_never_auto(r):
            continue
        actions.append(("update", r))
skipped_conflicts = 0 if FORCE_CONFLICTS else len([c for c in conflicts if not is_never_auto(c)])
if PRUNE:
    for r in orphans:
        actions.append(("delete", r))
    for r in out_of_scope:
        actions.append(("delete", r))
deleted_count_plan = sum(1 for kind, _ in actions if kind == "delete")
for r in additions:
    actions.append(("add", r))

# Renames — always-safe ones execute under --apply; conflict ones need --force-conflicts.
for r in renames_safe:
    actions.append(("rename", r))
if FORCE_CONFLICTS:
    for r in renames_conflict:
        actions.append(("rename", r))
skipped_rename_conflicts = 0 if FORCE_CONFLICTS else len(renames_conflict)

print(f"==> Applying {len(actions)} action(s)" + (" [DRY RUN]" if DRY_RUN else "") + "...")

written = 0
deleted = 0
for kind, r in actions:
    rel = r["path"]
    dst = os.path.join(target_root, rel)
    if kind in ("update", "add"):
        src = bundle_source_for(rel)
        if not os.path.exists(src):
            # Shouldn't happen — bundle path should exist for in-scope items.
            print(f"  warn: bundle source missing, skipping: {src}")
            continue
        if DRY_RUN:
            print(f"  [dry-run] would {kind}: {rel}")
        else:
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            shutil.copy2(src, dst)
            written += 1
    elif kind == "delete":
        if not os.path.exists(dst):
            # Already gone (user may have deleted manually). Manifest will still drop it.
            print(f"  note: already absent on disk: {rel}")
        elif DRY_RUN:
            print(f"  [dry-run] would delete: {rel}")
        else:
            os.remove(dst)
            deleted += 1
            # Clean up now-empty parent dirs we own (under .claude). Don't
            # touch the user's project root.
            parent = os.path.dirname(dst)
            owned_root = os.path.join(target_root, ".claude")
            while parent.startswith(owned_root) and parent != owned_root:
                try:
                    if not os.listdir(parent):
                        os.rmdir(parent)
                        parent = os.path.dirname(parent)
                    else:
                        break
                except OSError:
                    break
    elif kind == "rename":
        # Move file from r["path"] (old) → r["renamed_to"] (new). Write the
        # bundle's content at the new path; delete the old.
        new_rel = r["renamed_to"]
        new_dst = os.path.join(target_root, new_rel)
        old_dst = os.path.join(target_root, rel)
        src = bundle_source_for(new_rel)
        if not os.path.exists(src):
            print(f"  warn: bundle source missing for rename target, skipping: {src}")
            continue
        if DRY_RUN:
            print(f"  [dry-run] would rename: {rel} → {new_rel}")
        else:
            os.makedirs(os.path.dirname(new_dst), exist_ok=True)
            shutil.copy2(src, new_dst)
            written += 1
            if os.path.exists(old_dst):
                os.remove(old_dst)
                deleted += 1
                # Clean up empty parents under .claude/ only.
                parent = os.path.dirname(old_dst)
                owned_root = os.path.join(target_root, ".claude")
                while parent.startswith(owned_root) and parent != owned_root:
                    try:
                        if not os.listdir(parent):
                            os.rmdir(parent)
                            parent = os.path.dirname(parent)
                        else:
                            break
                    except OSError:
                        break

# ----- MCP apply -------------------------------------------------------------
# Decide which MCP entries to mutate. Same model as files:
#   - safe_updates: always under APPLY
#   - conflicts: only under --force-conflicts
#   - orphans: only under --prune (removes entry from settings.local.json AND manifest)
mcp_updates = list(mcp_safe_updates)
if FORCE_CONFLICTS:
    mcp_updates.extend(mcp_conflicts)
mcp_skipped_conflicts = 0 if FORCE_CONFLICTS else len(mcp_conflicts)
mcp_deletions = []
if PRUNE:
    mcp_deletions = list(mcp_orphans)

# Tracking: what manifest entries to drop, what new entries to record.
mcp_dropped_names = set()       # names removed under --prune
mcp_refreshed = {}              # name → fresh config_sha256 to write into manifest
mcp_written = 0
mcp_removed = 0

if mcp_updates or mcp_deletions:
    # Reload settings.local.json fresh — we may need to mutate it.
    sl_data = {}
    if os.path.exists(settings_local_path):
        try:
            with open(settings_local_path) as f:
                sl_data = json.load(f)
        except json.JSONDecodeError:
            print(f"  warn: cannot mutate {settings_local_path} — not valid JSON; skipping MCP apply")
            mcp_updates = []
            mcp_deletions = []
    sl_servers = sl_data.setdefault("mcpServers", {}) if sl_data is not None else {}

    for row in mcp_updates:
        name = row["name"]
        bundle_recipe = bundle_recipes.get(name)
        if not bundle_recipe or "config" not in bundle_recipe:
            continue
        new_config = bundle_recipe["config"]
        if DRY_RUN:
            print(f"  [dry-run] would update MCP: {name}")
        else:
            sl_servers[name] = new_config
            mcp_refreshed[name] = mcp_config_hash(new_config)
            mcp_written += 1

    for row in mcp_deletions:
        name = row["name"]
        if DRY_RUN:
            print(f"  [dry-run] would prune MCP: {name}")
        else:
            sl_servers.pop(name, None)
            mcp_dropped_names.add(name)
            mcp_removed += 1

    if not DRY_RUN and (mcp_written or mcp_removed):
        # Write settings.local.json back. Preserve every other top-level key.
        os.makedirs(os.path.dirname(settings_local_path), exist_ok=True)
        with open(settings_local_path, "w") as f:
            json.dump(sl_data, f, indent=2)
            f.write("\n")

if DRY_RUN:
    print(f"==> [DRY RUN] {len(actions)} file action(s) + {len(mcp_updates) + len(mcp_deletions)} MCP action(s) would run; 0 written.")
    if skipped_conflicts:
        print(f"    {skipped_conflicts} file conflict(s) would be SKIPPED — re-run with --force-conflicts to overwrite.")
    if skipped_rename_conflicts:
        print(f"    {skipped_rename_conflicts} rename conflict(s) would be SKIPPED — re-run with --force-conflicts to apply.")
    if mcp_skipped_conflicts:
        print(f"    {mcp_skipped_conflicts} MCP conflict(s) would be SKIPPED — re-run with --force-conflicts to overwrite.")
    sys.exit(0)

# ----- Re-build manifest from current disk state -----------------------------
def sha256_path(p):
    if not os.path.exists(p):
        return None
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()

# Set of rel_paths we just deleted (under --prune OR via the old side of a
# rename) — exclude from new manifest.
deleted_paths = set()
renamed_to_paths = []   # (new_path, src_row) — new entries to add after carry-forward
for kind, r in actions:
    if kind == "delete":
        deleted_paths.add(r["path"])
    elif kind == "rename":
        deleted_paths.add(r["path"])         # old path is gone
        renamed_to_paths.append((r["renamed_to"], r))

# Start by carrying every manifest entry forward UNLESS we deleted it.
# Then layer additions on top. For each carried entry, recompute hash from disk.
new_files = []
seen_paths = set()
for entry in manifest.get("files", []):
    rel = entry["path"]
    if rel in deleted_paths:
        continue
    abs_p = os.path.join(target_root, rel)
    type_ = entry.get("type", "rule")
    if type_ == "gitignore-block":
        # Carry forward unchanged — bash install path manages this block separately.
        new_files.append({
            "path": rel,
            "type": "gitignore-block",
            "category": entry.get("category", "-"),
            "sha256": None,
        })
        seen_paths.add(rel)
        continue
    if not os.path.exists(abs_p):
        # File vanished between plan and apply (or was deleted manually). Drop it.
        continue
    e_out = {
        "path": rel,
        "type": type_,
        "category": entry.get("category", "-"),
        "sha256": sha256_path(abs_p),
    }
    if "skill" in entry:
        e_out["skill"] = entry["skill"]
    new_files.append(e_out)
    seen_paths.add(rel)

# Additions that just landed → record them.
for kind, r in actions:
    if kind != "add":
        continue
    rel = r["path"]
    if rel in seen_paths:
        continue   # already carried forward (shouldn't happen for additions)
    abs_p = os.path.join(target_root, rel)
    if not os.path.exists(abs_p):
        continue
    e_out = {
        "path": rel,
        "type": r.get("type", "rule"),
        "category": r.get("category", "-"),
        "sha256": sha256_path(abs_p),
    }
    if r.get("skill"):
        e_out["skill"] = r["skill"]
    new_files.append(e_out)
    seen_paths.add(rel)

# Renames — record the NEW path with the bundle's metadata (skill name comes
# from the rewritten path's skill dir). Carry-forward already dropped the old
# entry because we added it to deleted_paths above.
for new_rel, src_row in renamed_to_paths:
    if new_rel in seen_paths:
        continue
    abs_p = os.path.join(target_root, new_rel)
    if not os.path.exists(abs_p):
        continue
    bundle_meta = bundle_all.get(new_rel)
    type_ = bundle_meta[0] if bundle_meta else src_row.get("type", "rule")
    cat   = bundle_meta[1] if bundle_meta else src_row.get("category", "-")
    e_out = {
        "path": new_rel,
        "type": type_,
        "category": cat,
        "sha256": sha256_path(abs_p),
    }
    # If the new path is under a skill dir, infer the new skill name from it.
    if new_rel.startswith(".claude/skills/"):
        parts = new_rel.split("/")
        if len(parts) >= 3:
            e_out["skill"] = parts[2]
    new_files.append(e_out)
    seen_paths.add(new_rel)

# Rebuild mcps_installed from the apply outcome:
#   - drop entries pruned under --prune
#   - update config_sha256 for entries we just refreshed (safe-update / force-conflicts)
#   - carry every other entry forward unchanged
new_mcps_installed = []
for installed in manifest.get("mcps_installed", []):
    name = installed["name"]
    if name in mcp_dropped_names:
        continue
    if name in mcp_refreshed:
        new_mcps_installed.append({"name": name, "config_sha256": mcp_refreshed[name]})
    else:
        new_mcps_installed.append(installed)

new_manifest = {
    "schema_version": 2,
    "installed_at": datetime.datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ"),
    "bundle_commit": bundle_commit if bundle_commit else "unknown",
    "selection": {
        "platform": platform,
        "apple_language": apple_lang,
        "features_input": features,
        "features_resolved": manifest.get("selection", {}).get("features_resolved", []),
        "agents_input": agents_input,
        "agents_resolved": agents_resolved,
    },
    "files": new_files,
    "mcps_installed": new_mcps_installed,
}

with open(manifest_path, "w") as f:
    json.dump(new_manifest, f, indent=2)
    f.write("\n")

# ----- Apply summary ---------------------------------------------------------
print(f"==> Apply complete: {written} file(s) written, {deleted} deleted.")
if mcp_written or mcp_removed:
    print(f"    MCPs: {mcp_written} entry(ies) updated, {mcp_removed} pruned.")
if mcp_skipped_conflicts:
    print(f"    {mcp_skipped_conflicts} MCP conflict(s) SKIPPED — re-run with --force-conflicts to overwrite.")
if skipped_conflicts:
    print(f"    {skipped_conflicts} conflict(s) SKIPPED — re-run with --force-conflicts to overwrite.")
print(f"==> Manifest refreshed: {manifest_path}")
PYTHON

    exit 0
fi

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

    python3 - \
        "$manifest_path" "$TARGET" "$settings_local_path" \
        "$FORCE_CONFLICTS" "$PURGE" "$KEEP_MCPS" "$DRY_RUN" \
        <<'PYTHON'
import hashlib, json, os, sys

(manifest_path, target_root, settings_local_path,
 force_flag, purge_flag, keep_mcps_flag, dry_run_flag) = sys.argv[1:8]

FORCE        = (force_flag      == "true")
PURGE        = (purge_flag      == "true")
KEEP_MCPS    = (keep_mcps_flag  == "true")
DRY_RUN      = (dry_run_flag    == "true")

with open(manifest_path) as f:
    manifest = json.load(f)

def sha256_path(p):
    if not os.path.exists(p):
        return None
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()

# ----- Classify each tracked file -------------------------------------------
safe_delete = []     # current hash matches installed hash → delete
user_edited = []     # current hash differs → keep unless --force
user_protected = []  # template / settings → keep unless --purge
missing = []         # already gone from disk

for entry in manifest.get("files", []):
    rel = entry["path"]
    type_ = entry.get("type", "rule")
    installed_hash = entry.get("sha256")
    abs_path = os.path.join(target_root, rel)

    if type_ == "gitignore-block":
        continue  # handled separately below

    if not os.path.exists(abs_path):
        missing.append(rel)
        continue

    if type_ in ("template", "settings"):
        user_protected.append({"path": rel, "type": type_})
        continue

    current_hash = sha256_path(abs_path)
    if installed_hash is None or current_hash == installed_hash:
        safe_delete.append({"path": rel, "type": type_})
    else:
        user_edited.append({"path": rel, "type": type_})

# ----- Print plan -----------------------------------------------------------
def section(title, rows):
    if not rows:
        return
    print(f"  {title} ({len(rows)})")
    for r in rows[:50]:
        path = r["path"] if isinstance(r, dict) else r
        print(f"    {path}")
    if len(rows) > 50:
        print(f"    … and {len(rows) - 50} more")
    print("")

print("")
section("Will delete (unchanged since install):", safe_delete)
section("Locally edited — keep unless --force:", user_edited)
section("User-protected (CLAUDE.md / settings.json) — keep unless --purge:", user_protected)
section("Already absent on disk (will drop from manifest):", missing)

# ----- File deletions -------------------------------------------------------
to_delete = list(safe_delete)
if FORCE:
    to_delete.extend(user_edited)
if PURGE:
    to_delete.extend(user_protected)

print(f"==> Deleting {len(to_delete)} file(s)" + (" [DRY RUN]" if DRY_RUN else "") + "...")
deleted_count = 0
for r in to_delete:
    rel = r["path"] if isinstance(r, dict) else r
    abs_path = os.path.join(target_root, rel)
    if not os.path.exists(abs_path):
        continue
    if DRY_RUN:
        print(f"  [dry-run] would delete: {rel}")
    else:
        os.remove(abs_path)
        deleted_count += 1
        # Clean up empty parent dirs under .claude/ only.
        parent = os.path.dirname(abs_path)
        owned_root = os.path.join(target_root, ".claude")
        while parent.startswith(owned_root) and parent != owned_root:
            try:
                if not os.listdir(parent):
                    os.rmdir(parent)
                    parent = os.path.dirname(parent)
                else:
                    break
            except OSError:
                break

# ----- MCP cleanup ----------------------------------------------------------
def mcp_config_hash(config):
    payload = json.dumps(config, sort_keys=True, separators=(",", ":")).encode()
    return hashlib.sha256(payload).hexdigest()

mcps_removed = 0
mcps_skipped = []   # names left in settings.local.json (modified or missing recipe)

if not KEEP_MCPS and manifest.get("mcps_installed"):
    sl_data = {}
    if os.path.exists(settings_local_path):
        try:
            with open(settings_local_path) as f:
                sl_data = json.load(f)
        except json.JSONDecodeError:
            print(f"  warn: {settings_local_path} not valid JSON; skipping MCP cleanup")
            sl_data = None
    if sl_data is None:
        pass
    else:
        sl_servers = sl_data.get("mcpServers", {}) or {}
        before = dict(sl_servers)
        for installed in manifest["mcps_installed"]:
            name = installed["name"]
            installed_hash = installed.get("config_sha256")
            current_config = sl_servers.get(name)
            if current_config is None:
                continue   # already removed by user
            current_hash = mcp_config_hash(current_config)
            if current_hash == installed_hash or FORCE:
                if DRY_RUN:
                    print(f"  [dry-run] would remove MCP: {name}")
                else:
                    del sl_servers[name]
                    mcps_removed += 1
            else:
                mcps_skipped.append(name)
        if not DRY_RUN and sl_servers != before:
            if sl_servers:
                sl_data["mcpServers"] = sl_servers
            else:
                # If mcpServers ended up empty AND we created it via --with-mcps,
                # drop the key. Other top-level keys (customField, permissions, etc.)
                # stay untouched.
                sl_data.pop("mcpServers", None)
            with open(settings_local_path, "w") as f:
                json.dump(sl_data, f, indent=2)
                f.write("\n")

# ----- .gitignore block + manifest removal ---------------------------------
gitignore_path = os.path.join(target_root, ".gitignore")
gitignore_stripped = False
if os.path.exists(gitignore_path) and not DRY_RUN:
    with open(gitignore_path) as f:
        lines = f.read().splitlines()
    out_lines = []
    in_block = False
    for line in lines:
        if line.startswith("# --- AppBootstrapAI ("):
            in_block = True
            # Also drop a leading blank line if present
            while out_lines and out_lines[-1] == "":
                out_lines.pop()
            continue
        if in_block and line == "# --- end AppBootstrapAI ---":
            in_block = False
            continue
        if not in_block:
            out_lines.append(line)
    new_content = "\n".join(out_lines)
    if new_content and not new_content.endswith("\n"):
        new_content += "\n"
    with open(gitignore_path, "w") as f:
        f.write(new_content)
    gitignore_stripped = True
elif os.path.exists(gitignore_path):
    # dry-run path: just check if there's a block to strip
    with open(gitignore_path) as f:
        if "# --- AppBootstrapAI (" in f.read():
            print("  [dry-run] would strip .gitignore block")

if not DRY_RUN:
    if os.path.exists(manifest_path):
        os.remove(manifest_path)
        # Try to remove .claude/ if now empty.
        claude_dir = os.path.dirname(manifest_path)
        try:
            if not os.listdir(claude_dir):
                os.rmdir(claude_dir)
        except OSError:
            pass

# ----- Summary --------------------------------------------------------------
print("")
if DRY_RUN:
    print(f"==> [DRY RUN] {len(to_delete)} file(s) would be deleted; {mcps_removed} MCP entry(ies) would be removed.")
    if user_edited and not FORCE:
        print(f"    {len(user_edited)} locally-edited file(s) would be KEPT — re-run with --force to remove.")
    if user_protected and not PURGE:
        print(f"    {len(user_protected)} user-protected file(s) (CLAUDE.md / settings.json) would be KEPT — re-run with --purge to remove.")
    if mcps_skipped:
        print(f"    {len(mcps_skipped)} MCP entry(ies) would be KEPT (modified): {', '.join(mcps_skipped)}")
else:
    print(f"==> Uninstall complete: {deleted_count} file(s) deleted, {mcps_removed} MCP entry(ies) removed.")
    if gitignore_stripped:
        print(f"    Stripped AppBootstrapAI block from {gitignore_path}")
    if user_edited and not FORCE:
        print(f"    Kept {len(user_edited)} locally-edited file(s) — re-run with --force to remove.")
    if user_protected and not PURGE:
        print(f"    Kept {len(user_protected)} user-protected file(s) (CLAUDE.md / settings.json) — re-run with --purge to remove.")
    if mcps_skipped:
        print(f"    Kept {len(mcps_skipped)} modified MCP entry(ies): {', '.join(mcps_skipped)}")
PYTHON

    exit 0
fi

# --- Install mode -------------------------------------------------------------

if [[ ! -d "$TARGET" ]]; then
    echo "error: target directory does not exist: $TARGET" >&2
    exit 1
fi

TARGET="$(cd "$TARGET" && pwd)"
echo "==> Installing AppBootstrapAI into $TARGET"
if [[ "$PLATFORM_AUTODETECTED" == "true" ]]; then
    echo "    platform: $PLATFORM (auto-detected)   apple-language: $APPLE_LANG"
    [[ -n "$DETECTED_APPLE_SIGNALS"   ]] && echo "      apple signals:   $DETECTED_APPLE_SIGNALS"
    [[ -n "$DETECTED_ANDROID_SIGNALS" ]] && echo "      android signals: $DETECTED_ANDROID_SIGNALS"
    echo "      (override with --platform apple|android|both)"
elif [[ "$PLATFORM_AUTODETECT_FALLBACK" == "true" ]]; then
    echo "    platform: $PLATFORM (auto-detect found no project files → fallback)   apple-language: $APPLE_LANG"
    echo "      (override with --platform apple|android|both)"
else
    echo "    platform: $PLATFORM   apple-language: $APPLE_LANG"
fi
echo "    features: $FEATURES_INPUT  ($SELECTED_FEATURES)"
echo "    agents:   $SELECTED_AGENTS"
if [[ "$DRY_RUN" == "true" ]]; then
    echo "==> [DRY RUN] No files will be written. Re-run without --dry-run to apply."
fi

# Track installed files for the manifest.
# Entry format: rel_path|type|category|sha256|skill_name
#   rel_path    — path relative to TARGET (e.g. ".claude/rules/foo.md")
#   type        — "rule" | "skill-file" | "settings" | "template" | "gitignore-block"
#   category    — feature category or "-" for uncategorized
#   sha256      — content hash, or empty for non-content entries (gitignore-block)
#   skill_name  — only set for skill-file entries; empty otherwise
#
# Use record_install for single files (hash is computed from source path).
# Use record_install_meta for non-content entries (gitignore block).
INSTALLED_FILES=()
record_install() {
    local rel_path="$1" type_="$2" category="$3" source_path="$4" skill_name="${5:-}"
    local hash
    hash="$(sha256_file "$source_path")"
    INSTALLED_FILES+=("$rel_path|$type_|$category|$hash|$skill_name")
}
record_install_meta() {
    # Non-content entries: no source file to hash.
    local rel_path="$1" type_="$2" category="$3"
    INSTALLED_FILES+=("$rel_path|$type_|$category||")
}

# Track MCP entries that were added/skipped by --with-mcps. Populated by
# install_mcps_now() (called late in the install flow). Used to print setup
# notes and to extend the manifest.
INSTALLED_MCPS_ADDED=()
INSTALLED_MCPS_SKIPPED=()

# The manifest lives at .claude/.appbootstrap-manifest.json regardless of which
# agents are selected. Ensure the dir exists so the late-stage manifest write
# can land even on a non-Claude-only install (e.g., --agents copilot).
act "create $TARGET/.claude (for manifest)" mkdir -p "$TARGET/.claude"

# ----- Claude agent install (default) ----------------------------------------
if agents_has claude; then
    act "create $TARGET/.claude/rules"  mkdir -p "$TARGET/.claude/rules"
    act "create $TARGET/.claude/skills" mkdir -p "$TARGET/.claude/skills"

    # Skills — copy each individually based on platform/language/features filter.
    # Each file inside the skill directory gets its own manifest entry with a hash,
    # so a local edit to one reference doesn't block upstream updates to siblings.
    if should_install_any_skills; then
        echo "--> Copying skills (.claude/skills/)"
        shopt -s nullglob
        for d in "$SCRIPT_DIR/.claude/skills/"*/; do
            name="$(basename "$d")"
            if should_install_skill "$name"; then
                cat="$(file_category "$name")"
                [[ -z "$cat" ]] && cat="-"
                act "copy skill $name" cp -R "$d" "$TARGET/.claude/skills/$name"
                # Walk every file inside the source skill dir; record_install each
                # so the manifest has a per-file hash. `find -type f` includes
                # nested references/, agents/, assets/ — exactly what we copied.
                while IFS= read -r -d '' src_file; do
                    # Strip the SCRIPT_DIR prefix so rel_path is target-relative.
                    rel_path="${src_file#"$SCRIPT_DIR"/}"
                    record_install "$rel_path" "skill-file" "$cat" "$src_file" "$name"
                done < <(find "$d" -type f -print0)
            fi
        done
    else
        echo "--> Skipping skills (not in scope for current selection)"
    fi

    # Rules → .claude/rules/.
    echo "--> Copying rules (.claude/rules/)"
    shopt -s nullglob
    for f in "$SCRIPT_DIR/.claude/rules/"*.md; do
        name="$(basename "$f")"
        if should_install_rule "$name"; then
            cat="$(file_category "$name")"
            [[ -z "$cat" ]] && cat="-"
            act "copy rule $name" cp "$f" "$TARGET/.claude/rules/$name"
            record_install ".claude/rules/$name" "rule" "$cat" "$f"
        fi
    done

    # settings.json — never overwrite.
    if [[ ! -f "$TARGET/.claude/settings.json" ]]; then
        act "copy settings.json" cp "$SCRIPT_DIR/.claude/settings.json" "$TARGET/.claude/settings.json"
        record_install ".claude/settings.json" "settings" "-" "$SCRIPT_DIR/.claude/settings.json"
    else
        echo "--> Skipping settings.json (already exists — merge manually)"
    fi

    # CLAUDE.md — render from the platform-appropriate template, never overwrite.
    case "$PLATFORM" in
        apple)   TEMPLATE="$SCRIPT_DIR/templates/CLAUDE.template.apple.md"   ;;
        android) TEMPLATE="$SCRIPT_DIR/templates/CLAUDE.template.android.md" ;;
        both)    TEMPLATE="$SCRIPT_DIR/templates/CLAUDE.template.md"         ;;
    esac

    if [[ -f "$TARGET/CLAUDE.md" ]]; then
        echo "--> Skipping CLAUDE.md (already exists — merge manually)"
    elif [[ ! -f "$TEMPLATE" ]]; then
        echo "--> Skipping CLAUDE.md (template missing: $TEMPLATE)"
    else
        act "create CLAUDE.md from $(basename "$TEMPLATE")" cp "$TEMPLATE" "$TARGET/CLAUDE.md"
        record_install "CLAUDE.md" "template" "core" "$TEMPLATE"
    fi
fi

# ----- Non-Claude agents ------------------------------------------------------
#
# Each non-Claude agent gets its own set of files derived from the in-scope
# rules. Skills are skipped (Claude-only). Existing files are NEVER
# overwritten — same policy as CLAUDE.md / settings.json.
#
# install_agent_concat <agent_tag> <rel_path> <banner_purpose>
# Writes a deterministic concat to <TARGET>/<rel_path> via concat_in_scope_rules.
install_agent_concat() {
    local agent_tag="$1" rel_path="$2" banner_purpose="$3"
    local dst="$TARGET/$rel_path"
    if [[ -f "$dst" ]]; then
        echo "--> Skipping $rel_path (already exists — merge manually)"
        return
    fi
    # Stage the concat in a temp file so we can:
    #   - hash it
    #   - record it in the manifest with that hash
    #   - move it into place (or skip under dry-run)
    local tmp; tmp="$(mktemp)"
    concat_in_scope_rules "$banner_purpose" > "$tmp"
    act "create $rel_path (concat of in-scope rules)" mkdir -p "$(dirname "$dst")"
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "[dry-run] would write $rel_path ($(wc -l < "$tmp" | tr -d ' ') lines)"
        # Still record under dry-run so the count is accurate.
        record_install "$rel_path" "agent-file-$agent_tag" "-" "$tmp"
    else
        mv "$tmp" "$dst"
        record_install "$rel_path" "agent-file-$agent_tag" "-" "$dst"
    fi
    rm -f "$tmp"
}

if agents_has copilot; then
    echo "--> Installing for GitHub Copilot (.github/copilot-instructions.md)"
    install_agent_concat "copilot" ".github/copilot-instructions.md" "GitHub Copilot"
fi

if agents_has gemini; then
    echo "--> Installing for Gemini CLI (GEMINI.md)"
    install_agent_concat "gemini" "GEMINI.md" "Gemini CLI"
fi

if agents_has codex; then
    echo "--> Installing for Codex / generic agents (AGENTS.md)"
    install_agent_concat "codex" "AGENTS.md" "Codex CLI and other AGENTS.md-aware tools"
fi

if agents_has cursor; then
    # Cursor uses per-rule .mdc files under .cursor/rules/. Direct 1:1 with
    # .claude/rules/, just renamed. Each file gets its own manifest entry
    # so upgrade can diff per-rule (like skill-file does for Claude skills).
    echo "--> Installing for Cursor (.cursor/rules/*.mdc)"
    act "create $TARGET/.cursor/rules" mkdir -p "$TARGET/.cursor/rules"
    shopt -s nullglob
    for f in "$SCRIPT_DIR/.claude/rules/"*.md; do
        name="$(basename "$f")"
        if should_install_rule "$name"; then
            mdc_name="${name%.md}.mdc"
            dst="$TARGET/.cursor/rules/$mdc_name"
            if [[ -f "$dst" ]]; then
                echo "    skipping $mdc_name (already exists)"
                continue
            fi
            cat="$(file_category "$name")"
            [[ -z "$cat" ]] && cat="-"
            act "copy cursor rule $mdc_name" cp "$f" "$dst"
            record_install ".cursor/rules/$mdc_name" "agent-file-cursor" "$cat" "$f"
        fi
    done
fi

# .gitignore — append platform entries, deduped by marker.
GITIGNORE="$TARGET/.gitignore"
MARKER="# --- AppBootstrapAI ($PLATFORM) ---"
if [[ -f "$GITIGNORE" ]] && grep -qF "$MARKER" "$GITIGNORE"; then
    echo "--> Skipping .gitignore (marker already present)"
else
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "[dry-run] would append .gitignore block marked '$MARKER'"
    else
        touch "$GITIGNORE"
        {
            echo ""
            echo "$MARKER"
            if [[ "$PLATFORM" != "android" ]]; then
                cat <<'APPLE'
# Apple / Xcode / SPM
*.DS_Store
*xcuserdata*
DerivedData/
build/
*.ipa
*.dSYM.zip
.build/
.swiftpm/
Package.resolved
Carthage/Build/
fastlane/report.xml
fastlane/test_output
APPLE
            fi
            if [[ "$PLATFORM" != "apple" ]]; then
                cat <<'ANDROID'
# Android / Gradle / Kotlin
.gradle/
build/
*.apk
*.aab
local.properties
keystore.properties
*.jks
*.keystore
.kotlin/
.idea/
*.iml
ANDROID
            fi
            if agents_has claude; then
                echo "# Claude Code local settings"
                echo ".claude/settings.local.json"
                echo ".claude/plans/"
            fi
            if agents_has cursor; then
                echo "# Cursor runtime caches (per-developer; not committed)"
                echo ".cursor/state*"
                echo ".cursor/.cache/"
            fi
            echo "# --- end AppBootstrapAI ---"
        } >> "$GITIGNORE"
        echo "--> Appended recommended .gitignore entries"
    fi
    record_install_meta ".gitignore" "gitignore-block" "-"
fi

# Manifest — records every file the installer wrote (with content hashes,
# under schema v2) so future --upgrade flows can do per-file 3-way diffs:
# installed hash (here) vs. current disk hash vs. bundle hash.
#
# Called at the END of install (after the MCP merge) so mcps_installed reflects
# what actually got written, not what was requested.
MANIFEST_PATH="$TARGET/.claude/.appbootstrap-manifest.json"
TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

write_manifest() {
    {
        printf '{\n'
        printf '  "schema_version": 2,\n'
        printf '  "installed_at": "%s",\n' "$TIMESTAMP"
        printf '  "bundle_commit": "%s",\n' "$BUNDLE_COMMIT"
        printf '  "selection": {\n'
        printf '    "platform": "%s",\n' "$PLATFORM"
        printf '    "apple_language": "%s",\n' "$APPLE_LANG"
        printf '    "features_input": "%s",\n' "$FEATURES_INPUT"
        printf '    "features_resolved": '
        json_string_array "$SELECTED_FEATURES"
        printf ',\n'
        printf '    "agents_input": "%s",\n' "$AGENTS_INPUT"
        printf '    "agents_resolved": '
        json_string_array "$SELECTED_AGENTS"
        printf '\n  },\n'
        printf '  "files": [\n'
        local first=1 entry path type_ cat_ hash skill hash_field
        for entry in "${INSTALLED_FILES[@]}"; do
            # rel_path|type|category|sha256|skill_name
            IFS='|' read -r path type_ cat_ hash skill <<<"$entry"
            if [[ "$first" -eq 1 ]]; then first=0; else printf ',\n'; fi
            # Emit sha256 as null when empty (gitignore-block); JSON string otherwise.
            if [[ -z "$hash" ]]; then
                hash_field='"sha256": null'
            else
                hash_field=$(printf '"sha256": "%s"' "$hash")
            fi
            # Emit "skill" field only for skill-file entries.
            if [[ -n "$skill" ]]; then
                printf '    {"path": "%s", "type": "%s", "category": "%s", %s, "skill": "%s"}' \
                    "$path" "$type_" "$cat_" "$hash_field" "$skill"
            else
                printf '    {"path": "%s", "type": "%s", "category": "%s", %s}' \
                    "$path" "$type_" "$cat_" "$hash_field"
            fi
        done
        printf '\n  ],\n'
        # mcps_installed — array of {name, config_sha256}. Records what we
        # actually wrote into settings.local.json (not what was requested but
        # skipped because already present).
        printf '  "mcps_installed": ['
        first=1
        # Guard the array expansion — `set -u` + bash 3.x errors on "${arr[@]}"
        # when the array is unset/empty.
        if [[ "${#INSTALLED_MCPS_ADDED[@]}" -gt 0 ]]; then
            local mcp_entry mcp_name mcp_hash
            for mcp_entry in "${INSTALLED_MCPS_ADDED[@]}"; do
                mcp_name="${mcp_entry%%|*}"
                mcp_hash="${mcp_entry#*|}"
                if [[ "$first" -eq 1 ]]; then first=0; printf '\n'; else printf ',\n'; fi
                if [[ -z "$mcp_hash" ]]; then
                    printf '    {"name": "%s", "config_sha256": null}' "$mcp_name"
                else
                    printf '    {"name": "%s", "config_sha256": "%s"}' "$mcp_name" "$mcp_hash"
                fi
            done
        fi
        if [[ "$first" -eq 0 ]]; then printf '\n  '; fi
        printf ']\n'
        printf '}\n'
    } > "$MANIFEST_PATH"
    echo "--> Wrote manifest to $MANIFEST_PATH"
}

# --- MCP recipes — merge into .claude/settings.local.json -------------------
#
# Each named recipe contributes one entry under "mcpServers". Existing entries
# with the same name are preserved (never overwritten). settings.local.json is
# the right target because MCP configs often carry machine-specific paths /
# tokens and shouldn't be committed; the file is gitignored by the bundle.

if [[ -n "$SELECTED_MCPS" ]]; then
    SETTINGS_LOCAL="$TARGET/.claude/settings.local.json"
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "[dry-run] would merge MCP recipes into $SETTINGS_LOCAL: $SELECTED_MCPS"
        for mcp_name in $SELECTED_MCPS; do
            # No actual write happens, so no hash. Record name-only entry; the
            # manifest will record an empty hash for these dry-run rows (they
            # won't be in the real manifest because --dry-run skips the write).
            INSTALLED_MCPS_ADDED+=("$mcp_name|")
        done
    else
        echo "--> Merging MCP recipes into $(basename "$SETTINGS_LOCAL"): $SELECTED_MCPS"
        # Python does the JSON merge — safe escaping, dict union, idempotency.
        # Also computes a sha256 of each added recipe's config so the manifest
        # can do 3-way diffs on upgrade (installed config vs. current vs. bundle).
        merge_output="$(python3 - "$SETTINGS_LOCAL" "$MCP_RECIPES_DIR" "$SELECTED_MCPS" <<'PYTHON'
import hashlib, json, os, sys

settings_path, recipes_dir, mcp_names_str = sys.argv[1], sys.argv[2], sys.argv[3]
mcp_names = mcp_names_str.split()

# Load existing settings.local.json or start fresh.
if os.path.exists(settings_path):
    with open(settings_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError as e:
            print(f"ERROR:{settings_path} is not valid JSON: {e}", file=sys.stderr)
            sys.exit(2)
else:
    data = {}

mcps = data.setdefault("mcpServers", {})
added = []        # list of (name, config_sha256)
skipped = []
setup_notes = []  # [(display_name, [step, ...]), ...]

def config_hash(config):
    # Stable hash of the recipe's config blob — sort_keys + compact separators
    # so reformatting the recipe file doesn't change the hash.
    payload = json.dumps(config, sort_keys=True, separators=(",", ":")).encode()
    return hashlib.sha256(payload).hexdigest()

for name in mcp_names:
    recipe_path = os.path.join(recipes_dir, f"{name}.json")
    with open(recipe_path, "r") as f:
        recipe = json.load(f)
    entry_key = recipe["name"]
    if entry_key in mcps:
        skipped.append(entry_key)
        continue
    mcps[entry_key] = recipe["config"]
    added.append((entry_key, config_hash(recipe["config"])))
    if recipe.get("setup"):
        setup_notes.append((recipe.get("display_name", entry_key), recipe["setup"], recipe.get("homepage", "")))

os.makedirs(os.path.dirname(settings_path), exist_ok=True)
with open(settings_path, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")

# Emit machine-parseable result lines for bash to capture.
# ADDED line carries name=hash pairs separated by commas.
print("ADDED:" + ",".join(f"{n}={h}" for n, h in added))
print("SKIPPED:" + ",".join(skipped))
for display, steps, homepage in setup_notes:
    print("---SETUP---")
    print(f"NAME:{display}")
    if homepage:
        print(f"HOMEPAGE:{homepage}")
    for step in steps:
        print(f"STEP:{step}")
PYTHON
)"
        # Parse the python output back into bash arrays.
        while IFS= read -r line; do
            case "$line" in
                ADDED:*)
                    # Format: ADDED:name1=hash1,name2=hash2
                    added_csv="${line#ADDED:}"
                    if [[ -n "$added_csv" ]]; then
                        # shellcheck disable=SC2206
                        IFS=',' read -r -a tmp <<<"$added_csv"
                        for entry in "${tmp[@]}"; do
                            # Convert "name=hash" → "name|hash" for our array form.
                            INSTALLED_MCPS_ADDED+=("${entry/=/|}")
                        done
                    fi
                    ;;
                SKIPPED:*)
                    skipped_csv="${line#SKIPPED:}"
                    if [[ -n "$skipped_csv" ]]; then
                        IFS=',' read -r -a tmp <<<"$skipped_csv"
                        for entry in "${tmp[@]}"; do
                            INSTALLED_MCPS_SKIPPED+=("$entry")
                        done
                    fi
                    ;;
            esac
        done <<<"$merge_output"

        if [[ "${#INSTALLED_MCPS_ADDED[@]}" -gt 0 ]]; then
            # Entries are "name|hash" — strip hash for human display.
            added_display=""
            for entry in "${INSTALLED_MCPS_ADDED[@]}"; do
                added_display="$added_display ${entry%%|*}"
            done
            echo "    added:${added_display}"
        fi
        if [[ "${#INSTALLED_MCPS_SKIPPED[@]}" -gt 0 ]]; then
            echo "    skipped (already present): ${INSTALLED_MCPS_SKIPPED[*]}"
        fi

        # Re-print the setup notes verbatim from the python output.
        if echo "$merge_output" | grep -q "^---SETUP---"; then
            echo ""
            echo "==> Setup steps for newly-installed MCPs:"
            current=""
            while IFS= read -r line; do
                case "$line" in
                    ---SETUP---) echo "" ;;
                    NAME:*)
                        current="${line#NAME:}"
                        echo "    $current"
                        ;;
                    HOMEPAGE:*) echo "      (see $(echo "$line" | sed 's|^HOMEPAGE:||'))" ;;
                    STEP:*) echo "      - $(echo "$line" | sed 's|^STEP:||')" ;;
                esac
            done <<<"$merge_output"
        fi
    fi
fi

# Manifest write — runs last so mcps_installed reflects the MCP merge result.
if [[ "$DRY_RUN" == "true" ]]; then
    echo "[dry-run] would write manifest ($MANIFEST_PATH, ${#INSTALLED_FILES[@]} entries)"
else
    write_manifest
fi

echo ""
if [[ "$DRY_RUN" == "true" ]]; then
    echo "==> [DRY RUN] Complete. ${#INSTALLED_FILES[@]} file(s) would be installed. Re-run without --dry-run to apply."
else
    echo "==> Done. Next steps:"
    step=1
    if agents_has claude; then
        echo "    $step. Edit $TARGET/CLAUDE.md — fill in the <PLACEHOLDER> sections."
        step=$((step + 1))
    fi
    if agents_has copilot && [[ -f "$TARGET/.github/copilot-instructions.md" ]]; then
        echo "    $step. Review $TARGET/.github/copilot-instructions.md (generated; commit alongside your rules)."
        step=$((step + 1))
    fi
    if agents_has gemini && [[ -f "$TARGET/GEMINI.md" ]]; then
        echo "    $step. Review $TARGET/GEMINI.md (generated; commit alongside your rules)."
        step=$((step + 1))
    fi
    if agents_has codex && [[ -f "$TARGET/AGENTS.md" ]]; then
        echo "    $step. Review $TARGET/AGENTS.md (generated; commit alongside your rules)."
        step=$((step + 1))
    fi
    echo "    $step. Review $TARGET/.gitignore for merge conflicts."
    step=$((step + 1))
    echo "    $step. Commit the new files."
fi
echo ""
echo "Tip: \`./install.sh --list\`  (with the same flags) — preview catalog as text."
echo "     \`./install.sh --list --json\`  — same catalog as JSON for automation."
echo "     \`./install.sh --dry-run ...\`  — show what would install without writing."
echo "     Opt into more with \`--features all\` or e.g. \`--features recommended,persistence,ai\`."

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
