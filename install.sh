#!/usr/bin/env bash
# AppBootstrapAI installer — copies the Claude Code bundle into a target repo.
#
# Usage:
#   ./install.sh [TARGET_DIR] [--platform apple|android|both]
#                             [--apple-language swift|objc|both]
#                             [--features all|recommended|<csv>]
#   ./install.sh --list [--features ...] [--platform ...]
#   ./install.sh --help
#
# Defaults: TARGET_DIR=.  --platform both  --apple-language swift
#           --features recommended
#
# Flags:
#   --platform           Which platform's rules and skills to install.
#                        - apple   → install apple-* rules + Apple skills
#                        - android → install android-* rules + Android skills
#                        - both    → install everything (intersected with --features)
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
#   --list               Print the catalog of available rules and skills with
#                        one-line descriptions and category tags, and exit.
#                        Use this to preview what a given flag combo would install.
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
#
# It never overwrites an existing CLAUDE.md or settings.json; it prints what
# it skipped so you can merge manually.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="${1:-.}"
PLATFORM="both"
APPLE_LANG="swift"
FEATURES_INPUT="recommended"
ACTION="install"

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
        -h|--help)
            sed -n '2,77p' "${BASH_SOURCE[0]}"
            exit 0
            ;;
        *)
            TARGET="$1"
            shift
            ;;
    esac
done

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

# --- Feature categories -------------------------------------------------------

ALL_CATEGORIES="core concurrency ui testing docs error-handling packaging logging localization persistence ai migration shrinking"
RECOMMENDED_CATEGORIES="core concurrency ui testing docs error-handling packaging logging localization"

# Resolve --features input into a space-separated list of category names.
resolve_features() {
    case "$1" in
        all)         echo "$ALL_CATEGORIES" ;;
        recommended) echo "$RECOMMENDED_CATEGORIES" ;;
        *)           echo "$1" | tr ',' ' ' ;;
    esac
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
        apple-swiftui-mvvm.md|apple-accessibility-best-practices.md|swiftui-pro|android-compose-best-practices.md|android-accessibility-best-practices.md)
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
        apple-objc-*)
            # ObjC rule: include only if Apple is in scope AND language permits objc.
            # --features doesn't gate this — only --apple-language.
            [[ "$PLATFORM" != "android" ]] && [[ "$APPLE_LANG" != "swift" ]]
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

# --- --list mode --------------------------------------------------------------

if [[ "$ACTION" == "list" ]]; then
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
    exit 0
fi

# --- Install mode -------------------------------------------------------------

if [[ ! -d "$TARGET" ]]; then
    echo "error: target directory does not exist: $TARGET" >&2
    exit 1
fi

TARGET="$(cd "$TARGET" && pwd)"
echo "==> Installing AppBootstrapAI into $TARGET"
echo "    platform: $PLATFORM   apple-language: $APPLE_LANG"
echo "    features: $FEATURES_INPUT  ($SELECTED_FEATURES)"

mkdir -p "$TARGET/.claude/rules" "$TARGET/.claude/skills"

# Skills — copy each individually based on platform/language/features filter.
if should_install_any_skills; then
    echo "--> Copying skills"
    shopt -s nullglob
    for d in "$SCRIPT_DIR/.claude/skills/"*/; do
        name="$(basename "$d")"
        if should_install_skill "$name"; then
            cp -R "$d" "$TARGET/.claude/skills/$name"
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
        cp "$f" "$TARGET/.claude/rules/$name"
    fi
done

# settings.json — never overwrite.
if [[ ! -f "$TARGET/.claude/settings.json" ]]; then
    echo "--> Copying settings.json"
    cp "$SCRIPT_DIR/.claude/settings.json" "$TARGET/.claude/settings.json"
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
    echo "--> Creating CLAUDE.md from $(basename "$TEMPLATE") (edit the placeholders)"
    cp "$TEMPLATE" "$TARGET/CLAUDE.md"
fi

# .gitignore — append platform entries, deduped by marker.
GITIGNORE="$TARGET/.gitignore"
touch "$GITIGNORE"
MARKER="# --- AppBootstrapAI ($PLATFORM) ---"
if ! grep -qF "$MARKER" "$GITIGNORE"; then
    echo "--> Appending recommended .gitignore entries"
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
else
    echo "--> Skipping .gitignore (marker already present)"
fi

echo ""
echo "==> Done. Next steps:"
echo "    1. Edit $TARGET/CLAUDE.md — fill in the <PLACEHOLDER> sections."
echo "    2. Review $TARGET/.gitignore for merge conflicts."
echo "    3. Commit the new files."
echo ""
echo "Tip: run \`./install.sh --list\` (with the same flags) to see what was installed."
echo "     Opt into more with \`--features all\` or e.g. \`--features recommended,persistence,ai\`."
