#!/usr/bin/env bash
# Smoke test, upgrade: plan, --apply, MCP diff, skill-dir renames, compare URL.
# Run one part with `bash .github/scripts/smoke/upgrade.sh`, or all of them
# with `bash .github/scripts/install-smoke-test.sh`.

# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

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


# --- Skill-directory renames (Phase 5a) -------------------------------------
#
# Synthesize a RENAMES.md entry, fake a manifest pointing at the old skill name,
# and verify the upgrade flow folds the migration into rename rows + applies.

bold "==> RENAMES.md: skill-dir rename surfaces in plan as 'Renames — safe'"
t="$(mktemp -d)"
# Snapshot+restore RENAMES.md around the test so we don't pollute the repo.
cp "$REPO_ROOT/RENAMES.md" /tmp/RENAMES.md.smoke-bak
cat >> "$REPO_ROOT/RENAMES.md" <<'EOF'

swift-old-test-pro -> swift-concurrency-pro
EOF
"$INSTALL" "$t" --platform apple --features recommended > /dev/null
# Mirror the new skill's files under the old-name path; mark the manifest as old.
python3 -c "
import json, os, shutil
m = json.load(open('$t/.claude/.appbootstrap-manifest.json'))
new_files = []
for entry in m['files']:
    if entry.get('skill') == 'swift-concurrency-pro' and 'assets/' not in entry['path']:
        old_path = entry['path'].replace('swift-concurrency-pro', 'swift-old-test-pro')
        os.makedirs(os.path.dirname(os.path.join('$t', old_path)), exist_ok=True)
        shutil.copy(os.path.join('$t', entry['path']), os.path.join('$t', old_path))
        new_files.append({**entry, 'path': old_path, 'skill': 'swift-old-test-pro'})
    else:
        new_files.append(entry)
m['files'] = new_files
json.dump(m, open('$t/.claude/.appbootstrap-manifest.json','w'), indent=2)
# Remove the new-name files from disk so the rename target is a real move.
import shutil
for f in os.listdir('$t/.claude/skills/swift-concurrency-pro/references'):
    os.remove(os.path.join('$t/.claude/skills/swift-concurrency-pro/references', f))
"
out="$("$INSTALL" "$t" --upgrade 2>&1)"
if grep -q "Renames — safe" <<<"$out" \
    && grep -q "swift-old-test-pro" <<<"$out" \
    && grep -q "swift-concurrency-pro" <<<"$out"; then
    PASS=$((PASS + 1))
else
    red "FAIL: skill-dir rename should surface as 'Renames — safe' in the plan"
    FAIL=$((FAIL + 1))
fi
# Restore RENAMES.md
mv /tmp/RENAMES.md.smoke-bak "$REPO_ROOT/RENAMES.md"
rm -rf "$t"

bold "==> RENAMES.md: skill-dir rename --apply moves files; manifest updates"
t="$(mktemp -d)"
cp "$REPO_ROOT/RENAMES.md" /tmp/RENAMES.md.smoke-bak
cat >> "$REPO_ROOT/RENAMES.md" <<'EOF'

swift-old-test-pro -> swift-concurrency-pro
EOF
"$INSTALL" "$t" --platform apple --features recommended > /dev/null
# Realistic-rename synthesis: user installed a hypothetical earlier "swift-old-test-pro"
# skill (which the bundle has since renamed to swift-concurrency-pro). To simulate
# that, mirror non-asset files of swift-concurrency-pro under the old name AND
# remove ALL of swift-concurrency-pro from disk (the user only has the old version).
python3 -c "
import json, os, shutil
m = json.load(open('$t/.claude/.appbootstrap-manifest.json'))
new_files = []
for entry in m['files']:
    if entry.get('skill') == 'swift-concurrency-pro' and 'assets/' not in entry['path']:
        old_path = entry['path'].replace('swift-concurrency-pro', 'swift-old-test-pro')
        os.makedirs(os.path.dirname(os.path.join('$t', old_path)), exist_ok=True)
        shutil.copy(os.path.join('$t', entry['path']), os.path.join('$t', old_path))
        new_files.append({**entry, 'path': old_path, 'skill': 'swift-old-test-pro'})
    elif entry.get('skill') != 'swift-concurrency-pro':
        new_files.append(entry)
    # asset entries for swift-concurrency-pro are dropped — they're a real-world
    # collision (asset filenames contain the skill name; can't auto-fold).
