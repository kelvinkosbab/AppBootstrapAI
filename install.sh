#!/usr/bin/env bash
# AppBootstrapAI installer — copies the Claude Code bundle into a target repo.
#
# Usage:
#   ./install.sh [TARGET_DIR] [--platform apple|android|both]
#
# Defaults: TARGET_DIR=.  --platform both
#
# What it does:
#   - Copies .claude/skills/ (Apple skills)
#   - Copies .claude/rules/ matching the chosen platform
#   - Copies .claude/settings.json if none exists in TARGET_DIR
#   - Renders templates/CLAUDE.template.md into TARGET_DIR/CLAUDE.md (only if
#     CLAUDE.md does not already exist — it never overwrites)
#   - Appends recommended .gitignore entries for the chosen platform(s)
#
# It never overwrites an existing CLAUDE.md or settings.json; it prints what it
# skipped so you can merge manually.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="${1:-.}"
PLATFORM="both"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --platform)
            PLATFORM="$2"
            shift 2
            ;;
        -h|--help)
            sed -n '2,20p' "${BASH_SOURCE[0]}"
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
        echo "error: --platform must be apple, android, or both" >&2
        exit 1
        ;;
esac

if [[ ! -d "$TARGET" ]]; then
    echo "error: target directory does not exist: $TARGET" >&2
    exit 1
fi

TARGET="$(cd "$TARGET" && pwd)"
echo "==> Installing AppBootstrapAI into $TARGET (platform: $PLATFORM)"

mkdir -p "$TARGET/.claude/rules" "$TARGET/.claude/skills"

# Skills: currently Apple-only; copy for apple or both.
if [[ "$PLATFORM" != "android" ]]; then
    echo "--> Copying skills"
    cp -R "$SCRIPT_DIR/.claude/skills/." "$TARGET/.claude/skills/"
fi

# Rules: copy platform-matching files.
echo "--> Copying rules"
shopt -s nullglob
for f in "$SCRIPT_DIR/.claude/rules/"*.md; do
    name="$(basename "$f")"
    case "$PLATFORM:$name" in
        apple:apple-*|android:android-*|both:*)
            cp "$f" "$TARGET/.claude/rules/$name"
            ;;
    esac
done

# settings.json — never overwrite.
if [[ ! -f "$TARGET/.claude/settings.json" ]]; then
    echo "--> Copying settings.json"
    cp "$SCRIPT_DIR/.claude/settings.json" "$TARGET/.claude/settings.json"
else
    echo "--> Skipping settings.json (already exists — merge manually)"
fi

# CLAUDE.md — render from template, never overwrite.
if [[ ! -f "$TARGET/CLAUDE.md" ]] && [[ -f "$SCRIPT_DIR/templates/CLAUDE.template.md" ]]; then
    echo "--> Creating CLAUDE.md from template (edit the placeholders)"
    cp "$SCRIPT_DIR/templates/CLAUDE.template.md" "$TARGET/CLAUDE.md"
else
    echo "--> Skipping CLAUDE.md (already exists or template missing)"
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
