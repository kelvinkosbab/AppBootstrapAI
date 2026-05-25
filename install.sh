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
#                        and print an upgrade plan (no files written). Reads
#                        the manifest at .claude/.appbootstrap-manifest.json
#                        and classifies every tracked file into one of:
#                          - up to date (installed hash matches bundle)
#                          - safe update (no local edits, bundle has new content)
#                          - local edits (file modified after install — left alone)
#                          - conflict (both local and bundle changed)
#                          - retired (file removed upstream — orphan)
#                          - addition (new in bundle, fits --features)
#                          - renamed (via RENAMES.md)
#                        Requires schema_version 2 manifest; v1 manifests
#                        (older installs without hashes) get a migration hint.
#                        This is plan-only — Phase 3 will add --apply.
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
ACTION="install"
DRY_RUN="false"
JSON_OUTPUT="false"

# Track whether the user explicitly passed each flag. Used by --upgrade to
# inherit selection from the manifest when the user didn't override.
APPLE_LANG_EXPLICIT="false"
FEATURES_EXPLICIT="false"

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
        --with-mcps)
            WITH_MCPS="$2"
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
            sed -n '2,121p' "${BASH_SOURCE[0]}"
            exit 0
            ;;
        *)
            TARGET="$1"
            shift
            ;;
    esac
done

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
# Print pipe-separated: platform|apple_language|features_input
print(f"{s.get('platform','')}|{s.get('apple_language','')}|{s.get('features_input','')}")
PYTHON
        )"; then
            IFS='|' read -r m_platform m_apple m_features <<<"$inherited"
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
        echo "    selection (inherited from manifest): --platform $PLATFORM --apple-language $APPLE_LANG --features $FEATURES_INPUT"
        echo "    (override any of these on the command line to opt into new categories)"
    else
        echo "    selection: --platform $PLATFORM --apple-language $APPLE_LANG --features $FEATURES_INPUT"
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
    # shellcheck disable=SC2064
    trap "rm -f '$bundle_all_tmp' '$bundle_in_scope_tmp'" EXIT

    # Rules.
    shopt -s nullglob
    for f in "$SCRIPT_DIR/.claude/rules/"*.md; do
        name="$(basename "$f")"
        cat="$(file_category "$name")"; [[ -z "$cat" ]] && cat="-"
        hash="$(sha256_file "$f")"
        rel_path=".claude/rules/$name"
        echo "$rel_path|rule|$cat|$hash|" >> "$bundle_all_tmp"
        if should_install_rule "$name"; then
            echo "$rel_path" >> "$bundle_in_scope_tmp"
        fi
    done

    # Skill files (one entry per file inside each skill dir).
    for d in "$SCRIPT_DIR/.claude/skills/"*/; do
        skill_name="$(basename "$d")"
        cat="$(file_category "$skill_name")"; [[ -z "$cat" ]] && cat="-"
        skill_in_scope="false"
        if should_install_skill "$skill_name"; then skill_in_scope="true"; fi
        while IFS= read -r -d '' src_file; do
            rel_path="${src_file#"$SCRIPT_DIR"/}"
            hash="$(sha256_file "$src_file")"
            echo "$rel_path|skill-file|$cat|$hash|$skill_name" >> "$bundle_all_tmp"
            if [[ "$skill_in_scope" == "true" ]]; then
                echo "$rel_path" >> "$bundle_in_scope_tmp"
            fi
        done < <(find "$d" -type f -print0)
    done

    # settings.json — always considered in scope (install path always tries
    # to write it, even if it skips because the target already has one).
    settings_hash="$(sha256_file "$SCRIPT_DIR/.claude/settings.json")"
    echo ".claude/settings.json|settings|-|$settings_hash|" >> "$bundle_all_tmp"
    echo ".claude/settings.json" >> "$bundle_in_scope_tmp"

    # CLAUDE.md template — platform-specific. We don't auto-update it, but we
    # still want to surface "template changed" in the plan output.
    case "$PLATFORM" in
        apple)   TEMPLATE_PATH="templates/CLAUDE.template.apple.md"   ;;
        android) TEMPLATE_PATH="templates/CLAUDE.template.android.md" ;;
        both)    TEMPLATE_PATH="templates/CLAUDE.template.md"         ;;
    esac
    template_hash="$(sha256_file "$SCRIPT_DIR/$TEMPLATE_PATH")"
    # The user's file on disk is CLAUDE.md; we tag the bundle-side path so the
    # plan can show "templates/CLAUDE.template.apple.md → CLAUDE.md".
    echo "CLAUDE.md|template|core|$template_hash|$TEMPLATE_PATH" >> "$bundle_all_tmp"
    echo "CLAUDE.md" >> "$bundle_in_scope_tmp"

    # RENAMES.md path (may not exist; Python tolerates missing file).
    renames_path="$SCRIPT_DIR/RENAMES.md"

    python3 - \
        "$manifest_path" "$TARGET" "$bundle_all_tmp" "$bundle_in_scope_tmp" "$renames_path" \
        "$PLATFORM" "$APPLE_LANG" "$FEATURES_INPUT" \
        <<'PYTHON'
import hashlib, json, os, sys

manifest_path, target_root, bundle_all_path, in_scope_path, renames_path, platform, apple_lang, features = sys.argv[1:9]

# ----- Read manifest --------------------------------------------------------
with open(manifest_path) as f:
    manifest = json.load(f)

schema = manifest.get("schema_version", 1)