m['files'] = new_files
json.dump(m, open('$t/.claude/.appbootstrap-manifest.json','w'), indent=2)
shutil.rmtree('$t/.claude/skills/swift-concurrency-pro', ignore_errors=True)
"
"$INSTALL" "$t" --upgrade --apply > /dev/null
old_dir_present="false"
[[ -d "$t/.claude/skills/swift-old-test-pro" ]] && old_dir_present="true"
new_files_present="false"
[[ -f "$t/.claude/skills/swift-concurrency-pro/references/structured.md" ]] && new_files_present="true"
manifest_has_old="$(python3 -c "import json; m=json.load(open('$t/.claude/.appbootstrap-manifest.json')); print(any('swift-old-test-pro' in f['path'] for f in m['files']))")"
if [[ "$old_dir_present" == "false" && "$new_files_present" == "true" && "$manifest_has_old" == "False" ]]; then
    PASS=$((PASS + 1))
else
    red "FAIL: rename --apply should move files to new skill dir and drop old manifest entries"
    FAIL=$((FAIL + 1))
fi
mv /tmp/RENAMES.md.smoke-bak "$REPO_ROOT/RENAMES.md"
rm -rf "$t"


# --- GitHub compare URL (Phase 5c) ------------------------------------------

bold "==> --upgrade: GitHub compare URL appears when manifest commit differs from bundle"
t="$(mktemp -d)"
"$INSTALL" "$t" --platform apple --features recommended > /dev/null
# Fake an older commit in the manifest so a compare is meaningful.
python3 -c "
import json
m = json.load(open('$t/.claude/.appbootstrap-manifest.json'))
m['bundle_commit'] = '6a1afb1461fb26d070722b7916c1dbb37260e13b'  # a real older commit
json.dump(m, open('$t/.claude/.appbootstrap-manifest.json','w'), indent=2)
"
out="$("$INSTALL" "$t" --upgrade 2>&1)"
if grep -q "https://github.com/.*/compare/6a1afb14" <<<"$out"; then
    PASS=$((PASS + 1))
else
    red "FAIL: upgrade plan should print a GitHub compare URL when commits differ"
    FAIL=$((FAIL + 1))
fi
rm -rf "$t"

bold "==> --upgrade: no compare URL when manifest commit matches current"
t="$(mktemp -d)"
"$INSTALL" "$t" --platform apple --features recommended > /dev/null
out="$("$INSTALL" "$t" --upgrade 2>&1)"
# manifest_commit == current bundle_commit → no compare line
if ! grep -q "changes between them:" <<<"$out"; then
    PASS=$((PASS + 1))
else
    red "FAIL: compare URL should be suppressed when manifest_commit == current commit"
    FAIL=$((FAIL + 1))
fi
rm -rf "$t"

bold "==> --upgrade: no compare URL when manifest commit is 'unknown'"
t="$(mktemp -d)"
"$INSTALL" "$t" --platform apple --features recommended > /dev/null
python3 -c "
import json
m = json.load(open('$t/.claude/.appbootstrap-manifest.json'))
m['bundle_commit'] = 'unknown'
json.dump(m, open('$t/.claude/.appbootstrap-manifest.json','w'), indent=2)
"
out="$("$INSTALL" "$t" --upgrade 2>&1)"
if ! grep -q "changes between them:" <<<"$out"; then
    PASS=$((PASS + 1))
else
    red "FAIL: compare URL should be suppressed when bundle_commit is 'unknown'"
    FAIL=$((FAIL + 1))
fi
rm -rf "$t"

finish
