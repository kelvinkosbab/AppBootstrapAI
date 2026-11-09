#!/usr/bin/env bash
# Smoke test, uninstall: plan and apply.
# Run one part with `bash .github/scripts/smoke/uninstall.sh`, or all of them
# with `bash .github/scripts/install-smoke-test.sh`.

# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# --- --uninstall (Phase 5b) -------------------------------------------------

bold "==> --uninstall: default removes tracked files, keeps CLAUDE.md/settings.json"
t="$(mktemp -d)"
"$INSTALL" "$t" --platform apple --features recommended --with-mcps xcodebuildmcp > /dev/null
"$INSTALL" "$t" --uninstall > /dev/null
if [[ ! -f "$t/.claude/rules/apple-swift6-strict-concurrency.md" \
    && ! -f "$t/.claude/.appbootstrap-manifest.json" \
    && -f "$t/.claude/settings.json" \
    && -f "$t/CLAUDE.md" ]] \
    && ! grep -q "AppBootstrapAI" "$t/.gitignore"; then
    PASS=$((PASS + 1))
else
    red "FAIL: --uninstall should delete rules + manifest, keep settings.json/CLAUDE.md, strip gitignore block"
    FAIL=$((FAIL + 1))
fi
rm -rf "$t"

bold "==> --uninstall: locally-edited file is KEPT (skipped with warning)"
t="$(mktemp -d)"
"$INSTALL" "$t" --platform apple --features recommended > /dev/null
echo "# local edit" >> "$t/.claude/rules/apple-swift6-strict-concurrency.md"
"$INSTALL" "$t" --uninstall > /dev/null
if [[ -f "$t/.claude/rules/apple-swift6-strict-concurrency.md" ]] \
    && grep -q "local edit" "$t/.claude/rules/apple-swift6-strict-concurrency.md"; then
    PASS=$((PASS + 1))
else
    red "FAIL: --uninstall should NOT delete locally-edited files"
    FAIL=$((FAIL + 1))
fi
rm -rf "$t"

bold "==> --uninstall --force-conflicts: deletes user-edited files too"
t="$(mktemp -d)"
"$INSTALL" "$t" --platform apple --features recommended > /dev/null
echo "# local edit" >> "$t/.claude/rules/apple-swift6-strict-concurrency.md"
"$INSTALL" "$t" --uninstall --force-conflicts > /dev/null
if [[ ! -f "$t/.claude/rules/apple-swift6-strict-concurrency.md" ]]; then
    PASS=$((PASS + 1))
else
    red "FAIL: --uninstall --force-conflicts should delete the edited file"
    FAIL=$((FAIL + 1))
fi
rm -rf "$t"

bold "==> --uninstall --purge: also removes CLAUDE.md and settings.json"
t="$(mktemp -d)"
"$INSTALL" "$t" --platform apple --features recommended > /dev/null
"$INSTALL" "$t" --uninstall --purge > /dev/null
if [[ ! -f "$t/CLAUDE.md" && ! -f "$t/.claude/settings.json" ]]; then
    PASS=$((PASS + 1))
else
    red "FAIL: --uninstall --purge should remove CLAUDE.md and settings.json"
    FAIL=$((FAIL + 1))
fi
rm -rf "$t"

bold "==> --uninstall: removes MCP entries (matching install hash)"
t="$(mktemp -d)"
"$INSTALL" "$t" --platform apple --features recommended --with-mcps xcodebuildmcp > /dev/null
"$INSTALL" "$t" --uninstall > /dev/null
# settings.local.json might be deleted along with .claude/ — either way, no mcpServers
mcp_present="false"
if [[ -f "$t/.claude/settings.local.json" ]]; then
    has_mcp="$(python3 -c "import json; sl=json.load(open('$t/.claude/settings.local.json')); print('xcodebuildmcp' in sl.get('mcpServers',{}))")"
    [[ "$has_mcp" == "True" ]] && mcp_present="true"
fi
if [[ "$mcp_present" == "false" ]]; then
    PASS=$((PASS + 1))
else
    red "FAIL: --uninstall should remove unmodified MCP entries"
    FAIL=$((FAIL + 1))
fi
rm -rf "$t"

bold "==> --uninstall --keep-mcps: leaves MCP entries alone"
t="$(mktemp -d)"
"$INSTALL" "$t" --platform apple --features recommended --with-mcps xcodebuildmcp > /dev/null
"$INSTALL" "$t" --uninstall --keep-mcps > /dev/null
if [[ -f "$t/.claude/settings.local.json" ]] \
    && python3 -c "
import json, sys
sl = json.load(open('$t/.claude/settings.local.json'))
sys.exit(0 if 'xcodebuildmcp' in sl.get('mcpServers',{}) else 1)
"; then
    PASS=$((PASS + 1))
else
    red "FAIL: --uninstall --keep-mcps should leave MCP entries alone"
    FAIL=$((FAIL + 1))
fi
rm -rf "$t"

bold "==> --uninstall --dry-run: writes nothing"
t="$(mktemp -d)"
"$INSTALL" "$t" --platform apple --features recommended > /dev/null
"$INSTALL" "$t" --uninstall --dry-run > /dev/null
if [[ -f "$t/.claude/.appbootstrap-manifest.json" \
    && -f "$t/.claude/rules/apple-swift6-strict-concurrency.md" ]]; then
    PASS=$((PASS + 1))
else
    red "FAIL: --uninstall --dry-run must not write anything"
    FAIL=$((FAIL + 1))
fi
rm -rf "$t"

bold "==> --uninstall: validation — --purge requires --uninstall"
if "$INSTALL" /tmp/never --purge > /dev/null 2>&1; then
    red "FAIL: --purge without --uninstall should exit non-zero"; FAIL=$((FAIL + 1))
else
    PASS=$((PASS + 1))
fi

bold "==> --uninstall: validation — --keep-mcps requires --uninstall"
if "$INSTALL" /tmp/never --keep-mcps > /dev/null 2>&1; then
    red "FAIL: --keep-mcps without --uninstall should exit non-zero"; FAIL=$((FAIL + 1))
else
    PASS=$((PASS + 1))
fi

bold "==> --uninstall: no manifest at target → clean error"
t="$(mktemp -d)"
if "$INSTALL" "$t" --uninstall > /tmp/uninstall_none.out 2>&1; then
    red "FAIL: --uninstall against unmanaged target should exit non-zero"; FAIL=$((FAIL + 1))
else
    if grep -q "no manifest" /tmp/uninstall_none.out; then
        PASS=$((PASS + 1))
    else
        red "FAIL: --uninstall with no manifest should mention 'no manifest'"
        FAIL=$((FAIL + 1))
    fi
fi
rm -rf "$t" /tmp/uninstall_none.out

finish
