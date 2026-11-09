#!/usr/bin/env bash
# install-smoke-test.sh: run the installer smoke tests in .github/scripts/smoke/.
#
# Each part runs install.sh (or the scaffold script) against scratch
# directories and asserts on what lands. With no arguments every part runs, in
# sequence, and the script fails if any part failed. Name parts to run only
# those:
#
#   bash .github/scripts/install-smoke-test.sh                # all
#   bash .github/scripts/install-smoke-test.sh upgrade audit  # just these
#
# CI runs one part per job (install-smoke-test.yml), so a failure names the
# area that broke.

set -uo pipefail

SMOKE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/smoke" && pwd)"
ALL_PARTS=(install agents categories upgrade uninstall audit scaffold)

if [[ $# -gt 0 ]]; then
    parts=("$@")
else
    parts=("${ALL_PARTS[@]}")
fi

failed=()
for part in "${parts[@]}"; do
    if [[ ! -f "$SMOKE_DIR/$part.sh" ]]; then
        echo "error: no smoke-test part '$part' (have: ${ALL_PARTS[*]})" >&2
        exit 2
    fi
    printf '\n\033[1m######## %s ########\033[0m\n' "$part"
    bash "$SMOKE_DIR/$part.sh" || failed+=("$part")
done

echo
if [[ ${#failed[@]} -eq 0 ]]; then
    printf '\033[32mAll smoke-test parts passed: %s\033[0m\n' "${parts[*]}"
else
    printf '\033[31mFailed parts: %s\033[0m\n' "${failed[*]}"
    exit 1
fi
