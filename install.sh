#!/usr/bin/env bash
# AppBootstrapAI installer — copies the Claude Code bundle into a target repo.
#
# Usage:
#   ./install.sh [TARGET_DIR] [--platform apple|android|both]
#                             [--apple-language swift|objc|both]
#   ./install.sh --list
#   ./install.sh --help
#
# Defaults: TARGET_DIR=.  --platform both  --apple-language swift
#
# Flags:
#   --platform           Which platform's rules and skills to install.
#                        - apple   → install apple-* rules + skills
#                        - android → install android-* rules (no skills yet)
#                        - both    → install everything
#   --apple-language     When --platform is apple or both, narrows the Apple
#                        side to a specific language:
#                        - swift (default) → all apple- rules except apple-objc-*
#                                            + all skills (skills are Swift-tied)
#                        - objc            → apple-objc-* only, no skills
#                        - both            → all apple- rules + all skills
#   --list               Print the catalog of available rules and skills with
#                        one-line descriptions, and exit. Use this to see what
#                        a given --platform / --apple-language combo would
#                        actually install.
#   -h, --help           Print this help and exit.
#
# What it does:
#   - Copies .claude/skills/ when the platform/language combo includes Swift.
#   - Copies .claude/rules/ matching the chosen platform and language.
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
        --list)
            ACTION="list"
            shift
            ;;
        -h|--help)
            sed -n '2,42p' "${BASH_SOURCE[0]}"
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

# --- Inclusion predicates -----------------------------------------------------
# Decide whether a given rule file should be installed for the current
# (PLATFORM, APPLE_LANG) combo.

should_install_rule() {
    local name="$1"
    case "$name" in
        apple-objc-*)
            # ObjC rule: include only if Apple is in scope AND language permits objc.
            [[ "$PLATFORM" != "android" ]] && [[ "$APPLE_LANG" != "swift" ]]
            ;;
        apple-*)
            # Other apple-* rules are Swift-side: include if Apple in scope and
            # language is swift or both (not objc-only).
            [[ "$PLATFORM" != "android" ]] && [[ "$APPLE_LANG" != "objc" ]]
            ;;
        android-*)
            [[ "$PLATFORM" != "apple" ]]
            ;;
        *)
            # Unprefixed rules: include for both platforms.
            true
            ;;
    esac
}

# Per-skill inclusion. Apple/Swift skills install when Apple+Swift is in scope;
# Android skills install when Android is in scope. apple-language=objc skips
# all skills (Apple skills are Swift-only; Android skills aren't ObjC-relevant).
should_install_skill() {
    local name="$1"
    case "$name" in
        android-*|xml-to-compose-*|r8-shrink-*)
            # Android skill — install when Android is in scope.
            [[ "$PLATFORM" != "apple" ]]
            ;;
        *)
            # Apple/Swift skill — install when Apple+Swift is in scope.
            [[ "$PLATFORM" != "android" ]] && [[ "$APPLE_LANG" != "objc" ]]
            ;;
    esac
}

# Whether ANY skills will install — drives the "Copying skills" log message
# and the `--list` "skills installed" marker.
should_install_any_skills() {
    shopt -s nullglob
    for d in "$SCRIPT_DIR/.claude/skills/"*/; do
        if should_install_skill "$(basename "$d")"; then
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

# Pull the `description:` line out of a skill's SKILL.md.
skill_description() {
    rule_description "$1/SKILL.md"
}

# --- --list mode --------------------------------------------------------------

if [[ "$ACTION" == "list" ]]; then
    echo "AppBootstrapAI catalog"
    echo "  current selection: --platform $PLATFORM --apple-language $APPLE_LANG"
    echo ""
    echo "Rules:"
    shopt -s nullglob
    for f in "$SCRIPT_DIR/.claude/rules/"*.md; do
        name="$(basename "$f")"
        if should_install_rule "$name"; then mark="✓"; else mark=" "; fi
        printf "  [%s] %s\n        %s\n" "$mark" "$name" "$(rule_description "$f")"
    done
    echo ""
    echo "Skills:"
    for d in "$SCRIPT_DIR/.claude/skills/"*/; do
        name="$(basename "$d")"
        if should_install_skill "$name"; then mark="✓"; else mark=" "; fi
        printf "  [%s] %s\n        %s\n" "$mark" "$name" "$(skill_description "$d")"
    done
    echo ""
    echo "Legend: [✓] = installed under current selection, [ ] = skipped."
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

mkdir -p "$TARGET/.claude/rules" "$TARGET/.claude/skills"

# Skills — copy each individually based on platform/language filter.
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
