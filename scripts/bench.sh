#!/usr/bin/env bash
# Median startup time over N runs (default 10), in the sandbox.
set -euo pipefail
source "$(dirname "$0")/env.sh"
cd "$LUMEN_ROOT"
runs="${1:-10}"
tmp="$(mktemp -d)"
median() { grep "NVIM STARTED" "$1" | awk '{print $1+0}' | sort -n | awk '{a[NR]=$1} END {printf "%.1f ms", a[int((NR+1)/2)]}'; }
for _ in $(seq "$runs"); do
  nvim --headless --startuptime "$tmp/empty" +qa >/dev/null 2>&1
  nvim --headless --startuptime "$tmp/file" lua/lumen/lsp.lua +qa >/dev/null 2>&1
done
echo "nvim            → $(median "$tmp/empty")"
echo "nvim file.lua   → $(median "$tmp/file")"
rm -rf "$tmp"
