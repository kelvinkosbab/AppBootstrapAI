#!/usr/bin/env bash
# install-smoke-test.sh — verify install.sh produces the expected files
# under each --platform / --apple-language combination.
#
# Runs install.sh against a scratch directory for each combo and asserts:
#   - the right rules are present and the wrong ones are not
#   - skills are installed (or correctly skipped) per Apple/Swift inclusion
#   - the right CLAUDE template was selected
#   - settings.json and .gitignore landed
#
# Exits 1 on the first failed assertion. Run from the repo root.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
INSTALL="$REPO_ROOT/install.sh"
PASS=0
FAIL=0

bold() { printf '\033[1m%s\033[0m\n' "$*"; }
red()  { printf '\033[31m%s\033[0m\n' "$*"; }
green(){ printf '\033[32m%s\033[0m\n' "$*"; }

assert_file_exists() {
    local file="$1" why="$2"
    if [[ -f "$file" ]]; then
        PASS=$((PASS + 1))
    else
        red "FAIL: expected file missing — $file  ($why)"
        FAIL=$((FAIL + 1))
    fi
}

assert_file_absent() {
    local file="$1" why="$2"
    if [[ ! -f "$file" ]]; then
        PASS=$((PASS + 1))
    else
        red "FAIL: file should be absent but is present — $file  ($why)"
        FAIL=$((FAIL + 1))
    fi
}

assert_dir_exists() {
    local dir="$1" why="$2"
    if [[ -d "$dir" ]]; then
        PASS=$((PASS + 1))
    else
        red "FAIL: expected directory missing — $dir  ($why)"
        FAIL=$((FAIL + 1))
    fi
}

assert_dir_empty_or_missing() {
    local dir="$1" why="$2"
    if [[ ! -d "$dir" ]] || [[ -z "$(ls -A "$dir" 2>/dev/null)" ]]; then
        PASS=$((PASS + 1))
    else
        red "FAIL: directory should be empty/missing but has contents — $dir  ($why)"
        FAIL=$((FAIL + 1))
    fi
}

assert_grep() {
    local pattern="$1" file="$2" why="$3"
    if grep -qE "$pattern" "$file" 2>/dev/null; then
        PASS=$((PASS + 1))
    else
        red "FAIL: pattern '$pattern' not found in $file  ($why)"
        FAIL=$((FAIL + 1))
    fi
}

