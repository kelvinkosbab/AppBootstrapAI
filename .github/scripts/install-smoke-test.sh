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
    local platform="$1" apple_lang="$2" features="${3:-all}"
    bold "==> Combo: --platform $platform --apple-language $apple_lang --features $features"

    local target
    target="$(mktemp -d)"
    "$INSTALL" "$target" --platform "$platform" --apple-language "$apple_lang" --features "$features" >/dev/null

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
                    assert_file_exists "$target/.claude/rules/apple-objc-best-practices.md"              "ObjC core rule in scope"
                    # apple-objc-accessibility-best-practices.md is gated by --features ui,
                    # which IS in --features all (used by these existing combos).
                    assert_file_exists "$target/.claude/rules/apple-objc-accessibility-best-practices.md" "ObjC a11y rule in scope with --features all"
                    ;;
                swift)
                    assert_file_absent "$target/.claude/rules/apple-objc-best-practices.md"              "ObjC core rule NOT in scope under apple-language=swift"
                    assert_file_absent "$target/.claude/rules/apple-objc-accessibility-best-practices.md" "ObjC a11y rule NOT in scope under apple-language=swift"
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
# we still pass a value to exercise the parser. Existing combos use
# --features all so the platform-level assertions stay valid.
run_combo apple   swift all
run_combo apple   objc  all
run_combo apple   both  all
run_combo android swift all
run_combo both    swift all
run_combo both    both  all

# --- --features-specific tests -----------------------------------------------
# Targeted assertions for the --features filter.

bold "==> Feature filter: --features recommended (default behavior)"
target_rec="$(mktemp -d)"
"$INSTALL" "$target_rec" --platform both --apple-language both --features recommended >/dev/null

# recommended INCLUDES: core, concurrency, ui, testing, docs, error-handling,
# packaging, logging, localization. Spot-check one rule from each.
assert_file_exists "$target_rec/.claude/rules/project-documentation.md"                    "recommended includes core"
assert_file_exists "$target_rec/.claude/rules/apple-swift6-strict-concurrency.md"           "recommended includes concurrency"
assert_file_exists "$target_rec/.claude/rules/apple-swiftui-mvvm.md"                        "recommended includes ui"
assert_file_exists "$target_rec/.claude/rules/apple-testing-strategy.md"                    "recommended includes testing"
assert_file_exists "$target_rec/.claude/rules/apple-documentation-strategy.md"              "recommended includes docs"
assert_file_exists "$target_rec/.claude/rules/apple-localization-best-practices.md"         "recommended includes localization"
# Skills covered by recommended:
assert_dir_exists  "$target_rec/.claude/skills/swift-error-handling-pro"                    "recommended includes error-handling skill"
assert_dir_exists  "$target_rec/.claude/skills/swift-logging-pro"                           "recommended includes logging skill"
assert_dir_exists  "$target_rec/.claude/skills/swift-package-pro"                           "recommended includes packaging skill"

# recommended EXCLUDES: persistence, ai, migration, shrinking.
assert_file_absent "$target_rec/.claude/rules/apple-foundation-models.md"                   "recommended excludes ai (Foundation Models)"
assert_dir_empty_or_missing "$target_rec/.claude/skills/coredata-swift6-pro"                "recommended excludes persistence (Core Data)"
assert_dir_empty_or_missing "$target_rec/.claude/skills/xml-to-compose-migration-pro"       "recommended excludes migration"
assert_dir_empty_or_missing "$target_rec/.claude/skills/r8-shrink-pro"                      "recommended excludes shrinking"
rm -rf "$target_rec"

bold "==> Feature filter: --features core,testing"
target_min="$(mktemp -d)"
"$INSTALL" "$target_min" --platform both --apple-language both --features core,testing >/dev/null

assert_file_exists "$target_min/.claude/rules/project-documentation.md"        "core in scope"
assert_file_exists "$target_min/.claude/rules/apple-testing-strategy.md"        "testing in scope"
assert_file_exists "$target_min/.claude/rules/android-testing-strategy.md"      "testing in scope"
assert_dir_exists  "$target_min/.claude/skills/swift-testing-pro"               "swift-testing-pro in scope"
# Out of scope:
assert_file_absent "$target_min/.claude/rules/apple-swift6-strict-concurrency.md" "concurrency not selected"
assert_file_absent "$target_min/.claude/rules/apple-swiftui-mvvm.md"              "ui not selected"
assert_file_absent "$target_min/.claude/rules/apple-documentation-strategy.md"    "docs not selected"
assert_dir_empty_or_missing "$target_min/.claude/skills/swift-concurrency-pro"    "concurrency skill not selected"
rm -rf "$target_min"

bold "==> Feature filter: --features ai,persistence (apple, specialized opt-ins)"
target_ai="$(mktemp -d)"
"$INSTALL" "$target_ai" --platform apple --apple-language swift --features ai,persistence >/dev/null

assert_file_exists "$target_ai/.claude/rules/apple-foundation-models.md"        "ai includes Foundation Models rule"
assert_dir_exists  "$target_ai/.claude/skills/coredata-swift6-pro"              "persistence includes Core Data skill"
# Out of scope:
assert_file_absent "$target_ai/.claude/rules/apple-swift6-strict-concurrency.md" "concurrency not selected when only ai+persistence"
assert_dir_empty_or_missing "$target_ai/.claude/skills/swiftui-pro"              "ui skill not selected"
rm -rf "$target_ai"

bold "==> Feature filter: --apple-language objc --features core,testing (no ui)"
target_objc_no_ui="$(mktemp -d)"
"$INSTALL" "$target_objc_no_ui" --platform apple --apple-language objc --features core,testing >/dev/null

