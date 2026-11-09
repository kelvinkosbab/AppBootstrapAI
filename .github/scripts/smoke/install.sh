#!/usr/bin/env bash
# Smoke test, install: platform/language/feature combos, --dry-run, the manifest, MCP recipes, platform auto-detect, --new/--force/setup, command verbs, installer safety.
# Run one part with `bash .github/scripts/smoke/install.sh`, or all of them
# with `bash .github/scripts/install-smoke-test.sh`.

# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

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
# packaging, logging, localization, linting. Spot-check one rule from each.
assert_file_exists "$target_rec/.claude/rules/project-documentation.md"                    "recommended includes core"
assert_file_exists "$target_rec/.claude/rules/apple-swift6-strict-concurrency.md"           "recommended includes concurrency"
assert_file_exists "$target_rec/.claude/rules/apple-swiftui-mvvm.md"                        "recommended includes ui"
assert_file_exists "$target_rec/.claude/rules/apple-testing-strategy.md"                    "recommended includes testing"
assert_file_exists "$target_rec/.claude/rules/apple-documentation-strategy.md"              "recommended includes docs"
assert_file_exists "$target_rec/.claude/rules/apple-localization-best-practices.md"         "recommended includes localization"
assert_file_exists "$target_rec/.claude/rules/apple-linting-strategy.md"                    "recommended includes linting (apple)"
assert_file_exists "$target_rec/.claude/rules/android-linting-strategy.md"                  "recommended includes linting (android)"
# Skills covered by recommended:
assert_dir_exists  "$target_rec/.claude/skills/swift-error-handling-pro"                    "recommended includes error-handling skill"
assert_dir_exists  "$target_rec/.claude/skills/swift-logging-pro"                           "recommended includes logging skill"
assert_file_exists "$target_rec/.claude/rules/apple-logging-strategy.md"                    "recommended includes logging rule (apple)"
assert_file_exists "$target_rec/.claude/rules/android-logging-strategy.md"                  "recommended includes logging rule (android)"
assert_file_exists "$target_rec/.claude/rules/apple-memory-management.md"                   "recommended includes memory rule (apple)"
assert_file_exists "$target_rec/.claude/rules/android-storage-management.md"                 "recommended includes storage rule (android)"
assert_dir_exists  "$target_rec/.claude/skills/swift-memory-storage-pro"                    "recommended includes memory/storage skill (apple)"
assert_dir_exists  "$target_rec/.claude/skills/android-memory-storage-pro"                  "recommended includes memory/storage skill (android)"
assert_dir_exists  "$target_rec/.claude/skills/swift-package-pro"                           "recommended includes packaging skill"
assert_dir_exists  "$target_rec/.claude/skills/instruments-profiling-pro"                   "recommended includes performance skill"
assert_file_exists "$target_rec/.claude/rules/apple-motion-design.md"                      "recommended includes motion rule (apple)"
assert_file_exists "$target_rec/.claude/rules/android-motion-design.md"                    "recommended includes motion rule (android)"
assert_file_exists "$target_rec/.claude/skills/motion-design-pro/NOTICE.md"                "recommended includes motion skill with its license notice"

# recommended EXCLUDES: persistence, ai, migration, shrinking, intents, security.
assert_dir_empty_or_missing "$target_rec/.claude/skills/app-intents-pro"                    "recommended excludes intents"
assert_file_absent "$target_rec/.claude/rules/apple-build-security.md"                      "recommended excludes security"
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
# categories array — the contract the MCP server reads as its source of truth.
assert 'categories' in data and isinstance(data['categories'], list), 'missing categories array'
assert len(data['categories']) >= 16, f'expected >=16 categories, got {len(data[\"categories\"])}'
cat_names = {c['name'] for c in data['categories']}
assert {'spatial', 'deployment', 'linting'} <= cat_names, f'categories missing spatial/deployment/linting: {cat_names}'
for c in data['categories']:
    assert 'name' in c and 'recommended' in c, f'category missing name/recommended: {c}'
    assert isinstance(c['recommended'], bool), f'recommended must be bool: {c}'
