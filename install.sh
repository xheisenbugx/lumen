#!/usr/bin/env bash
# Install the Lumen starter: a tiny config dir (init.lua + your settings) that loads Lumen as a
# lazy.nvim plugin, exactly like LazyVim. Lumen itself updates with :Lazy update / :Lumen update.
#
#   curl -fsSL https://raw.githubusercontent.com/xheisenbugx/lumen/main/install.sh | bash
#   … | bash -s -- --appname lumen   → ~/.config/lumen, start it with `NVIM_APPNAME=lumen nvim`
#
# Options:
#   --appname <name>   config dir name under ~/.config (default: nvim)
#   --fresh            also back up the app's data/state/cache dirs (clean switch from another distro)
#   --repo <owner/name>  load Lumen from this GitHub repo (default: xheisenbugx/lumen)
#   --dev              load Lumen from the local checkout this script lives in (for contributors)
#
# Anything already at the destination is moved to <dir>.bak-<timestamp>, never deleted.
set -euo pipefail

appname="nvim"
repo="xheisenbugx/lumen"
fresh=0
dev=0

while [ $# -gt 0 ]; do
  case "$1" in
    --appname) appname="$2"; shift 2 ;;
    --repo) repo="$2"; shift 2 ;;
    --fresh) fresh=1; shift ;;
    --dev) dev=1; shift ;;
    -h|--help) sed -n '2,14p' "${BASH_SOURCE[0]:-$0}" 2>/dev/null || true; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 1 ;;
  esac
done

for tool in git nvim; do
  command -v "$tool" >/dev/null || { echo "error: \`$tool\` is required" >&2; exit 1; }
done

# the starter template: next to this script when run from a checkout, otherwise fetch it
here=""
if [ -n "${BASH_SOURCE[0]:-}" ] && [ -f "${BASH_SOURCE[0]}" ]; then
  here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi
if [ -n "$here" ] && [ -d "$here/starter" ]; then
  src="$here"
else
  [ "$dev" = 1 ] && { echo "error: --dev needs a local checkout (run ./install.sh from the repo)" >&2; exit 1; }
  src="$(mktemp -d)"
  trap 'rm -rf "$src"' EXIT
  echo "• fetching the starter from github.com/$repo"
  git clone --quiet --depth 1 "https://github.com/$repo.git" "$src"
fi

stamp="$(date +%Y%m%d-%H%M%S)"
backup() {
  local dir="$1"
  if [ -L "$dir" ]; then
    rm "$dir"
    echo "• removed old symlink $dir"
  elif [ -e "$dir" ]; then
    mv "$dir" "$dir.bak-$stamp"
    echo "• backed up $dir → $dir.bak-$stamp"
  fi
}

config="${XDG_CONFIG_HOME:-$HOME/.config}/$appname"
backup "$config"
if [ "$fresh" = 1 ]; then
  backup "${XDG_DATA_HOME:-$HOME/.local/share}/$appname"
  backup "${XDG_STATE_HOME:-$HOME/.local/state}/$appname"
  backup "${XDG_CACHE_HOME:-$HOME/.cache}/$appname"
fi

mkdir -p "$(dirname "$config")"
cp -R "$src/starter" "$config"

if [ "$dev" = 1 ]; then
  spec="{ dir = \"$src\", name = \"lumen\", import = \"lumen.plugins\" },"
else
  spec="{ \"$repo\", name = \"lumen\", import = \"lumen.plugins\" },"
fi
LUMEN_SPEC="$spec" perl -pi -e 's/\{ [^{}]*name = "lumen", import = "lumen\.plugins" \},/$ENV{LUMEN_SPEC}/' "$config/init.lua"

echo "✓ Lumen installed in $config"
echo "  your whole config: init.lua · lua/config/lumen.lua (settings) · lua/plugins/ (extra plugins)"
if [ "$appname" = "nvim" ]; then
  echo "  start it with: nvim"
else
  echo "  start it with: NVIM_APPNAME=$appname nvim"
fi
echo "  first launch installs plugins, parsers and language servers — then run :checkhealth lumen"