# Core ObjC rule lands regardless of --features (gated only by --apple-language)
assert_file_exists "$target_objc_no_ui/.claude/rules/apple-objc-best-practices.md"               "ObjC core rule lands even without ui category"
# ObjC accessibility rule is in 'ui' category, which isn't selected → skipped
assert_file_absent "$target_objc_no_ui/.claude/rules/apple-objc-accessibility-best-practices.md" "ObjC a11y rule skipped when ui not in --features"
# Swift-side apple rules are blocked by --apple-language=objc
assert_file_absent "$target_objc_no_ui/.claude/rules/apple-swift6-strict-concurrency.md"          "Swift rules skipped under apple-language=objc"
rm -rf "$target_objc_no_ui"

bold "==> Feature filter: --apple-language objc --features ui (a11y lands)"
target_objc_ui="$(mktemp -d)"
"$INSTALL" "$target_objc_ui" --platform apple --apple-language objc --features ui >/dev/null

assert_file_exists "$target_objc_ui/.claude/rules/apple-objc-best-practices.md"                  "ObjC core rule lands"
assert_file_exists "$target_objc_ui/.claude/rules/apple-objc-accessibility-best-practices.md"    "ObjC a11y rule lands when ui in --features"
# Apple Swift-side a11y rule still blocked by --apple-language=objc, even though ui is in --features
assert_file_absent "$target_objc_ui/.claude/rules/apple-accessibility-best-practices.md"          "Swift a11y rule blocked by apple-language=objc"
rm -rf "$target_objc_ui"

bold "==> Feature filter: invalid category should fail"
if "$INSTALL" /tmp/never --platform apple --features bogus >/dev/null 2>&1; then
    red "FAIL: invalid --features value should exit non-zero"
    FAIL=$((FAIL + 1))
else
    PASS=$((PASS + 1))
fi

# --- Tier 1 install.sh additions ---------------------------------------------

bold "==> Composition: --features recommended,ai,persistence"
target_compose="$(mktemp -d)"
"$INSTALL" "$target_compose" --platform apple --features recommended,ai,persistence >/dev/null
assert_file_exists "$target_compose/.claude/rules/apple-swift6-strict-concurrency.md" "recommended subset still applies"
assert_file_exists "$target_compose/.claude/rules/apple-foundation-models.md"          "ai opt-in from CSV composition"
assert_dir_exists  "$target_compose/.claude/skills/coredata-swift6-pro"                "persistence opt-in from CSV composition"
# migration NOT in recommended,ai,persistence:
assert_dir_empty_or_missing "$target_compose/.claude/skills/xml-to-compose-migration-pro" "migration not selected"
rm -rf "$target_compose"

bold "==> --dry-run writes nothing"
target_dry="$(mktemp -d)"
"$INSTALL" "$target_dry" --platform both --features all --dry-run >/dev/null
# No files should land. The mktemp dir might be empty or contain hidden dotfiles; check both.
file_count=$(find "$target_dry" -type f 2>/dev/null | wc -l | tr -d ' ')
if [[ "$file_count" -eq 0 ]]; then
    PASS=$((PASS + 1))
else
    red "FAIL: --dry-run wrote $file_count file(s) into the target — should write zero"
    FAIL=$((FAIL + 1))
fi
rm -rf "$target_dry"

bold "==> --list --json produces valid JSON parseable by python3"
json_payload="$("$INSTALL" --list --json --platform both --features all)"
# Validate via python3 — fail this assertion if the JSON doesn't parse or lacks expected keys.
if echo "$json_payload" | python3 -c "
import sys, json
data = json.load(sys.stdin)
assert 'selection' in data, 'missing selection'
assert 'rules' in data and isinstance(data['rules'], list), 'missing rules array'
assert 'skills' in data and isinstance(data['skills'], list), 'missing skills array'
assert data['selection']['platform'] == 'both'
assert data['selection']['features_input'] == 'all'
# Every rule should have filename/category/installed/description
for r in data['rules']:
    for k in ('filename', 'category', 'installed', 'description'):
        assert k in r, f'rule missing {k}: {r}'
for s in data['skills']:
    for k in ('name', 'category', 'installed', 'description'):
        assert k in s, f'skill missing {k}: {s}'
" 2>/dev/null; then
    PASS=$((PASS + 1))
else
    red "FAIL: --list --json output was invalid or schema didn't match"
    FAIL=$((FAIL + 1))
fi

bold "==> --json without --list rejected"
if "$INSTALL" /tmp/never --json --platform apple >/dev/null 2>&1; then
    red "FAIL: --json without --list should exit non-zero"
    FAIL=$((FAIL + 1))
else
    PASS=$((PASS + 1))
fi

bold "==> Manifest written on real install"
target_manifest="$(mktemp -d)"
"$INSTALL" "$target_manifest" --platform apple --features recommended >/dev/null
manifest="$target_manifest/.claude/.appbootstrap-manifest.json"
assert_file_exists "$manifest" "manifest file lands"
# Schema check via python3.
if python3 -c "
import json, sys
with open('$manifest') as f:
    m = json.load(f)
assert m['schema_version'] == 1, f'wrong schema_version: {m}'
assert 'installed_at' in m
assert m['selection']['platform'] == 'apple'
assert m['selection']['features_input'] == 'recommended'
assert isinstance(m['files'], list) and len(m['files']) > 0
for entry in m['files']:
    assert all(k in entry for k in ('path', 'type', 'category')), entry
" 2>/dev/null; then
    PASS=$((PASS + 1))
else
    red "FAIL: manifest schema mismatch"
    FAIL=$((FAIL + 1))
fi
rm -rf "$target_manifest"

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