# recommended preset must be exactly the 13 day-one categories
recommended = {c['name'] for c in data['categories'] if c['recommended']}
assert recommended == {'core','concurrency','ui','testing','docs','error-handling','packaging','logging','localization','linting','compliance','memory-storage','performance'}, \
    f'unexpected recommended set: {recommended}'
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
# Deliberate re-install over a now-managed target → requires --force.
"$INSTALL" "$target_mcp_idem" --platform apple --with-mcps xcodebuildmcp --force >/dev/null
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


# --- entry experience: --new / --force / managed-refuse / interactive --------

bold "==> --new creates a missing target dir and installs"
t="$(mktemp -d)/created-app"
"$INSTALL" "$t" --platform apple --features recommended --new > /dev/null
if [[ -d "$t" && -f "$t/CLAUDE.md" && -f "$t/.claude/.appbootstrap-manifest.json" ]]; then
    PASS=$((PASS + 1))
else
    red "FAIL: --new should create the dir and install into it"
    FAIL=$((FAIL + 1))
fi
rm -rf "$(dirname "$t")"

bold "==> --new git-inits a fresh repo (when git available + no .git)"
t="$(mktemp -d)/git-app"
"$INSTALL" "$t" --platform apple --features recommended --new > /dev/null
if command -v git >/dev/null 2>&1; then
    [[ -d "$t/.git" ]] && PASS=$((PASS + 1)) || { red "FAIL: --new should git init"; FAIL=$((FAIL + 1)); }
else
    PASS=$((PASS + 1))   # no git in this environment — skip the assertion, don't fail
fi
rm -rf "$(dirname "$t")"

bold "==> missing dir WITHOUT --new still errors (typo guard)"
if "$INSTALL" /tmp/abai-nope-$$ --platform apple > /tmp/new_none.out 2>&1; then
    red "FAIL: missing dir without --new should exit non-zero"; FAIL=$((FAIL + 1))
else
    grep -q "does not exist" /tmp/new_none.out && PASS=$((PASS + 1)) \
        || { red "FAIL: missing-dir error message changed"; FAIL=$((FAIL + 1)); }
fi
rm -f /tmp/new_none.out

bold "==> re-install over a managed target REFUSES and steers to --upgrade"
t="$(mktemp -d)"
"$INSTALL" "$t" --platform apple --features recommended > /dev/null
before_stamp="$(python3 -c "import json;print(json.load(open('$t/.claude/.appbootstrap-manifest.json'))['installed_at'])")"
if "$INSTALL" "$t" --platform apple --features recommended > /tmp/reinstall.out 2>&1; then
    red "FAIL: re-install over managed target should exit non-zero"; FAIL=$((FAIL + 1))
else
    after_stamp="$(python3 -c "import json;print(json.load(open('$t/.claude/.appbootstrap-manifest.json'))['installed_at'])")"
    if grep -q -- "--upgrade" /tmp/reinstall.out && [[ "$before_stamp" == "$after_stamp" ]]; then
        PASS=$((PASS + 1))   # refused, steered to --upgrade, and baseline NOT rewritten
    else
        red "FAIL: managed re-install should steer to --upgrade and leave the manifest untouched"
        FAIL=$((FAIL + 1))
    fi
fi
rm -f /tmp/reinstall.out
rm -rf "$t"

bold "==> --force allows re-install over a managed target"
t="$(mktemp -d)"
"$INSTALL" "$t" --platform apple --features recommended > /dev/null
if "$INSTALL" "$t" --platform apple --features recommended --force > /dev/null 2>&1; then
    PASS=$((PASS + 1))
else
    red "FAIL: --force should permit re-install over a managed target"
    FAIL=$((FAIL + 1))
fi
rm -rf "$t"