run_combo() {
    local platform="$1" apple_lang="$2"
    bold "==> Combo: --platform $platform --apple-language $apple_lang"

    local target
    target="$(mktemp -d)"
    "$INSTALL" "$target" --platform "$platform" --apple-language "$apple_lang" >/dev/null

    # settings.json + .gitignore land for every combo
    assert_file_exists "$target/.claude/settings.json"   "settings.json should always be copied"
    assert_file_exists "$target/CLAUDE.md"               "CLAUDE.md should always be created"
    assert_file_exists "$target/.gitignore"              ".gitignore should always be appended"
    assert_grep "AppBootstrapAI \\($platform\\)"         "$target/.gitignore" \
                                                          ".gitignore marker should match the chosen platform"

    # Cross-platform rule installs everywhere.
    assert_file_exists "$target/.claude/rules/project-documentation.md" \
                       "project-documentation.md is cross-platform — always installs"

    case "$platform" in
        apple|both)
            case "$apple_lang" in
                swift|both)
                    assert_file_exists "$target/.claude/rules/apple-swift6-strict-concurrency.md" "Apple+Swift in scope"
                    assert_file_exists "$target/.claude/rules/apple-swiftui-mvvm.md"              "Apple+Swift in scope"
                    assert_file_exists "$target/.claude/rules/apple-foundation-models.md"        "Apple+Swift in scope"
                    assert_dir_exists  "$target/.claude/skills/swiftui-pro"                       "Apple skills land when Swift in scope"
                    assert_dir_exists  "$target/.claude/skills/swift-concurrency-pro"             "Apple skills land when Swift in scope"
                    ;;
            esac
            case "$apple_lang" in
                objc|both)
                    assert_file_exists "$target/.claude/rules/apple-objc-best-practices.md" "ObjC in scope"
                    ;;
                swift)
                    assert_file_absent "$target/.claude/rules/apple-objc-best-practices.md" "ObjC NOT in scope under apple-language=swift"
                    ;;
            esac
            if [[ "$apple_lang" == "objc" ]] && [[ "$platform" == "apple" ]]; then
                # Pure objc-only: no Apple skills (Swift-tied) and no Android skills (Android not in scope).
                assert_dir_empty_or_missing "$target/.claude/skills" "no skills when Apple+ObjC-only — Apple skills are Swift-tied, Android out of scope"
                assert_file_absent "$target/.claude/rules/apple-swift6-strict-concurrency.md" "Swift-side rules excluded under apple-language=objc"
            fi
            ;;
        android)
            assert_file_absent "$target/.claude/rules/apple-swift6-strict-concurrency.md"  "Apple rules excluded for android"
            assert_file_absent "$target/.claude/rules/apple-objc-best-practices.md"        "Apple rules excluded for android"
            assert_dir_exists  "$target/.claude/skills/android-gradle-architecture-pro"    "Android skills land for android platform"
            assert_dir_exists  "$target/.claude/skills/xml-to-compose-migration-pro"       "Android skills land for android platform"
            assert_dir_exists  "$target/.claude/skills/r8-shrink-pro"                      "Android skills land for android platform"
            # Apple skills should NOT land:
            assert_file_absent "$target/.claude/skills/swiftui-pro/SKILL.md"                "Apple skills excluded for android"
            assert_file_absent "$target/.claude/skills/swift-concurrency-pro/SKILL.md"      "Apple skills excluded for android"
            ;;
    esac

    case "$platform" in
        android|both)
            assert_file_exists "$target/.claude/rules/android-project-rules.md"             "Android rules in scope"
            assert_file_exists "$target/.claude/rules/android-compose-best-practices.md"    "Android rules in scope"
            assert_file_exists "$target/.claude/rules/android-coroutines-best-practices.md" "Android rules in scope"
            assert_dir_exists  "$target/.claude/skills/android-gradle-architecture-pro"     "Android skills in scope"
            assert_dir_exists  "$target/.claude/skills/xml-to-compose-migration-pro"        "Android skills in scope"
            assert_dir_exists  "$target/.claude/skills/r8-shrink-pro"                       "Android skills in scope"
            ;;
        apple)
            assert_file_absent "$target/.claude/rules/android-project-rules.md"             "Android rules excluded for apple"
            assert_file_absent "$target/.claude/skills/android-gradle-architecture-pro/SKILL.md" "Android skills excluded for apple"
            ;;
    esac

    # CLAUDE template selection — assert by sentinel string unique to each template.
    case "$platform" in
        apple)
            assert_grep "iOS Simulator"               "$target/CLAUDE.md" "Apple template should be applied"
            ;;
        android)
            assert_grep "gradlew assembleDebug"       "$target/CLAUDE.md" "Android template should be applied"
            ;;
        both)
            # Cross-platform template references both build commands.
            assert_grep "iOS Simulator"               "$target/CLAUDE.md" "cross-platform template references iOS"
            assert_grep "gradlew assembleDebug"       "$target/CLAUDE.md" "cross-platform template references Gradle"
            ;;
    esac

    rm -rf "$target"
}

# Run every meaningful combo. apple-language is irrelevant for android, but
# we still pass a value to exercise the parser.
run_combo apple   swift
run_combo apple   objc
run_combo apple   both
run_combo android swift
run_combo both    swift
run_combo both    both

# --list and --help should both succeed and produce sentinel output.
# Note: capture output before grepping. If we piped directly to `grep -q`,
# grep closes stdin after the first match, install.sh gets SIGPIPE on the
# rest of its output, and `set -o pipefail` reports the pipeline as failed.
bold "==> --list / --help sanity"

list_out="$("$INSTALL" --list)"
if grep -q "AppBootstrapAI catalog" <<<"$list_out"; then
    PASS=$((PASS + 1))
else
    red "FAIL: --list output missing 'AppBootstrapAI catalog' header"
    FAIL=$((FAIL + 1))
fi

help_out="$("$INSTALL" --help)"
if grep -q "Usage:" <<<"$help_out"; then
    PASS=$((PASS + 1))
else
    red "FAIL: --help output missing 'Usage:' header"
    FAIL=$((FAIL + 1))
fi

echo
if [[ "$FAIL" -eq 0 ]]; then
    green "PASSED: $PASS assertions across every install combination."
    exit 0
else
    red "FAILED: $FAIL of $((PASS + FAIL)) assertions."
    exit 1
fi
