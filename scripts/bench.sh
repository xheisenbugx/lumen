#!/usr/bin/env bash
# Median startup time over N runs (default 10), in the sandbox.
# With BENCH_MAX_EMPTY_MS / BENCH_MAX_FILE_MS set, exits 1 when a median goes over its budget (CI).
set -euo pipefail
source "$(dirname "$0")/env.sh"
cd "$LUMEN_ROOT"
runs="${1:-10}"
tmp="$(mktemp -d)"
median() { grep "NVIM STARTED" "$1" | awk '{print $1+0}' | sort -n | awk '{a[NR]=$1} END {printf "%.1f", a[int((NR+1)/2)]}'; }
for _ in $(seq "$runs"); do
  nvim --headless --startuptime "$tmp/empty" +qa >/dev/null 2>&1
  nvim --headless --startuptime "$tmp/file" lua/lumen/lsp.lua +qa >/dev/null 2>&1
done
empty="$(median "$tmp/empty")"
file="$(median "$tmp/file")"
rm -rf "$tmp"
echo "nvim            → $empty ms"
echo "nvim file.lua   → $file ms"

status=0
over() { awk -v v="$1" -v max="$2" 'BEGIN { exit !(v > max) }'; }
if [ -n "${BENCH_MAX_EMPTY_MS:-}" ] && over "$empty" "$BENCH_MAX_EMPTY_MS"; then
  echo "✗ empty start: $empty ms is over the $BENCH_MAX_EMPTY_MS ms budget" >&2
  status=1
fi
if [ -n "${BENCH_MAX_FILE_MS:-}" ] && over "$file" "$BENCH_MAX_FILE_MS"; then
  echo "✗ opening a file: $file ms is over the $BENCH_MAX_FILE_MS ms budget" >&2
  status=1
fi
exit "$status"
