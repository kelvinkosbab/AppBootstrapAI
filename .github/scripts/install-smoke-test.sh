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
import json, sys, re
with open('$manifest') as f:
    m = json.load(f)
assert m['schema_version'] == 2, f'wrong schema_version: {m}'
assert 'installed_at' in m
assert 'bundle_commit' in m, 'v2 manifest must record bundle_commit'
assert m['selection']['platform'] == 'apple'
assert m['selection']['features_input'] == 'recommended'
assert isinstance(m['files'], list) and len(m['files']) > 0
assert isinstance(m['mcps_installed'], list), 'mcps_installed must be a list'
sha_re = re.compile(r'^[0-9a-f]{64}$')
for entry in m['files']:
    assert all(k in entry for k in ('path', 'type', 'category', 'sha256')), entry
    # sha256 is null only for the gitignore-block synthetic entry; everything else has a hex digest.
    if entry['type'] == 'gitignore-block':
        assert entry['sha256'] is None, f'gitignore-block should have null sha256: {entry}'
    else:
        assert isinstance(entry['sha256'], str) and sha_re.match(entry['sha256']), entry
    if entry['type'] == 'skill-file':
        assert 'skill' in entry and isinstance(entry['skill'], str), f'skill-file missing skill field: {entry}'
" 2>/dev/null; then
    PASS=$((PASS + 1))
else
    red "FAIL: manifest schema mismatch"
    FAIL=$((FAIL + 1))
fi
rm -rf "$target_manifest"

# --- MCP recipes (--list-mcps, --with-mcps) ----------------------------------

bold "==> --list-mcps prints the 5 recipes"
list_mcps_out="$("$INSTALL" --list-mcps)"
for name in xcodebuildmcp xcode-native android-mcp-server firebase sentry; do
    if grep -qE "(^|[^a-zA-Z-])$name([^a-zA-Z-]|$)" <<<"$list_mcps_out"; then
        PASS=$((PASS + 1))
    else
        red "FAIL: --list-mcps output missing recipe: $name"
        FAIL=$((FAIL + 1))
    fi
done

bold "==> --with-mcps xcodebuildmcp writes settings.local.json with the entry"
target_mcp="$(mktemp -d)"
"$INSTALL" "$target_mcp" --platform apple --with-mcps xcodebuildmcp >/dev/null
assert_file_exists "$target_mcp/.claude/settings.local.json" "settings.local.json created by --with-mcps"
if python3 -c "
import json, sys
with open('$target_mcp/.claude/settings.local.json') as f:
    d = json.load(f)
assert 'mcpServers' in d, 'missing mcpServers key'
assert 'xcodebuildmcp' in d['mcpServers'], 'missing xcodebuildmcp entry'
assert d['mcpServers']['xcodebuildmcp']['command'] == 'npx', 'wrong command'
print('OK')
" >/dev/null 2>&1; then
    PASS=$((PASS + 1))
else
    red "FAIL: settings.local.json missing expected xcodebuildmcp entry"
    FAIL=$((FAIL + 1))
fi
rm -rf "$target_mcp"

bold "==> --with-mcps with multiple recipes (stdio + hosted) lands both"
target_mcp_multi="$(mktemp -d)"
"$INSTALL" "$target_mcp_multi" --platform apple --with-mcps xcodebuildmcp,sentry >/dev/null
if python3 -c "
import json
with open('$target_mcp_multi/.claude/settings.local.json') as f:
    d = json.load(f)
mcps = d['mcpServers']
assert 'xcodebuildmcp' in mcps and 'command' in mcps['xcodebuildmcp']
assert 'sentry' in mcps and 'url' in mcps['sentry']
" >/dev/null 2>&1; then
    PASS=$((PASS + 1))
else
    red "FAIL: --with-mcps xcodebuildmcp,sentry did not land both correctly"
    FAIL=$((FAIL + 1))
fi
rm -rf "$target_mcp_multi"

bold "==> --with-mcps is idempotent — re-run preserves existing entries"
target_mcp_idem="$(mktemp -d)"
"$INSTALL" "$target_mcp_idem" --platform apple --with-mcps xcodebuildmcp >/dev/null
# Inject a custom command into the existing entry to detect overwrite.
python3 -c "
import json
p = '$target_mcp_idem/.claude/settings.local.json'
d = json.load(open(p))
d['mcpServers']['xcodebuildmcp']['args'] = ['custom-marker']
json.dump(d, open(p, 'w'), indent=2)
"
"$INSTALL" "$target_mcp_idem" --platform apple --with-mcps xcodebuildmcp >/dev/null
if python3 -c "
import json
d = json.load(open('$target_mcp_idem/.claude/settings.local.json'))
assert d['mcpServers']['xcodebuildmcp']['args'] == ['custom-marker']
" >/dev/null 2>&1; then
    PASS=$((PASS + 1))
else
    red "FAIL: --with-mcps overwrote an existing custom-modified entry"
    FAIL=$((FAIL + 1))
fi
rm -rf "$target_mcp_idem"

bold "==> --with-mcps preserves unrelated keys in settings.local.json"
target_mcp_pres="$(mktemp -d)"
mkdir -p "$target_mcp_pres/.claude"
cat >"$target_mcp_pres/.claude/settings.local.json" <<'JSON'
{
  "permissions": { "allow": ["Bash(echo:*)"] },
  "customField": "preserve me"
}
JSON
"$INSTALL" "$target_mcp_pres" --platform apple --with-mcps firebase >/dev/null
if python3 -c "
import json
d = json.load(open('$target_mcp_pres/.claude/settings.local.json'))
assert d['customField'] == 'preserve me', 'custom field lost'
assert 'Bash(echo:*)' in d['permissions']['allow'], 'permissions lost'
assert 'firebase' in d['mcpServers'], 'firebase not added'
" >/dev/null 2>&1; then
    PASS=$((PASS + 1))
else
    red "FAIL: --with-mcps did not preserve unrelated settings.local.json keys"
    FAIL=$((FAIL + 1))
fi
rm -rf "$target_mcp_pres"

bold "==> --with-mcps with unknown recipe name fails cleanly"
if "$INSTALL" /tmp/never-write --platform apple --with-mcps not-a-real-mcp >/dev/null 2>&1; then
    red "FAIL: --with-mcps with bogus name should exit non-zero"
    FAIL=$((FAIL + 1))
else
    PASS=$((PASS + 1))
fi

bold "==> --with-mcps under --dry-run writes nothing"
target_mcp_dry="$(mktemp -d)"
"$INSTALL" "$target_mcp_dry" --platform apple --with-mcps xcodebuildmcp --dry-run >/dev/null
assert_file_absent "$target_mcp_dry/.claude/settings.local.json" "dry-run must not write settings.local.json"
rm -rf "$target_mcp_dry"