bold "==> --force / --new rejected on non-install actions"
if "$INSTALL" /tmp/x --upgrade --new > /dev/null 2>&1; then red "FAIL: --new should require install"; FAIL=$((FAIL+1)); else PASS=$((PASS+1)); fi
if "$INSTALL" /tmp/x --upgrade --force > /dev/null 2>&1; then red "FAIL: --force should require install"; FAIL=$((FAIL+1)); else PASS=$((PASS+1)); fi

bold "==> --interactive: ADOPT into an existing repo (piped answers)"
t="$(mktemp -d)"
# answers: target, platform=apple, apple-lang(Enter), features(Enter), agents(Enter), mcps? n, proceed? y
printf '%s\napple\n\n\n\n\nn\ny\n' "$t" | "$INSTALL" --interactive > /dev/null 2>&1
if [[ -f "$t/CLAUDE.md" && -f "$t/.claude/rules/apple-swift6-strict-concurrency.md" ]]; then
    PASS=$((PASS + 1))
else
    red "FAIL: interactive adopt should install into the existing repo"
    FAIL=$((FAIL + 1))
fi
rm -rf "$t"

bold "==> --interactive: CREATE a new project (piped answers)"
t="$(mktemp -d)/inew"
# answers: target, create? y, platform=android, features(Enter), agents(Enter), mcps? n, proceed? y
printf '%s\ny\nandroid\n\n\n\nn\ny\n' "$t" | "$INSTALL" --interactive > /dev/null 2>&1
if [[ -d "$t" && -f "$t/.claude/rules/android-project-rules.md" ]]; then
    PASS=$((PASS + 1))
else
    red "FAIL: interactive create should mkdir + install"
    FAIL=$((FAIL + 1))
fi
rm -rf "$(dirname "$t")"

bold "==> --interactive: managed dir routes to UPGRADE (plan only, no writes)"
t="$(mktemp -d)"
"$INSTALL" "$t" --platform apple --features recommended > /dev/null
python3 -c "import json;p='$t/.claude/.appbootstrap-manifest.json';m=json.load(open(p));m['bundle_commit']='oldcommit0000';json.dump(m,open(p,'w'),indent=2)"
out="$(printf '%s\ny\nn\n' "$t" | "$INSTALL" --interactive 2>&1)"
still_old="$(python3 -c "import json;print(json.load(open('$t/.claude/.appbootstrap-manifest.json'))['bundle_commit'])")"
if grep -q "Upgrade plan" <<<"$out" && [[ "$still_old" == "oldcommit0000" ]]; then
    PASS=$((PASS + 1))   # ran the plan, wrote nothing
else
    red "FAIL: interactive on managed dir should run upgrade plan without writing"
    FAIL=$((FAIL + 1))
fi
rm -rf "$t"


# --- subcommand verbs (backward-compatible with the --flag forms) ------------

bold "==> verb: 'list' equals '--list'"
a="$("$INSTALL" list --platform apple --features recommended 2>&1)"
b="$("$INSTALL" --list --platform apple --features recommended 2>&1)"
[[ "$a" == "$b" && -n "$a" ]] && PASS=$((PASS + 1)) \
    || { red "FAIL: 'list' verb should match '--list'"; FAIL=$((FAIL + 1)); }

bold "==> verb: 'list-mcps' equals '--list-mcps'"
a="$("$INSTALL" list-mcps 2>&1)"
b="$("$INSTALL" --list-mcps 2>&1)"
[[ "$a" == "$b" && -n "$a" ]] && PASS=$((PASS + 1)) \
    || { red "FAIL: 'list-mcps' verb should match '--list-mcps'"; FAIL=$((FAIL + 1)); }

bold "==> verb: 'help' equals '--help'"
a="$("$INSTALL" help 2>&1)"
b="$("$INSTALL" --help 2>&1)"
[[ "$a" == "$b" && -n "$a" ]] && PASS=$((PASS + 1)) \
    || { red "FAIL: 'help' verb should match '--help'"; FAIL=$((FAIL + 1)); }

