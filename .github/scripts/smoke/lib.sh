#!/usr/bin/env bash
# Shared setup for the smoke-test parts in this folder. Each part sources it,
# runs its assertions, and ends with `finish`.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
# shellcheck disable=SC2034  # used by the parts that source this file
INSTALL="$REPO_ROOT/install.sh"
PART="$(basename "${BASH_SOURCE[1]:-smoke}" .sh)"
PASS=0
FAIL=0

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


check() {  # check <description> <command...>: pass when the command succeeds
    local why="$1"; shift
    if "$@"; then PASS=$((PASS + 1)); else red "FAIL: $why"; FAIL=$((FAIL + 1)); fi
}

finish() {
    echo
    if [[ "$FAIL" -eq 0 ]]; then
        green "PASSED ($PART): $PASS assertions."
        exit 0
    else
        red "FAILED ($PART): $FAIL of $((PASS + FAIL)) assertions."
        exit 1
    fi
}
