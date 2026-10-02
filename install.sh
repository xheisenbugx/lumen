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

usage() {
  cat <<'EOF'
Install Lumen: a small Neovim config dir that loads Lumen as a lazy.nvim plugin (like LazyVim).

usage: install.sh [--appname <name>] [--fresh] [--repo <owner/name>] [--dev]

  --appname <name>     install to ~/.config/<name>; start it with `NVIM_APPNAME=<name> nvim`
                       (default: nvim, i.e. ~/.config/nvim)
  --fresh              also back up the app's data, state and cache dirs (clean switch from another distro)
  --repo <owner/name>  load Lumen from this GitHub repo (default: xheisenbugx/lumen)
  --dev                load Lumen from the local checkout this script lives in (for contributors)
  -h, --help           show this help

Anything already at the destination is moved to <dir>.bak-<timestamp>, never deleted.
EOF
}

die() {
  echo "error: $*" >&2
  echo "run with --help for usage" >&2
  exit 1
}

while [ $# -gt 0 ]; do
  case "$1" in
    --appname | --repo)
      { [ $# -ge 2 ] && [ -n "$2" ] && [ "${2#-}" = "$2" ]; } || die "$1 needs a value"
      if [ "$1" = --appname ]; then appname="$2"; else repo="$2"; fi
      shift 2
      ;;
    --fresh) fresh=1; shift ;;
    --dev) dev=1; shift ;;
    -h | --help) usage; exit 0 ;;
    *) die "unknown option: $1" ;;
  esac
done

# the app name becomes a directory under ~/.config, ~/.local/share…, so it must stay a plain name
case "$appname" in
  . | .. | */* | *[[:space:]]*) die "invalid --appname '$appname' (use a plain name such as 'lumen')" ;;
esac
case "$repo" in
  */*) ;;
  *) die "invalid --repo '$repo' (expected owner/name)" ;;
esac

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
  [ "$dev" = 1 ] && die "--dev needs a local checkout (run ./install.sh from the repo)"
  src="$(mktemp -d)"
  trap 'rm -rf "$src"' EXIT
  echo "• fetching the starter from github.com/$repo"
  git clone --quiet --depth 1 "https://github.com/$repo.git" "$src"
fi

stamp="$(date +%Y%m%d-%H%M%S)"
backup() {
  local dir="$1"
  # a symlink (e.g. from a dotfiles repo) is renamed too; its target is left untouched
  if [ -e "$dir" ] || [ -L "$dir" ]; then
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

# warn early about tools the first launch needs (:checkhealth lumen lists them all)
missing=()
command -v rg >/dev/null || missing+=("rg (search)")
command -v tree-sitter >/dev/null || missing+=("tree-sitter CLI (builds syntax parsers)")
command -v cc >/dev/null || command -v gcc >/dev/null || command -v clang >/dev/null || missing+=("a C compiler")
for m in ${missing[@]+"${missing[@]}"}; do
  echo "! missing: $m"
done