bold "==> manifest tracks mcps_installed with config hashes"
target_mcp_mani="$(mktemp -d)"
"$INSTALL" "$target_mcp_mani" --platform apple --with-mcps xcodebuildmcp,sentry >/dev/null
if python3 -c "
import json, re
m = json.load(open('$target_mcp_mani/.claude/.appbootstrap-manifest.json'))
sha_re = re.compile(r'^[0-9a-f]{64}\$')
installed = m['mcps_installed']
names = [e['name'] for e in installed]
assert 'xcodebuildmcp' in names, f'xcodebuildmcp missing from mcps_installed: {names}'
assert 'sentry' in names, f'sentry missing from mcps_installed: {names}'
for e in installed:
    assert sha_re.match(e['config_sha256']), f'bad config_sha256 for {e[\"name\"]}: {e[\"config_sha256\"]}'
" 2>/dev/null; then
    PASS=$((PASS + 1))
else
    red "FAIL: manifest missing or malformed mcps_installed array"
    FAIL=$((FAIL + 1))
fi
rm -rf "$target_mcp_mani"

# --- Platform auto-detection (no --platform flag passed) ---------------------
#
# When --platform is omitted, install.sh sniffs the target directory for
# canonical project files and picks apple / android / both / fallback-both.

bold "==> auto-detect: empty target → falls back to 'both'"
target_auto_empty="$(mktemp -d)"
auto_empty_out="$("$INSTALL" "$target_auto_empty" --dry-run 2>&1)"
if grep -q "auto-detect found no project files → fallback" <<<"$auto_empty_out"; then
    PASS=$((PASS + 1))
else
    red "FAIL: empty target should print the fallback notice"
    FAIL=$((FAIL + 1))
fi
rm -rf "$target_auto_empty"

bold "==> auto-detect: Package.swift → apple, signal printed"
target_auto_spm="$(mktemp -d)"
touch "$target_auto_spm/Package.swift"
auto_spm_out="$("$INSTALL" "$target_auto_spm" --dry-run 2>&1)"
if grep -q "platform: apple (auto-detected)" <<<"$auto_spm_out" \
    && grep -q "apple signals:.*Package.swift"  <<<"$auto_spm_out"; then
    PASS=$((PASS + 1))
else
    red "FAIL: Package.swift should auto-detect to apple and print the signal"
    FAIL=$((FAIL + 1))
fi
rm -rf "$target_auto_spm"

bold "==> auto-detect: *.xcodeproj → apple"
target_auto_xcode="$(mktemp -d)"
mkdir -p "$target_auto_xcode/MyApp.xcodeproj"
auto_xcode_out="$("$INSTALL" "$target_auto_xcode" --dry-run 2>&1)"
if grep -q "platform: apple (auto-detected)" <<<"$auto_xcode_out" \
    && grep -q "apple signals:.*MyApp.xcodeproj"  <<<"$auto_xcode_out"; then
    PASS=$((PASS + 1))
else
    red "FAIL: *.xcodeproj should auto-detect to apple"
    FAIL=$((FAIL + 1))
fi
rm -rf "$target_auto_xcode"

bold "==> auto-detect: build.gradle.kts + gradlew → android"
target_auto_android="$(mktemp -d)"
touch "$target_auto_android/build.gradle.kts" "$target_auto_android/gradlew"
auto_android_out="$("$INSTALL" "$target_auto_android" --dry-run 2>&1)"
if grep -q "platform: android (auto-detected)" <<<"$auto_android_out" \
    && grep -q "android signals:.*build.gradle.kts"  <<<"$auto_android_out" \
    && grep -q "android signals:.*gradlew"           <<<"$auto_android_out"; then
    PASS=$((PASS + 1))
else
    red "FAIL: gradle signals should auto-detect to android"
    FAIL=$((FAIL + 1))
fi
rm -rf "$target_auto_android"

bold "==> auto-detect: Package.swift + settings.gradle.kts → both"
target_auto_both="$(mktemp -d)"
touch "$target_auto_both/Package.swift" "$target_auto_both/settings.gradle.kts"
auto_both_out="$("$INSTALL" "$target_auto_both" --dry-run 2>&1)"
if grep -q "platform: both (auto-detected)" <<<"$auto_both_out" \
    && grep -q "apple signals:.*Package.swift"        <<<"$auto_both_out" \
    && grep -q "android signals:.*settings.gradle.kts" <<<"$auto_both_out"; then
    PASS=$((PASS + 1))
else
    red "FAIL: mixed signals should auto-detect to both, printing both lines"
    FAIL=$((FAIL + 1))
fi
rm -rf "$target_auto_both"

bold "==> auto-detect: explicit --platform overrides detection"
target_auto_override="$(mktemp -d)"
touch "$target_auto_override/Package.swift"  # would auto-detect apple
auto_override_out="$("$INSTALL" "$target_auto_override" --platform android --dry-run 2>&1)"
# Should NOT carry the auto-detect tag, and should produce only android-side rules.
if grep -q "platform: android   apple-language" <<<"$auto_override_out" \
    && ! grep -q "auto-detected"                 <<<"$auto_override_out"; then
    PASS=$((PASS + 1))
else
    red "FAIL: explicit --platform should override detection and suppress the auto-detect line"
    FAIL=$((FAIL + 1))
fi
rm -rf "$target_auto_override"

# --- --upgrade plan-only flow (Phase 2) -------------------------------------
#
# Drive each classification by either editing files in the target or by mutating
# the manifest's recorded installed_hash to simulate upstream change.

bold "==> --upgrade: fresh install → everything up to date"
target_up_clean="$(mktemp -d)"
"$INSTALL" "$target_up_clean" --platform apple --features recommended > /dev/null
up_clean_out="$("$INSTALL" "$target_up_clean" --upgrade 2>&1)"
if grep -q "Plan: 0 safe update" <<<"$up_clean_out" \
    && grep -q "0 conflict"     <<<"$up_clean_out" \
    && grep -q "0 orphan"       <<<"$up_clean_out"; then
    PASS=$((PASS + 1))
else
    red "FAIL: fresh install should produce a zero-action upgrade plan"
    echo "$up_clean_out" | tail -5
    FAIL=$((FAIL + 1))
fi
rm -rf "$target_up_clean"

bold "==> --upgrade: local edit → 'Locally edited' classification"
target_up_local="$(mktemp -d)"
"$INSTALL" "$target_up_local" --platform apple --features recommended > /dev/null
echo "# my local override" >> "$target_up_local/.claude/rules/apple-swift6-strict-concurrency.md"
up_local_out="$("$INSTALL" "$target_up_local" --upgrade 2>&1)"
if grep -q "Locally edited" <<<"$up_local_out" \
    && grep -q "apple-swift6-strict-concurrency.md" <<<"$up_local_out"; then
    PASS=$((PASS + 1))
