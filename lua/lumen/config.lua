---@class lumen.Config
local defaults = {
  -- "lumen" follows 'background', or pin "lumen-night" / "lumen-dawn"
  colorscheme = "lumen",
  transparent = false,
  -- italic comments & keywords
  italics = true,
  -- the glow used for focus (cursor line nr, active tab, titles, matches):
  -- amber | orange | red | rose | violet | blue | sky | cyan | teal | green | yellow | "#rrggbb"
  accent = "amber",
  -- palette overrides per variant, e.g. { night = { bg = "#000000" } }
  colors = {},
  -- tweak any highlight: function(hl, palette) hl.Comment = { fg = palette.teal } end
  on_highlights = nil,

  -- per-window breadcrumbs (path › class › function) from LSP symbols
  winbar = true,
  -- right-edge scrollbar with diagnostics / git / search / cursor marks
  scrollbar = true,
  -- extra tasks for the task runner: { { name = "deploy", cmd = "./deploy.sh" } }, plus an optional
  -- `cwd` (default: the project root)
  tasks = {},
  -- how diagnostics show inline: "text" | "lines" (current line) | "signs"
  diagnostics = "text",

  -- language packs to enable (see :Lumen packs for the full list)
  packs = { "lua", "json", "yaml", "toml", "markdown", "bash" },
  -- offer to enable a pack when you open a filetype it supports
  suggest_packs = true,
  -- install missing treesitter parsers on demand when opening a file
  auto_install_parsers = true,

  format_on_save = true,
  inlay_hints = true,

  -- Lumen's own zero-dependency UI
  statusline = true,
  tabline = true,
  -- Neovim's new message/cmdline UI (0.12+); gives a clean `cmdheight=0` look
  ui2 = true,
  smooth_scroll = true,

  leader = " ",
  localleader = "\\",

  -- integrate <C-h/j/k/l> with tmux panes when inside tmux
  tmux_navigation = true,
}

local M = {}

---@type lumen.Config
local options = vim.deepcopy(defaults)

-- deep-merge `src` into `dst`, but replace lists (packs, tasks…) instead of merging them by index
local function merge(dst, src)
  for k, v in pairs(src) do
    if type(v) == "table" and not vim.islist(v) and type(dst[k]) == "table" and not vim.islist(dst[k]) then
      merge(dst[k], v)
    else
      dst[k] = v
    end
  end
  return dst
end

---@param mod string
local function user_module(mod)
  if not require("lumen.util").module_exists(mod) then
    return {}
  end
  local ok, res = pcall(require, mod)
  if ok then
    return type(res) == "table" and res or {}
  end
  if not tostring(res):find("module '" .. mod .. "' not found", 1, true) then
    vim.schedule(function()
      vim.notify(("Lumen: error in %s\n%s"):format(mod:gsub("%.", "/") .. ".lua", res), vim.log.levels.ERROR)
    end)
  end
  return {}
end

--- settings from your config dir: lua/config/lumen.lua (or the older lua/user/config.lua)
function M.load()
  options = vim.deepcopy(defaults)
  merge(options, user_module("user.config"))
  merge(options, user_module("config.lumen"))
end

-- settings needed while lazy.nvim builds the plugin list / before plugins map keys, i.e. before
-- any spec opts exist: they only work from lua/config/lumen.lua
local early = { "packs", "leader", "localleader", "ui2" }

--- runtime settings passed as `opts` on the lumen spec
---@param opts table
function M.merge(opts)
  local ignored = vim.tbl_filter(function(k)
    return opts[k] ~= nil
  end, early)
  if #ignored > 0 then
    vim.schedule(function()
      vim.notify(
        ("Lumen: `%s` in the spec opts is ignored — set it in lua/config/lumen.lua%s"):format(
          table.concat(ignored, "`, `"),
          vim.tbl_contains(ignored, "packs") and " or use :Lumen packs" or ""
        ),
        vim.log.levels.WARN
      )
    end)
    opts = vim.deepcopy(opts)
    for _, k in ipairs(ignored) do
      opts[k] = nil
    end
  end
  merge(options, opts)
end

M.defaults = defaults

return setmetatable(M, {
  __index = function(_, k)
    return options[k]
  end,
  __newindex = function(_, k, v)
    options[k] = v
  end,
})
