# Source to get an isolated Lumen environment (used by test/bench scripts).
# The sandbox config is the real starter, loading Lumen from this checkout — exactly what users run.
LUMEN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LUMEN_SBX="${LUMEN_TEST_DIR:-$LUMEN_ROOT/.tests}"
_cfg="$LUMEN_SBX/config/lumen"
[ -L "$_cfg" ] && rm "$_cfg"
mkdir -p "$_cfg"
cp -R "$LUMEN_ROOT/starter/." "$_cfg/"
LUMEN_SPEC="{ dir = \"$LUMEN_ROOT\", name = \"lumen\", import = \"lumen.plugins\" }," \
  perl -pi -e 's/\{ [^{}]*name = "lumen", import = "lumen\.plugins" \},/$ENV{LUMEN_SPEC}/' "$_cfg/init.lua"
unset _cfg
export NVIM_APPNAME=lumen
export XDG_CONFIG_HOME="$LUMEN_SBX/config" XDG_DATA_HOME="$LUMEN_SBX/data"
export XDG_STATE_HOME="$LUMEN_SBX/state" XDG_CACHE_HOME="$LUMEN_SBX/cache"