else
    red "FAIL: edited rule should appear under 'Locally edited'"
    FAIL=$((FAIL + 1))
fi
rm -rf "$target_up_local"

bold "==> --upgrade: simulated upstream change → 'Safe to update' classification"
target_up_safe="$(mktemp -d)"
"$INSTALL" "$target_up_safe" --platform apple --features recommended > /dev/null
# Overwrite the disk file with an "old" version, then point installed_hash at
# that same old hash. Now installed_hash == current_hash != bundle_hash → safe update.
echo "old version content" > "$target_up_safe/.claude/rules/apple-swiftui-mvvm.md"
old_hash="$(shasum -a 256 "$target_up_safe/.claude/rules/apple-swiftui-mvvm.md" | awk '{print $1}')"
python3 -c "
import json
m = json.load(open('$target_up_safe/.claude/.appbootstrap-manifest.json'))
for f in m['files']:
    if f['path'] == '.claude/rules/apple-swiftui-mvvm.md':
        f['sha256'] = '$old_hash'
        break
json.dump(m, open('$target_up_safe/.claude/.appbootstrap-manifest.json','w'), indent=2)
"
up_safe_out="$("$INSTALL" "$target_up_safe" --upgrade 2>&1)"
if grep -q "Safe to update" <<<"$up_safe_out" \
    && grep -q "Plan: 1 safe update" <<<"$up_safe_out"; then
    PASS=$((PASS + 1))
else
    red "FAIL: simulated upstream change should appear under 'Safe to update'"
    FAIL=$((FAIL + 1))
fi
rm -rf "$target_up_safe"

bold "==> --upgrade: local edit + upstream change → 'Conflict' classification"
target_up_conf="$(mktemp -d)"
"$INSTALL" "$target_up_conf" --platform apple --features recommended > /dev/null
echo "# local override" >> "$target_up_conf/.claude/rules/apple-swiftui-mvvm.md"
python3 -c "
import json
m = json.load(open('$target_up_conf/.claude/.appbootstrap-manifest.json'))
for f in m['files']:
    if f['path'] == '.claude/rules/apple-swiftui-mvvm.md':
        f['sha256'] = '0' * 64
        break
json.dump(m, open('$target_up_conf/.claude/.appbootstrap-manifest.json','w'), indent=2)
"
up_conf_out="$("$INSTALL" "$target_up_conf" --upgrade 2>&1)"
if grep -q "Conflict" <<<"$up_conf_out" \
    && grep -q "Plan: 0 safe update" <<<"$up_conf_out" \
    && grep -q "1 conflict"          <<<"$up_conf_out"; then
    PASS=$((PASS + 1))
else
    red "FAIL: both-changed scenario should appear under 'Conflict'"
    FAIL=$((FAIL + 1))
fi
rm -rf "$target_up_conf"

bold "==> --upgrade: synthesized orphan → 'Retired upstream' classification"
target_up_orph="$(mktemp -d)"
"$INSTALL" "$target_up_orph" --platform apple --features recommended > /dev/null
python3 -c "
import json
m = json.load(open('$target_up_orph/.claude/.appbootstrap-manifest.json'))
m['files'].append({'path': '.claude/rules/retired-rule.md', 'type': 'rule', 'category': 'core', 'sha256': '0'*64})
json.dump(m, open('$target_up_orph/.claude/.appbootstrap-manifest.json','w'), indent=2)
"
echo "fake retired" > "$target_up_orph/.claude/rules/retired-rule.md"
up_orph_out="$("$INSTALL" "$target_up_orph" --upgrade 2>&1)"
if grep -q "Retired upstream" <<<"$up_orph_out" \
    && grep -q "retired-rule.md" <<<"$up_orph_out"; then
    PASS=$((PASS + 1))
else
    red "FAIL: orphan manifest entry should appear under 'Retired upstream'"
    FAIL=$((FAIL + 1))
fi
rm -rf "$target_up_orph"

bold "==> --upgrade: feature drop → 'Out of scope' classification"
target_up_drop="$(mktemp -d)"
"$INSTALL" "$target_up_drop" --platform apple --features all > /dev/null
up_drop_out="$("$INSTALL" "$target_up_drop" --upgrade --features recommended 2>&1)"
if grep -q "Out of scope" <<<"$up_drop_out"; then
    PASS=$((PASS + 1))
else
    red "FAIL: opting out of features should surface previously-installed files as 'Out of scope'"
    FAIL=$((FAIL + 1))
fi
rm -rf "$target_up_drop"

bold "==> --upgrade: v1 manifest → migration notice + clean exit"
target_up_v1="$(mktemp -d)"
mkdir -p "$target_up_v1/.claude"
cat > "$target_up_v1/.claude/.appbootstrap-manifest.json" <<'V1MANIFEST'
{
  "schema_version": 1,
  "installed_at": "2024-01-01T00:00:00Z",
  "selection": {"platform": "apple", "apple_language": "swift", "features_input": "recommended"},
  "files": [],
  "mcps_requested": []
}
V1MANIFEST
up_v1_out="$("$INSTALL" "$target_up_v1" --upgrade 2>&1)"
if grep -q "schema v1" <<<"$up_v1_out" \
    && grep -q "Aborting plan" <<<"$up_v1_out"; then
    PASS=$((PASS + 1))
else
    red "FAIL: v1 manifest should produce the migration notice"
    FAIL=$((FAIL + 1))
fi
rm -rf "$target_up_v1"

bold "==> --upgrade: selection inherited from manifest when no flags passed"
target_up_inh="$(mktemp -d)"
"$INSTALL" "$target_up_inh" --platform apple --features recommended > /dev/null
up_inh_out="$("$INSTALL" "$target_up_inh" --upgrade 2>&1)"
if grep -q "inherited from manifest" <<<"$up_inh_out" \
    && grep -q "platform apple"      <<<"$up_inh_out" \
    && grep -q "features recommended" <<<"$up_inh_out"; then
    PASS=$((PASS + 1))
else
    red "FAIL: --upgrade should inherit selection from manifest"
    FAIL=$((FAIL + 1))
fi
rm -rf "$target_up_inh"

bold "==> --upgrade: no manifest at target → clean error"
target_up_none="$(mktemp -d)"
if "$INSTALL" "$target_up_none" --upgrade > /tmp/up_none.out 2>&1; then
    red "FAIL: --upgrade against a target with no manifest should exit non-zero"
    FAIL=$((FAIL + 1))
else
    if grep -q "no manifest at" /tmp/up_none.out; then
        PASS=$((PASS + 1))
    else
        red "FAIL: --upgrade with no manifest should print 'no manifest at' message"
        FAIL=$((FAIL + 1))
    fi