if schema == 1:
    print("==> Manifest is schema v1 (no content hashes recorded at install).")
    print("    The plan-and-apply upgrade flow needs hashes to safely diff your tree.")
    print("")
    print("    Two ways forward:")
    print("    1. Re-run install.sh (without --upgrade) to write a fresh v2 manifest.")
    print("       Existing files are not overwritten — settings.json, CLAUDE.md, and")
    print("       any rules you edited are preserved (the installer never overwrites).")
    print("       This is the lowest-risk path.")
    print("")
    print("    2. (Future) --upgrade --apply --migrate-manifest will rewrite the")
    print("       manifest from current disk contents as a v2 baseline. Not yet implemented.")
    print("")
    print("    Aborting plan — no v1 → v2 hash inference at this point.")
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
renames = {}  # old_path → new_path (always tracked at rel_path granularity)
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
            # If basename looks like a file (.md) keep as-is; if it's a bare
            # skill dir name, expand to the skill directory namespace. We
            # store both forms — rule rename is a single file; skill rename
            # would need per-file mapping which we don't have without a
            # listing of the OLD skill's files, so for now we only honor
            # rule renames (skills can be done in Phase 3).
            if old.endswith(".md") and new.endswith(".md"):
                renames[f".claude/rules/{old}"] = f".claude/rules/{new}"
            # else: skip — skill-dir renames need Phase 3 support

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
renamed_rows = []  # (old_path, new_path, classification)

manifest_paths = set()
for entry in manifest.get("files", []):
    rel = entry["path"]
    manifest_paths.add(rel)
    installed_hash = entry.get("sha256")
    abs_path = os.path.join(target_root, rel)
    current_hash = sha256_path(abs_path) if installed_hash is not None else None

    # Rename: if this path maps via RENAMES, follow the chain.
    rename_target = rel
    while rename_target in renames:
        rename_target = renames[rename_target]
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
    # Special handling for CLAUDE.md: we never auto-update.
    if entry.get("type") == "template":
        if installed_hash == bundle_hash:
            up_to_date.append({"path": rel, "type": "template"})
        else:
            # CLAUDE.md is the user's; just note that the template has advanced.
            local_edits.append({
                "path": rel,
                "type": "template",
                "note": f"CLAUDE.md is yours — but {bundle_info[3]} has changed upstream. Diff manually if you want the new boilerplate.",
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
        if is_renamed:
            renamed_rows.append((rel, rename_target, "safe-update"))
    elif installed_hash == bundle_hash:
        # Bundle unchanged from install, but disk differs → local edit only.
        local_edits.append(row)
    else:
        # current, installed, and bundle all differ → true conflict.
        conflicts.append(row)
        if is_renamed:
            renamed_rows.append((rel, rename_target, "conflict"))

# ----- Additions: bundle in-scope, not in manifest --------------------------
# (Skip rename targets — they're already accounted for as renames of an existing path.)
rename_targets = set(renames.values())
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

bundle_commit = manifest.get("bundle_commit", "unknown")
print(f"  installed bundle commit: {bundle_commit[:12] if bundle_commit != 'unknown' else 'unknown'}")
print(f"  installed at:            {manifest.get('installed_at', '?')}")
print("")

header("Up to date (no action needed):", up_to_date)
header("Safe to update (no local edits, bundle has new content):", safe_updates)
header("Locally edited (left alone — your changes win):", local_edits)
header("Conflict (both local AND bundle changed — default SKIP, --force-conflicts to overwrite):", conflicts)
header("Out of scope (manifest tracks, current --features doesn't include):", out_of_scope)
header("Retired upstream (bundle no longer ships these files):", [{"path": o["path"], "type": o["type"]} for o in orphans])
header("Would add (new in bundle, fits current --features):", additions)

if renamed_rows:
    print(f"  Renames detected ({len(renamed_rows)}):")
    for old, new, cls in renamed_rows:
        print(f"    {old} → {new}  ({cls})")
    print("")

# Summary line
total_actions = len(safe_updates) + len(conflicts) + len(orphans) + len(additions)
print(f"==> Plan: {len(safe_updates)} safe update(s), {len(conflicts)} conflict(s),")
print(f"          {len(orphans)} orphan(s), {len(additions)} addition(s),")
print(f"          {len(local_edits)} locally-edited (untouched), {len(up_to_date)} up to date.")
print("")
print("This is a plan-only preview. No files have been written.")
print("Phase 3 will add --upgrade --apply to execute it.")
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

act "create $TARGET/.claude/rules"  mkdir -p "$TARGET/.claude/rules"
act "create $TARGET/.claude/skills" mkdir -p "$TARGET/.claude/skills"

# Skills — copy each individually based on platform/language/features filter.
# Each file inside the skill directory gets its own manifest entry with a hash,
# so a local edit to one reference doesn't block upstream updates to siblings.
if should_install_any_skills; then
    echo "--> Copying skills"
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

# Rules.
echo "--> Copying rules"
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
            echo "# Claude Code local settings"
            echo ".claude/settings.local.json"
            echo ".claude/plans/"
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

# Best-effort: capture the AppBootstrapAI git HEAD. Falls back to "unknown" if
# the bundle was extracted from a tarball or git isn't on PATH. Purely informational —
# the upgrade flow uses content hashes, not commit SHAs.
if command -v git >/dev/null 2>&1; then
    BUNDLE_COMMIT="$(git -C "$SCRIPT_DIR" rev-parse HEAD 2>/dev/null || echo "unknown")"
else
    BUNDLE_COMMIT="unknown"
fi

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
    echo "    1. Edit $TARGET/CLAUDE.md — fill in the <PLACEHOLDER> sections."
    echo "    2. Review $TARGET/.gitignore for merge conflicts."
    echo "    3. Commit the new files."
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