bold "==> verb: 'install <dir>' installs (verb may precede the target)"
t="$(mktemp -d)"
"$INSTALL" install "$t" --platform apple --features recommended > /dev/null
[[ -f "$t/.claude/.appbootstrap-manifest.json" ]] && PASS=$((PASS + 1)) \
    || { red "FAIL: 'install' verb should install into the target"; FAIL=$((FAIL + 1)); }
rm -rf "$t"

bold "==> verb: 'upgrade <dir>' runs the plan like '--upgrade'"
t="$(mktemp -d)"
"$INSTALL" "$t" --platform apple --features recommended > /dev/null
# Capture then grep — piping straight into `grep -q` under `set -o pipefail`
# lets grep close the pipe early, SIGPIPE-ing install.sh and flipping the `if`.
up_out="$("$INSTALL" upgrade "$t" 2>&1)"
if grep -qi "upgrade plan" <<< "$up_out"; then
    PASS=$((PASS + 1))
else
    red "FAIL: 'upgrade' verb should print the upgrade plan"; FAIL=$((FAIL + 1))
fi
# Verb form, plan-only, must leave the manifest untouched (same as --upgrade).
before="$(python3 -c "import json;print(json.load(open('$t/.claude/.appbootstrap-manifest.json'))['installed_at'])")"
"$INSTALL" upgrade "$t" > /dev/null 2>&1
after="$(python3 -c "import json;print(json.load(open('$t/.claude/.appbootstrap-manifest.json'))['installed_at'])")"
[[ "$before" == "$after" ]] && PASS=$((PASS + 1)) \
    || { red "FAIL: 'upgrade' verb (plan-only) should not rewrite the manifest"; FAIL=$((FAIL + 1)); }
rm -rf "$t"

bold "==> verb: 'uninstall <dir>' removes like '--uninstall'"
t="$(mktemp -d)"
"$INSTALL" "$t" --platform apple --features recommended > /dev/null
"$INSTALL" uninstall "$t" > /dev/null 2>&1
[[ -f "$t/.claude/.appbootstrap-manifest.json" ]] \
    && { red "FAIL: 'uninstall' verb should remove the manifest"; FAIL=$((FAIL + 1)); } \
    || PASS=$((PASS + 1))
rm -rf "$t"

bold "==> verb: 'setup' routes to the interactive flow (piped adopt answers)"
t="$(mktemp -d)"
printf '%s\napple\n\n\n\n\nn\ny\n' "$t" | "$INSTALL" setup > /dev/null 2>&1
[[ -f "$t/.claude/rules/apple-swift6-strict-concurrency.md" ]] && PASS=$((PASS + 1)) \
    || { red "FAIL: 'setup' verb should run interactive + install"; FAIL=$((FAIL + 1)); }
rm -rf "$t"

bold "==> a non-verb dir name is still treated as the install target"
t="$(mktemp -d)"   # random tmp name — never collides with a verb
"$INSTALL" "$t" --platform android --features recommended > /dev/null
[[ -f "$t/.claude/rules/android-project-rules.md" ]] && PASS=$((PASS + 1)) \
    || { red "FAIL: a non-verb dir name should be the install target"; FAIL=$((FAIL + 1)); }
rm -rf "$t"


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

# --- Installer safety --------------------------------------------------------

bold "==> Package.resolved is ignored only for a library"
t_app="$(mktemp -d)"; mkdir -p "$t_app/App.xcodeproj"; touch "$t_app/Package.swift"
"$INSTALL" "$t_app" --platform apple >/dev/null
check "app install must not ignore Package.resolved" bash -c "! grep -qx 'Package.resolved' '$t_app/.gitignore'"
t_lib="$(mktemp -d)"; touch "$t_lib/Package.swift"
"$INSTALL" "$t_lib" --platform apple >/dev/null
check "library install should ignore Package.resolved" grep -qx 'Package.resolved' "$t_lib/.gitignore"

