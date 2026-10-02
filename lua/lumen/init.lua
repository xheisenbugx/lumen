-- Lumen is a lazy.nvim plugin, used like LazyVim:
--
--   require("lazy").setup({ spec = { { "you/lumen", name = "lumen", import = "lumen.plugins" } } })
--
-- Two phases:
--   M.init()  — while lazy.nvim reads Lumen's spec (lua/lumen/plugins/init.lua), before any
--               plugin loads: settings, options, the LazyFile event.
--   M.setup() — the `lumen` plugin's config (right after snacks.nvim): colorscheme, keymaps,
--               autocmds, commands and Lumen's UI.
local M = {}

M.version = "0.2.0"

local did_init = false

function M.init()
  if did_init then
    return
  end
  did_init = true

  require("lumen.config").load()

  ---@type lumen.Util
  _G.Lumen = require("lumen.util")

  require("lumen.options")
  -- user options early, so leader & friends are set before plugins define keymaps
  Lumen.try_require("config.options")
  Lumen.try_require("user.options")

  -- `LazyFile`: fires when a real file is opened — the backbone of fast startup
  local Event = require("lazy.core.handler.event")
  Event.mappings.LazyFile = { id = "LazyFile", event = { "BufReadPost", "BufNewFile", "BufWritePre" } }
  Event.mappings["User LazyFile"] = Event.mappings.LazyFile
end

---@param opts? table settings from the lumen spec's `opts` (merged over lua/config/lumen.lua)
function M.setup(opts)
  M.init()
  local config = require("lumen.config")
  config.merge(opts or {})

  -- keeps Lumen's statusline/tabline/winbar styled under any colorscheme
  require("lumen.colors.compat").setup()

  local ok = pcall(vim.cmd.colorscheme, config.colorscheme)
  if not ok then
    vim.notify(("Lumen: colorscheme `%s` not found, using `lumen`"):format(config.colorscheme), vim.log.levels.WARN)
    vim.cmd.colorscheme("lumen")
  end

  require("lumen.autocmds")
  require("lumen.keymaps")
  require("lumen.commands")

  if config.statusline then
    require("lumen.ui.statusline").setup()
  end
  if config.tabline then
    require("lumen.ui.tabline").setup()
  end
  if config.winbar then
    require("lumen.ui.winbar").setup()
  end
  if config.scrollbar then
    require("lumen.ui.scrollbar").setup()
  end
  require("lumen.ui.fold").setup()

  -- user hooks, loaded last so they win (LazyVim-style names, plus the old lua/user/*)
  for _, mod in ipairs({ "config.autocmds", "config.keymaps", "user.autocmds", "user.keymaps" }) do
    Lumen.try_require(mod)
  end
end

return M