fi
rm -rf "$target_up_none"
rm -f /tmp/up_none.out

# --- --upgrade --apply (Phase 3) --------------------------------------------
#
# Same scenarios as Phase 2 plan-only, but driving them to the actual write.
# We verify: file content changed (or didn't), manifest hash refreshed,
# and the right files were created/removed.

# Helpers for these tests.
file_hash() { shasum -a 256 "$1" | awk '{print $1}'; }
manifest_hash_for() {
    python3 -c "import json; m=json.load(open('$1')); print([f.get('sha256','') for f in m['files'] if f['path']=='$2'][0])" 2>/dev/null
}
manifest_has_path() {
    python3 -c "import json,sys; m=json.load(open('$1')); sys.exit(0 if '$2' in [f['path'] for f in m['files']] else 1)" 2>/dev/null
}

bold "==> --apply: safe update overwrites file and refreshes manifest"
t="$(mktemp -d)"
"$INSTALL" "$t" --platform apple --features recommended > /dev/null
echo "old content" > "$t/.claude/rules/apple-swiftui-mvvm.md"
old_hash="$(file_hash "$t/.claude/rules/apple-swiftui-mvvm.md")"
python3 -c "
import json
m = json.load(open('$t/.claude/.appbootstrap-manifest.json'))
for f in m['files']:
    if f['path'] == '.claude/rules/apple-swiftui-mvvm.md':
        f['sha256'] = '$old_hash'; break
json.dump(m, open('$t/.claude/.appbootstrap-manifest.json','w'), indent=2)
"
"$INSTALL" "$t" --upgrade --apply > /dev/null
bundle_hash="$(file_hash "$REPO_ROOT/.claude/rules/apple-swiftui-mvvm.md")"
disk_hash="$(file_hash "$t/.claude/rules/apple-swiftui-mvvm.md")"
m_hash="$(manifest_hash_for "$t/.claude/.appbootstrap-manifest.json" ".claude/rules/apple-swiftui-mvvm.md")"
if [[ "$disk_hash" == "$bundle_hash" && "$m_hash" == "$bundle_hash" ]]; then
    PASS=$((PASS + 1))
else
    red "FAIL: safe-update apply didn't fully sync disk + manifest to bundle"
    FAIL=$((FAIL + 1))
fi
rm -rf "$t"

bold "==> --apply: conflict SKIPPED by default, local edit preserved"
t="$(mktemp -d)"
"$INSTALL" "$t" --platform apple --features recommended > /dev/null
echo "# local edit" >> "$t/.claude/rules/apple-swiftui-mvvm.md"
local_hash="$(file_hash "$t/.claude/rules/apple-swiftui-mvvm.md")"
python3 -c "
import json
m = json.load(open('$t/.claude/.appbootstrap-manifest.json'))
for f in m['files']:
    if f['path'] == '.claude/rules/apple-swiftui-mvvm.md':
        f['sha256'] = '0'*64; break
json.dump(m, open('$t/.claude/.appbootstrap-manifest.json','w'), indent=2)
"
out="$("$INSTALL" "$t" --upgrade --apply 2>&1)"
disk_hash="$(file_hash "$t/.claude/rules/apple-swiftui-mvvm.md")"
if [[ "$disk_hash" == "$local_hash" ]] && grep -q "conflict.*SKIPPED" <<<"$out"; then
    PASS=$((PASS + 1))
else
    red "FAIL: conflict should be skipped + local edit preserved"
    FAIL=$((FAIL + 1))
fi
rm -rf "$t"

bold "==> --apply --force-conflicts: conflict overwritten"
t="$(mktemp -d)"
"$INSTALL" "$t" --platform apple --features recommended > /dev/null
echo "# local edit" >> "$t/.claude/rules/apple-swiftui-mvvm.md"
python3 -c "
import json
m = json.load(open('$t/.claude/.appbootstrap-manifest.json'))
for f in m['files']:
    if f['path'] == '.claude/rules/apple-swiftui-mvvm.md':
        f['sha256'] = '0'*64; break
json.dump(m, open('$t/.claude/.appbootstrap-manifest.json','w'), indent=2)
"
"$INSTALL" "$t" --upgrade --apply --force-conflicts > /dev/null
disk_hash="$(file_hash "$t/.claude/rules/apple-swiftui-mvvm.md")"
bundle_hash="$(file_hash "$REPO_ROOT/.claude/rules/apple-swiftui-mvvm.md")"
if [[ "$disk_hash" == "$bundle_hash" ]]; then
    PASS=$((PASS + 1))
else
    red "FAIL: --force-conflicts should overwrite the conflicted file"
    FAIL=$((FAIL + 1))
fi
rm -rf "$t"

bold "==> --apply --prune: orphan file deleted, manifest entry dropped"
t="$(mktemp -d)"
"$INSTALL" "$t" --platform apple --features recommended > /dev/null
echo "retired" > "$t/.claude/rules/retired-rule.md"
ret_hash="$(file_hash "$t/.claude/rules/retired-rule.md")"
python3 -c "
import json
m = json.load(open('$t/.claude/.appbootstrap-manifest.json'))
m['files'].append({'path': '.claude/rules/retired-rule.md', 'type': 'rule', 'category': 'core', 'sha256': '$ret_hash'})
json.dump(m, open('$t/.claude/.appbootstrap-manifest.json','w'), indent=2)
"
"$INSTALL" "$t" --upgrade --apply --prune > /dev/null
if [[ ! -f "$t/.claude/rules/retired-rule.md" ]] \
    && ! manifest_has_path "$t/.claude/.appbootstrap-manifest.json" ".claude/rules/retired-rule.md"; then
    PASS=$((PASS + 1))
else
    red "FAIL: --prune should delete orphan AND drop its manifest entry"
    FAIL=$((FAIL + 1))
fi
rm -rf "$t"

bold "==> --apply --prune: out-of-scope file deleted on feature drop"
t="$(mktemp -d)"
"$INSTALL" "$t" --platform apple --features all > /dev/null
"$INSTALL" "$t" --upgrade --features recommended --apply --prune > /dev/null
if [[ ! -f "$t/.claude/rules/apple-foundation-models.md" ]]; then
    PASS=$((PASS + 1))
else
    red "FAIL: out-of-scope file should be removed under --prune"
    FAIL=$((FAIL + 1))
fi
rm -rf "$t"

