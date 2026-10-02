#!/usr/bin/env bash
# Build and check the vetted plugin lockfile behind `update_channel = "stable"`.
#   scripts/vetted-lock.sh resolve <out.json>   newest versions of every plugin, all packs enabled
#   scripts/vetted-lock.sh verify  <lock.json>  install exactly those, load every plugin, run the suite
# Uses an isolated sandbox (LUMEN_TEST_DIR, default .tests-lock/). CI runs it nightly.
set -euo pipefail
mode="${1:-}"
lock="${2:-}"
[ -n "$mode" ] && [ -n "$lock" ] || { echo "usage: $0 resolve|verify <lockfile>" >&2; exit 1; }
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export LUMEN_TEST_DIR="${LUMEN_TEST_DIR:-$here/../.tests-lock}"
lock="$(cd "$(dirname "$lock")" && pwd)/$(basename "$lock")"
source "$here/env.sh"
cd "$LUMEN_ROOT"

packs_state="$XDG_STATE_HOME/lumen/lumen/packs.json"
all_packs() {
  mkdir -p "$(dirname "$packs_state")"
  local names
  names="$(ls lua/lumen/packs/*.lua | xargs -n1 basename | sed 's/\.lua$//' | sed 's/.*/"&"/' | paste -sd, -)"
  printf '{"enabled":[%s],"disabled":[],"dismissed":[]}\n' "$names" >"$packs_state"
}
cfg_lock="$XDG_CONFIG_HOME/lumen/lazy-lock.json"

case "$mode" in
  resolve)
    all_packs
    rm -f "$cfg_lock"
    nvim --headless "+Lazy! sync" +qa
    cp "$cfg_lock" "$lock"
    echo "resolved $(grep -c '"commit"' "$lock") plugins → $lock"
    ;;
  verify)
    all_packs
    cp "$lock" "$cfg_lock"
    nvim --headless "+Lazy! restore" +qa
    # every plugin must load and configure without errors (same check :Lumen update runs)
    nvim --headless -c "lua require('lumen.update').selftest()"
    echo "✓ all plugins load at the vetted versions"
    # parser downloads cut short when that check exited leave temp dirs behind
    rm -rf "$XDG_CACHE_HOME"/lumen/tree-sitter-*
    # then the smoke suite, with the default packs
    rm -f "$packs_state"
    bash "$here/test.sh"
    ;;
  *)
    echo "unknown mode: $mode" >&2
    exit 1
    ;;
esac
