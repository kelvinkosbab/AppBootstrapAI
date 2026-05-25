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