bold "==> --apply: addition (new feature opt-in) lands + tracks in manifest"
t="$(mktemp -d)"
"$INSTALL" "$t" --platform apple --features recommended > /dev/null
[[ -f "$t/.claude/rules/apple-foundation-models.md" ]] && { red "test setup wrong: ai rule already present"; FAIL=$((FAIL + 1)); }
"$INSTALL" "$t" --upgrade --features all --apply > /dev/null
if [[ -f "$t/.claude/rules/apple-foundation-models.md" ]] \
    && manifest_has_path "$t/.claude/.appbootstrap-manifest.json" ".claude/rules/apple-foundation-models.md"; then
    PASS=$((PASS + 1))
else
    red "FAIL: addition should write the file AND extend the manifest"
    FAIL=$((FAIL + 1))
fi
rm -rf "$t"

bold "==> --apply --dry-run: nothing written, manifest untouched"
t="$(mktemp -d)"
"$INSTALL" "$t" --platform apple --features recommended > /dev/null
echo "old" > "$t/.claude/rules/apple-swiftui-mvvm.md"
old_hash="$(file_hash "$t/.claude/rules/apple-swiftui-mvvm.md")"
python3 -c "
import json
m = json.load(open('$t/.claude/.appbootstrap-manifest.json'))
for f in m['files']:
    if f['path'] == '.claude/rules/apple-swiftui-mvvm.md':
        f['sha256'] = '$old_hash'; break
json.dump(m, open('$t/.claude/.appbootstrap-manifest.json','w'), indent=2)
"
out="$("$INSTALL" "$t" --upgrade --apply --dry-run 2>&1)"
disk_hash="$(file_hash "$t/.claude/rules/apple-swiftui-mvvm.md")"
m_hash="$(manifest_hash_for "$t/.claude/.appbootstrap-manifest.json" ".claude/rules/apple-swiftui-mvvm.md")"
if [[ "$disk_hash" == "$old_hash" && "$m_hash" == "$old_hash" ]] && grep -q "DRY RUN" <<<"$out"; then
    PASS=$((PASS + 1))
else
    red "FAIL: --apply --dry-run must not write any files OR touch the manifest"
    FAIL=$((FAIL + 1))
fi
rm -rf "$t"

bold "==> --migrate-manifest: v1 → v2 with disk hashes"
t="$(mktemp -d)"
mkdir -p "$t/.claude/rules" "$t/.claude/skills/test-skill"
echo "rule content" > "$t/.claude/rules/test-rule.md"
echo "skill content" > "$t/.claude/skills/test-skill/SKILL.md"
cat > "$t/.claude/.appbootstrap-manifest.json" <<'V1MIG'
{
  "schema_version": 1,
  "installed_at": "2024-01-01T00:00:00Z",
  "selection": {"platform": "apple", "apple_language": "swift", "features_input": "recommended", "features_resolved": ["core"]},
  "files": [
    {"path": ".claude/rules/test-rule.md", "type": "rule", "category": "core"},
    {"path": ".claude/skills/test-skill", "type": "skill", "category": "concurrency"}
  ],
  "mcps_requested": []
}
V1MIG
"$INSTALL" "$t" --upgrade --apply --migrate-manifest > /dev/null
if python3 -c "
import json, re, sys
m = json.load(open('$t/.claude/.appbootstrap-manifest.json'))
assert m['schema_version'] == 2, m
assert 'bundle_commit' in m
assert isinstance(m['mcps_installed'], list)
paths = [f['path'] for f in m['files']]
assert '.claude/rules/test-rule.md' in paths
# v1 skill entry should have expanded to a skill-file entry
skill_files = [f for f in m['files'] if f.get('type')=='skill-file']
assert len(skill_files) >= 1
assert all(re.match(r'^[0-9a-f]{64}\$', f['sha256']) for f in m['files'] if f['type'] != 'gitignore-block')
" 2>/dev/null; then
    PASS=$((PASS + 1))
else
    red "FAIL: --migrate-manifest didn't produce a valid v2 manifest"
    FAIL=$((FAIL + 1))
fi
rm -rf "$t"

bold "==> --apply: validation — --apply requires --upgrade"
if "$INSTALL" /tmp/never --apply > /dev/null 2>&1; then
    red "FAIL: --apply without --upgrade should fail"; FAIL=$((FAIL + 1))
else
    PASS=$((PASS + 1))
fi

bold "==> --apply: validation — --force-conflicts requires --apply"
if "$INSTALL" /tmp/never --upgrade --force-conflicts > /dev/null 2>&1; then
    red "FAIL: --force-conflicts without --apply should fail"; FAIL=$((FAIL + 1))
else
    PASS=$((PASS + 1))
fi

bold "==> --apply: validation — --prune requires --apply"
if "$INSTALL" /tmp/never --upgrade --prune > /dev/null 2>&1; then
    red "FAIL: --prune without --apply should fail"; FAIL=$((FAIL + 1))
else
    PASS=$((PASS + 1))
fi

# --- MCP-side upgrade diff (Phase 3.1) --------------------------------------
#
# The classifier compares three hashes for each manifest mcps_installed entry:
#   installed_config_sha256 (manifest)
#   current_config_sha256   (settings.local.json's mcpServers.<name> entry)
#   bundle_config_sha256    (mcp-recipes/<name>.json's config)
# Test harness uses python3 to synthesize the configs + matching hashes.