bold "==> unknown flags and missing values are rejected"
t_flag="$(mktemp -d)"
check "a typo'd flag must fail, not become the target" bash -c "! '$INSTALL' '$t_flag' --dryrun >/dev/null 2>&1"
check "a typo'd flag must not create a directory" bash -c "[[ ! -e ./--dryrun ]]"
check "a value flag with no value must fail clearly" bash -c "'$INSTALL' '$t_flag' --platform 2>&1 | grep -q 'needs a value'"
check "a second positional must fail" bash -c "! '$INSTALL' '$t_flag' '$t_flag' >/dev/null 2>&1"
check "scaffold rejects a flag with no value" bash -c "'$REPO_ROOT/scripts/scaffold-spm-package.sh' '$t_flag' --name 2>&1 | grep -q 'needs a value'"

bold "==> install keeps existing, different rule and skill files"
t_keep="$(mktemp -d)"; mkdir -p "$t_keep/.claude/rules" "$t_keep/.claude/skills/swiftui-pro"
echo "my own rule" > "$t_keep/.claude/rules/apple-logging-strategy.md"
echo "my own skill" > "$t_keep/.claude/skills/swiftui-pro/SKILL.md"
cp "$REPO_ROOT/.claude/rules/apple-testing-strategy.md" "$t_keep/.claude/rules/"
keep_out="$("$INSTALL" "$t_keep" --platform apple 2>&1)"
check "user-edited rule must not be overwritten" grep -qx 'my own rule' "$t_keep/.claude/rules/apple-logging-strategy.md"
check "user-edited skill file must not be overwritten" grep -qx 'my own skill' "$t_keep/.claude/skills/swiftui-pro/SKILL.md"
check "kept files are reported" grep -q 'apple-logging-strategy.md' <<<"$keep_out"
check "skill dir must not be nested inside itself" bash -c "[[ ! -e '$t_keep/.claude/skills/swiftui-pro/swiftui-pro' ]]"
check "other files of a kept skill still install" test -d "$t_keep/.claude/skills/swiftui-pro/references"
check "identical pre-existing rule is adopted into the manifest" \
    grep -q '"path": ".claude/rules/apple-testing-strategy.md"' "$t_keep/.claude/.appbootstrap-manifest.json"
check "kept user file is not claimed by the manifest" \
    bash -c "! grep -q '\"path\": \".claude/rules/apple-logging-strategy.md\"' '$t_keep/.claude/.appbootstrap-manifest.json'"

bold "==> shipped settings.json doesn't pre-approve pushes or gh writes"
check "settings.json must not allow git push" bash -c "! grep -q '\"Bash(git push:' '$REPO_ROOT/.claude/settings.json'"
check "settings.json must not allow every gh command" bash -c "! grep -q 'Bash(gh:\*)' '$REPO_ROOT/.claude/settings.json'"
rm -rf "$t_app" "$t_lib" "$t_flag" "$t_keep"

# The bundle is app- and company-agnostic: no employer, product, or program
# names in rules, skills, docs, templates, or tooling. Add new terms to
# FORBIDDEN_NAMES; this file is excluded so the list itself doesn't match.
bold "==> no app- or company-specific names in the bundle"

FORBIDDEN_NAMES='amazon|kuiper|\bleo\b'
forbidden_hits="$(grep -rniIE --exclude-dir=.git --exclude-dir=node_modules --exclude-dir=dist --exclude="$(basename "${BASH_SOURCE[0]}")" \
    "$FORBIDDEN_NAMES" "$REPO_ROOT" || true)"
if [[ -z "$forbidden_hits" ]]; then
    PASS=$((PASS + 1))
else
    red "FAIL: app- or company-specific names found (use a generic example instead):"
    printf '%s\n' "$forbidden_hits"
    FAIL=$((FAIL + 1))
fi

finish
