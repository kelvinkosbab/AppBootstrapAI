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

# --- Argument parsing ---------------------------------------------------------

while [[ $# -gt 0 ]]; do
    case "$1" in
        --platform)
            PLATFORM="$2"
            shift 2
            ;;
        --apple-language)
            APPLE_LANG="$2"
            shift 2
            ;;
        --features)
            FEATURES_INPUT="$2"
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
            sed -n '2,99p' "${BASH_SOURCE[0]}"
            exit 0
            ;;
        *)
            TARGET="$1"
            shift
            ;;
    esac
done

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

# Track installed files for the manifest. Entry format: path|type|category
INSTALLED_FILES=()
record_install() {
    INSTALLED_FILES+=("$1|$2|$3")
}

# Track MCP entries that were added/skipped by --with-mcps. Populated by
# install_mcps_now() (called late in the install flow). Used to print setup
# notes and to extend the manifest.
INSTALLED_MCPS_ADDED=()
INSTALLED_MCPS_SKIPPED=()

act "create $TARGET/.claude/rules"  mkdir -p "$TARGET/.claude/rules"
act "create $TARGET/.claude/skills" mkdir -p "$TARGET/.claude/skills"

# Skills — copy each individually based on platform/language/features filter.
if should_install_any_skills; then
    echo "--> Copying skills"
    shopt -s nullglob
    for d in "$SCRIPT_DIR/.claude/skills/"*/; do
        name="$(basename "$d")"
        if should_install_skill "$name"; then
            cat="$(file_category "$name")"
            [[ -z "$cat" ]] && cat="-"
            act "copy skill $name" cp -R "$d" "$TARGET/.claude/skills/$name"
            record_install ".claude/skills/$name" "skill" "$cat"
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
        record_install ".claude/rules/$name" "rule" "$cat"
    fi
done

# settings.json — never overwrite.
if [[ ! -f "$TARGET/.claude/settings.json" ]]; then
    act "copy settings.json" cp "$SCRIPT_DIR/.claude/settings.json" "$TARGET/.claude/settings.json"
    record_install ".claude/settings.json" "settings" "-"
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
    record_install "CLAUDE.md" "template" "core"
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
    record_install ".gitignore" "gitignore-block" "-"
fi

# Manifest — records every file the installer wrote, so a future
# --upgrade or --uninstall flow can act on it.
MANIFEST_PATH="$TARGET/.claude/.appbootstrap-manifest.json"
TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
if [[ "$DRY_RUN" == "true" ]]; then
    echo "[dry-run] would write manifest ($MANIFEST_PATH, ${#INSTALLED_FILES[@]} entries)"
else
    {
        printf '{\n'
        printf '  "schema_version": 1,\n'
        printf '  "installed_at": "%s",\n' "$TIMESTAMP"
        printf '  "selection": {\n'
        printf '    "platform": "%s",\n' "$PLATFORM"
        printf '    "apple_language": "%s",\n' "$APPLE_LANG"
        printf '    "features_input": "%s",\n' "$FEATURES_INPUT"
        printf '    "features_resolved": '
        json_string_array "$SELECTED_FEATURES"
        printf '\n  },\n'
        printf '  "files": [\n'
        first=1
        for entry in "${INSTALLED_FILES[@]}"; do
            path="${entry%%|*}"
            rest="${entry#*|}"
            type_="${rest%%|*}"
            cat_="${rest#*|}"
            if [[ "$first" -eq 1 ]]; then first=0; else printf ',\n'; fi
            printf '    {"path": "%s", "type": "%s", "category": "%s"}' "$path" "$type_" "$cat_"
        done
        printf '\n  ],\n'
        printf '  "mcps_requested": '
        json_string_array "$SELECTED_MCPS"
        printf '\n}\n'
    } > "$MANIFEST_PATH"
    echo "--> Wrote manifest to $MANIFEST_PATH"
fi

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
            INSTALLED_MCPS_ADDED+=("$mcp_name")
        done
    else
        echo "--> Merging MCP recipes into $(basename "$SETTINGS_LOCAL"): $SELECTED_MCPS"
        # Python does the JSON merge — safe escaping, dict union, idempotency.
        merge_output="$(python3 - "$SETTINGS_LOCAL" "$MCP_RECIPES_DIR" "$SELECTED_MCPS" <<'PYTHON'
import json, os, sys

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
added = []
skipped = []
setup_notes = []  # [(display_name, [step, ...]), ...]

for name in mcp_names:
    recipe_path = os.path.join(recipes_dir, f"{name}.json")
    with open(recipe_path, "r") as f:
        recipe = json.load(f)
    entry_key = recipe["name"]
    if entry_key in mcps:
        skipped.append(entry_key)
        continue
    mcps[entry_key] = recipe["config"]
    added.append(entry_key)
    if recipe.get("setup"):
        setup_notes.append((recipe.get("display_name", entry_key), recipe["setup"], recipe.get("homepage", "")))

os.makedirs(os.path.dirname(settings_path), exist_ok=True)
with open(settings_path, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")

# Emit machine-parseable result lines for bash to capture.
print("ADDED:" + ",".join(added))
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
                    added_csv="${line#ADDED:}"
                    if [[ -n "$added_csv" ]]; then
                        # shellcheck disable=SC2206
                        IFS=',' read -r -a tmp <<<"$added_csv"
                        for entry in "${tmp[@]}"; do
                            INSTALLED_MCPS_ADDED+=("$entry")
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
            echo "    added: ${INSTALLED_MCPS_ADDED[*]}"
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