# Helper: compute a recipe-style stable config hash.
mcp_hash() { python3 -c "
import json, hashlib, sys
cfg = json.loads(sys.argv[1])
print(hashlib.sha256(json.dumps(cfg, sort_keys=True, separators=(',',':')).encode()).hexdigest())
" "$1"; }

bold "==> --upgrade MCP: fresh install → all MCPs up to date"
t="$(mktemp -d)"
"$INSTALL" "$t" --platform apple --features recommended --with-mcps xcodebuildmcp,sentry > /dev/null
out="$("$INSTALL" "$t" --upgrade 2>&1)"
if grep -q "MCP entries" <<<"$out" && grep -q "Up to date: (2)" <<<"$out"; then
    PASS=$((PASS + 1))
else
    red "FAIL: fresh MCP install should classify all entries as up to date"
    FAIL=$((FAIL + 1))
fi
rm -rf "$t"

bold "==> --upgrade MCP: local edit → 'Locally edited' classification"
t="$(mktemp -d)"
"$INSTALL" "$t" --platform apple --features recommended --with-mcps xcodebuildmcp > /dev/null
python3 -c "
import json
sl = json.load(open('$t/.claude/settings.local.json'))
sl['mcpServers']['xcodebuildmcp']['args'] = ['custom-arg']
json.dump(sl, open('$t/.claude/settings.local.json','w'), indent=2)
"
out="$("$INSTALL" "$t" --upgrade 2>&1)"
if grep -q "Locally edited" <<<"$out" && grep -q "xcodebuildmcp" <<<"$out"; then
    PASS=$((PASS + 1))
else
    red "FAIL: locally-edited MCP entry should be classified as 'Locally edited'"
    FAIL=$((FAIL + 1))
fi
rm -rf "$t"

bold "==> --upgrade MCP: simulated upstream change → 'Safe to update'"
t="$(mktemp -d)"
"$INSTALL" "$t" --platform apple --features recommended --with-mcps xcodebuildmcp > /dev/null
# Synthesize: settings.local.json + manifest both reflect "old" config; bundle differs.
old_cfg='{"command":"npx","args":["-y","old-version"]}'
old_hash="$(mcp_hash "$old_cfg")"
python3 -c "
import json
sl = json.load(open('$t/.claude/settings.local.json'))
sl['mcpServers']['xcodebuildmcp'] = json.loads('$old_cfg')
json.dump(sl, open('$t/.claude/settings.local.json','w'), indent=2)
m = json.load(open('$t/.claude/.appbootstrap-manifest.json'))
m['mcps_installed'][0]['config_sha256'] = '$old_hash'
json.dump(m, open('$t/.claude/.appbootstrap-manifest.json','w'), indent=2)
"
out="$("$INSTALL" "$t" --upgrade 2>&1)"
if grep -q "Safe to update" <<<"$out" && grep -q "xcodebuildmcp" <<<"$out"; then
    PASS=$((PASS + 1))
else
    red "FAIL: synthesized old-config + matching manifest hash should classify as 'Safe to update'"
    FAIL=$((FAIL + 1))
fi
rm -rf "$t"

bold "==> --apply MCP: safe-update overwrites the entry + refreshes manifest"
t="$(mktemp -d)"
"$INSTALL" "$t" --platform apple --features recommended --with-mcps xcodebuildmcp > /dev/null
old_cfg='{"command":"npx","args":["-y","old-version"]}'
old_hash="$(mcp_hash "$old_cfg")"
python3 -c "
import json
sl = json.load(open('$t/.claude/settings.local.json'))
sl['mcpServers']['xcodebuildmcp'] = json.loads('$old_cfg')
json.dump(sl, open('$t/.claude/settings.local.json','w'), indent=2)
m = json.load(open('$t/.claude/.appbootstrap-manifest.json'))
m['mcps_installed'][0]['config_sha256'] = '$old_hash'
json.dump(m, open('$t/.claude/.appbootstrap-manifest.json','w'), indent=2)
"
"$INSTALL" "$t" --upgrade --apply > /dev/null
# After apply: settings.local.json must contain the BUNDLE config + manifest hash must match.
bundle_cfg="$(python3 -c "import json; print(json.dumps(json.load(open('$REPO_ROOT/mcp-recipes/xcodebuildmcp.json'))['config'], sort_keys=True, separators=(',',':')))")"
bundle_hash="$(mcp_hash "$bundle_cfg")"
current_cfg="$(python3 -c "import json; print(json.dumps(json.load(open('$t/.claude/settings.local.json'))['mcpServers']['xcodebuildmcp'], sort_keys=True, separators=(',',':')))")"
current_hash="$(mcp_hash "$current_cfg")"
mani_hash="$(python3 -c "import json; m=json.load(open('$t/.claude/.appbootstrap-manifest.json')); print([e['config_sha256'] for e in m['mcps_installed'] if e['name']=='xcodebuildmcp'][0])")"
if [[ "$current_hash" == "$bundle_hash" && "$mani_hash" == "$bundle_hash" ]]; then
    PASS=$((PASS + 1))
else
    red "FAIL: MCP safe-update should sync settings.local.json + manifest hash to bundle"
    FAIL=$((FAIL + 1))
fi
rm -rf "$t"

bold "==> --apply MCP: conflict SKIPPED by default; local edit preserved"
t="$(mktemp -d)"
"$INSTALL" "$t" --platform apple --features recommended --with-mcps xcodebuildmcp > /dev/null
# Synthesize a conflict: settings.local.json has CUSTOM-A; manifest hash is RANDOM
custom_cfg='{"command":"my-tool","args":["--special"]}'
custom_hash="$(mcp_hash "$custom_cfg")"
python3 -c "
import json
sl = json.load(open('$t/.claude/settings.local.json'))
sl['mcpServers']['xcodebuildmcp'] = json.loads('$custom_cfg')
json.dump(sl, open('$t/.claude/settings.local.json','w'), indent=2)
m = json.load(open('$t/.claude/.appbootstrap-manifest.json'))
m['mcps_installed'][0]['config_sha256'] = '0'*64
json.dump(m, open('$t/.claude/.appbootstrap-manifest.json','w'), indent=2)
"
out="$("$INSTALL" "$t" --upgrade --apply 2>&1)"
# Entry should be unchanged (compare hashes — canonical JSON of disk vs custom).
after_cfg="$(python3 -c "import json; print(json.dumps(json.load(open('$t/.claude/settings.local.json'))['mcpServers']['xcodebuildmcp']))")"
after_hash="$(mcp_hash "$after_cfg")"
if [[ "$after_hash" == "$custom_hash" ]] && grep -q "MCP conflict" <<<"$out"; then
    PASS=$((PASS + 1))
else
    red "FAIL: MCP conflict should be skipped and local edit preserved"
    FAIL=$((FAIL + 1))
fi
rm -rf "$t"

bold "==> --apply --force-conflicts MCP: conflict overwritten"
t="$(mktemp -d)"
"$INSTALL" "$t" --platform apple --features recommended --with-mcps xcodebuildmcp > /dev/null
python3 -c "
import json
sl = json.load(open('$t/.claude/settings.local.json'))
sl['mcpServers']['xcodebuildmcp'] = {'command': 'my-tool', 'args': ['--special']}
json.dump(sl, open('$t/.claude/settings.local.json','w'), indent=2)
m = json.load(open('$t/.claude/.appbootstrap-manifest.json'))
m['mcps_installed'][0]['config_sha256'] = '0'*64
json.dump(m, open('$t/.claude/.appbootstrap-manifest.json','w'), indent=2)
"
"$INSTALL" "$t" --upgrade --apply --force-conflicts > /dev/null
bundle_cfg="$(python3 -c "import json; print(json.dumps(json.load(open('$REPO_ROOT/mcp-recipes/xcodebuildmcp.json'))['config'], sort_keys=True, separators=(',',':')))")"
bundle_hash="$(mcp_hash "$bundle_cfg")"
mani_hash="$(python3 -c "import json; m=json.load(open('$t/.claude/.appbootstrap-manifest.json')); print([e['config_sha256'] for e in m['mcps_installed'] if e['name']=='xcodebuildmcp'][0])")"
if [[ "$mani_hash" == "$bundle_hash" ]]; then
    PASS=$((PASS + 1))
else
    red "FAIL: --force-conflicts should sync the MCP entry back to bundle"
    FAIL=$((FAIL + 1))
fi
rm -rf "$t"

bold "==> --upgrade MCP: orphan recipe → 'Orphan' classification"
t="$(mktemp -d)"
"$INSTALL" "$t" --platform apple --features recommended --with-mcps xcodebuildmcp > /dev/null
# Synthesize a manifest mcp entry whose recipe doesn't exist in the bundle.
python3 -c "
import json
m = json.load(open('$t/.claude/.appbootstrap-manifest.json'))
m['mcps_installed'].append({'name': 'imaginary-mcp', 'config_sha256': '0'*64})
sl = json.load(open('$t/.claude/settings.local.json'))
sl['mcpServers']['imaginary-mcp'] = {'command': 'fake', 'args': []}
json.dump(m, open('$t/.claude/.appbootstrap-manifest.json','w'), indent=2)
json.dump(sl, open('$t/.claude/settings.local.json','w'), indent=2)
"
out="$("$INSTALL" "$t" --upgrade 2>&1)"
if grep -q "Orphan" <<<"$out" && grep -q "imaginary-mcp" <<<"$out"; then
    PASS=$((PASS + 1))
else
    red "FAIL: orphaned MCP recipe should classify as 'Orphan'"
    FAIL=$((FAIL + 1))
fi
rm -rf "$t"

bold "==> --apply --prune MCP: orphan removed from settings.local.json AND manifest"
t="$(mktemp -d)"
"$INSTALL" "$t" --platform apple --features recommended --with-mcps xcodebuildmcp > /dev/null
python3 -c "
import json
m = json.load(open('$t/.claude/.appbootstrap-manifest.json'))
m['mcps_installed'].append({'name': 'imaginary-mcp', 'config_sha256': '0'*64})
sl = json.load(open('$t/.claude/settings.local.json'))
sl['mcpServers']['imaginary-mcp'] = {'command': 'fake', 'args': []}
json.dump(m, open('$t/.claude/.appbootstrap-manifest.json','w'), indent=2)
json.dump(sl, open('$t/.claude/settings.local.json','w'), indent=2)
"
"$INSTALL" "$t" --upgrade --apply --prune > /dev/null
# Both records should be gone
in_settings="$(python3 -c "import json; sl=json.load(open('$t/.claude/settings.local.json')); print('imaginary-mcp' in sl['mcpServers'])")"
in_manifest="$(python3 -c "import json; m=json.load(open('$t/.claude/.appbootstrap-manifest.json')); print(any(e['name']=='imaginary-mcp' for e in m['mcps_installed']))")"
if [[ "$in_settings" == "False" && "$in_manifest" == "False" ]]; then
    PASS=$((PASS + 1))
else
    red "FAIL: --prune should remove orphan MCP from settings.local.json AND manifest"
    FAIL=$((FAIL + 1))
fi
rm -rf "$t"

bold "==> --apply MCP: settings.local.json keys outside mcpServers are preserved"
t="$(mktemp -d)"
"$INSTALL" "$t" --platform apple --features recommended --with-mcps xcodebuildmcp > /dev/null
# Inject custom top-level key into settings.local.json
python3 -c "
import json
sl = json.load(open('$t/.claude/settings.local.json'))
sl['customField'] = 'do-not-touch'
sl['permissions'] = {'allow': ['Bash(echo:*)']}
json.dump(sl, open('$t/.claude/settings.local.json','w'), indent=2)
"
# Trigger a safe-update via faked hashes
old_cfg='{"command":"npx","args":["-y","old-version"]}'
old_hash="$(mcp_hash "$old_cfg")"
python3 -c "
import json
sl = json.load(open('$t/.claude/settings.local.json'))
sl['mcpServers']['xcodebuildmcp'] = json.loads('$old_cfg')
json.dump(sl, open('$t/.claude/settings.local.json','w'), indent=2)
m = json.load(open('$t/.claude/.appbootstrap-manifest.json'))
m['mcps_installed'][0]['config_sha256'] = '$old_hash'
json.dump(m, open('$t/.claude/.appbootstrap-manifest.json','w'), indent=2)
"
"$INSTALL" "$t" --upgrade --apply > /dev/null
if python3 -c "
import json, sys
sl = json.load(open('$t/.claude/settings.local.json'))
assert sl['customField'] == 'do-not-touch'
assert sl['permissions']['allow'] == ['Bash(echo:*)']
" 2>/dev/null; then
    PASS=$((PASS + 1))
else
    red "FAIL: --apply must preserve non-mcpServers keys in settings.local.json"
    FAIL=$((FAIL + 1))
fi
rm -rf "$t"

# --- Multi-agent install (Phase 4) -------------------------------------------

bold "==> --agents claude (default) → same as today's install"
t="$(mktemp -d)"
"$INSTALL" "$t" --platform apple --features recommended > /dev/null
if [[ -d "$t/.claude/rules" && -f "$t/CLAUDE.md" \
    && ! -d "$t/.cursor" && ! -f "$t/.github/copilot-instructions.md" \
    && ! -f "$t/GEMINI.md" && ! -f "$t/AGENTS.md" ]]; then
    PASS=$((PASS + 1))
else
    red "FAIL: default --agents claude shouldn't drop any non-Claude files"
    FAIL=$((FAIL + 1))
fi
rm -rf "$t"

bold "==> --agents copilot only → only .github/copilot-instructions.md + manifest"
t="$(mktemp -d)"
"$INSTALL" "$t" --platform apple --features recommended --agents copilot > /dev/null
if [[ -f "$t/.github/copilot-instructions.md" \
    && -f "$t/.claude/.appbootstrap-manifest.json" \
    && ! -d "$t/.claude/rules" && ! -d "$t/.claude/skills" \
    && ! -f "$t/CLAUDE.md" ]]; then
    PASS=$((PASS + 1))
else
    red "FAIL: --agents copilot landed unexpected files"
    FAIL=$((FAIL + 1))
fi
rm -rf "$t"

bold "==> --agents copilot: file has the generated-banner header"
t="$(mktemp -d)"
"$INSTALL" "$t" --platform apple --features recommended --agents copilot > /dev/null
if head -1 "$t/.github/copilot-instructions.md" | grep -q "Generated by AppBootstrapAI"; then
    PASS=$((PASS + 1))
else
    red "FAIL: copilot file should start with a generated-banner comment"
    FAIL=$((FAIL + 1))
fi
rm -rf "$t"

bold "==> --agents cursor → .cursor/rules/<name>.mdc with full rule content"
t="$(mktemp -d)"
"$INSTALL" "$t" --platform apple --features recommended --agents cursor > /dev/null
mdc_count="$(ls "$t/.cursor/rules" 2>/dev/null | wc -l | tr -d ' ')"
if [[ "$mdc_count" -gt 0 ]] \
    && head -3 "$t/.cursor/rules/apple-swift6-strict-concurrency.mdc" 2>/dev/null | grep -q "description:"; then
    PASS=$((PASS + 1))
else
    red "FAIL: --agents cursor didn't produce .mdc files with rule content"
    FAIL=$((FAIL + 1))
fi
rm -rf "$t"

bold "==> --agents gemini → GEMINI.md at root"
t="$(mktemp -d)"
"$INSTALL" "$t" --platform apple --features recommended --agents gemini > /dev/null
if [[ -f "$t/GEMINI.md" ]] && grep -q "Generated by AppBootstrapAI" "$t/GEMINI.md"; then
    PASS=$((PASS + 1))
else
    red "FAIL: --agents gemini didn't produce GEMINI.md with header"
    FAIL=$((FAIL + 1))
fi
rm -rf "$t"

bold "==> --agents codex → AGENTS.md at root"
t="$(mktemp -d)"
"$INSTALL" "$t" --platform apple --features recommended --agents codex > /dev/null
if [[ -f "$t/AGENTS.md" ]] && grep -q "Generated by AppBootstrapAI" "$t/AGENTS.md"; then
    PASS=$((PASS + 1))
else
    red "FAIL: --agents codex didn't produce AGENTS.md with header"
    FAIL=$((FAIL + 1))
fi
rm -rf "$t"

bold "==> --agents all → every agent's file lands"
t="$(mktemp -d)"
"$INSTALL" "$t" --platform apple --features recommended --agents all > /dev/null
if [[ -f "$t/CLAUDE.md" \
    && -f "$t/.github/copilot-instructions.md" \
    && -d "$t/.cursor/rules" \
    && -f "$t/GEMINI.md" \
    && -f "$t/AGENTS.md" ]]; then
    PASS=$((PASS + 1))
else
    red "FAIL: --agents all didn't install every agent"
    FAIL=$((FAIL + 1))
fi
rm -rf "$t"

bold "==> --agents copilot: existing copilot file is NEVER overwritten on install"
t="$(mktemp -d)"
mkdir -p "$t/.github"
echo "user's own content" > "$t/.github/copilot-instructions.md"
"$INSTALL" "$t" --platform apple --features recommended --agents copilot > /dev/null
if [[ "$(cat "$t/.github/copilot-instructions.md")" == "user's own content" ]]; then
    PASS=$((PASS + 1))
else
    red "FAIL: existing copilot-instructions.md was overwritten"
    FAIL=$((FAIL + 1))
fi
rm -rf "$t"

bold "==> manifest records agents_input / agents_resolved"
t="$(mktemp -d)"
"$INSTALL" "$t" --platform apple --features recommended --agents claude,copilot > /dev/null
if python3 -c "
import json
m = json.load(open('$t/.claude/.appbootstrap-manifest.json'))
sel = m['selection']
assert sel['agents_input'] == 'claude,copilot', sel
assert set(sel['agents_resolved']) == {'claude', 'copilot'}, sel
" 2>/dev/null; then
    PASS=$((PASS + 1))
else
    red "FAIL: manifest didn't record agents_input/agents_resolved correctly"
    FAIL=$((FAIL + 1))
fi
rm -rf "$t"

bold "==> manifest tracks agent-file-* entries with hashes"
t="$(mktemp -d)"
"$INSTALL" "$t" --platform apple --features recommended --agents copilot,cursor > /dev/null
if python3 -c "
import json, re
m = json.load(open('$t/.claude/.appbootstrap-manifest.json'))
types = {e['type'] for e in m['files']}
assert 'agent-file-copilot' in types, types
assert 'agent-file-cursor' in types, types
sha_re = re.compile(r'^[0-9a-f]{64}\$')
for e in m['files']:
    if e['type'].startswith('agent-file-'):
        assert sha_re.match(e['sha256']), e
" 2>/dev/null; then
    PASS=$((PASS + 1))
else
    red "FAIL: agent-file-* entries missing or malformed in manifest"
    FAIL=$((FAIL + 1))
fi
rm -rf "$t"

bold "==> --upgrade: agents inherit from manifest when not explicitly passed"
t="$(mktemp -d)"
"$INSTALL" "$t" --platform apple --features recommended --agents claude,copilot > /dev/null
out="$("$INSTALL" "$t" --upgrade 2>&1)"
if grep -q "inherited from manifest" <<<"$out" && grep -q -- "--agents claude,copilot" <<<"$out"; then
    PASS=$((PASS + 1))
else
    red "FAIL: --upgrade should inherit agents_input from manifest"
    FAIL=$((FAIL + 1))
fi
rm -rf "$t"

bold "==> --upgrade opt-in: new agent shows up as additions"
t="$(mktemp -d)"
"$INSTALL" "$t" --platform apple --features recommended --agents claude > /dev/null
out="$("$INSTALL" "$t" --upgrade --agents claude,gemini 2>&1)"
if grep -q "GEMINI.md" <<<"$out" && grep -q "Would add" <<<"$out"; then
    PASS=$((PASS + 1))
else
    red "FAIL: opting into a new agent should produce additions in the plan"
    FAIL=$((FAIL + 1))
fi
rm -rf "$t"

bold "==> --upgrade --apply opt-in: new agent files land"
t="$(mktemp -d)"
"$INSTALL" "$t" --platform apple --features recommended --agents claude > /dev/null
"$INSTALL" "$t" --upgrade --agents claude,gemini --apply > /dev/null
if [[ -f "$t/GEMINI.md" ]] && grep -q "Generated by AppBootstrapAI" "$t/GEMINI.md"; then
    PASS=$((PASS + 1))
else
    red "FAIL: opting in to gemini via --upgrade --apply should write GEMINI.md"
    FAIL=$((FAIL + 1))
fi
rm -rf "$t"

bold "==> --upgrade --apply --prune: dropping an agent removes its files"
t="$(mktemp -d)"
"$INSTALL" "$t" --platform apple --features recommended --agents claude,gemini > /dev/null
[[ -f "$t/GEMINI.md" ]] || { red "test setup wrong: GEMINI.md missing after install"; FAIL=$((FAIL + 1)); }
"$INSTALL" "$t" --upgrade --agents claude --apply --prune > /dev/null
if [[ ! -f "$t/GEMINI.md" ]]; then
    PASS=$((PASS + 1))
else
    red "FAIL: --prune should delete files for dropped agents"
    FAIL=$((FAIL + 1))
fi
rm -rf "$t"

bold "==> --agents validation: unknown name fails cleanly"
if "$INSTALL" /tmp/never --agents bogus-agent > /dev/null 2>&1; then
    red "FAIL: unknown agent should exit non-zero"; FAIL=$((FAIL + 1))
else
    PASS=$((PASS + 1))
fi

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
