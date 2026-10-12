#!/usr/bin/env bash
# Run Lumen's smoke tests in a sandbox. First run installs everything (slow); later runs are fast.
# `./scripts/test.sh tasks` only runs the checks whose name contains "tasks".
set -euo pipefail
source "$(dirname "$0")/env.sh"
cd "$LUMEN_ROOT"
nvim --headless "+Lazy! install" +qa >/dev/null 2>&1
LUMEN_TEST_FILTER="${1:-}" nvim --headless -c "luafile tests/smoke.lua" lua/lumen/init.lua
