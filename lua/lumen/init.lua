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

  -- everything else uses snacks.nvim. Normally it is already loaded (priority 1000 > 900), but on
  -- a first launch lazy.nvim loads the install colorscheme (`lumen`) before anything else, so wait
  M.after_snacks(function()
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

    Lumen.on_very_lazy(M.welcome)
  end)

  -- `:restart` (e.g. after enabling a pack) restores the session into the current window. If
  -- lazy.nvim just installed the pack's plugins, that is its (finished) install float, and the
  -- restored file would end up inside it. Plugins are installed by then, so close it.
  if (vim.v.startreason or ""):find("^restart") then
    vim.api.nvim_create_autocmd("VimEnter", {
      once = true,
      callback = function()
        local view = package.loaded["lazy.view"]
        if view and view.visible() then
          view.view:close()
        end
      end,
    })
  end
end

--- one-time hint on the very first launch with a UI
function M.welcome()
  local flag = vim.fn.stdpath("state") .. "/lumen/welcomed"
  if #vim.api.nvim_list_uis() == 0 or vim.uv.fs_stat(flag) then
    return
  end
  vim.fn.mkdir(vim.fs.dirname(flag), "p")
  local f = io.open(flag, "w")
  if f then
    f:close()
  end
  local leader = vim.g.mapleader == " " and "<space>" or (vim.g.mapleader or "\\")
  Lumen.notify(
    table.concat({
      "Welcome to Lumen! Parsers and language servers install in the background.",
      ("• press %s and wait to see every keymap · :Lumen (%sL) opens the menu"):format(leader, leader),
      ("• settings: lua/config/lumen.lua (%sfc) · languages: :Lumen packs"):format(leader),
      "• missing tools? run :checkhealth lumen",
    }, "\n"),
    nil,
    { timeout = 15000 }
  )
end

---@param fn fun()
function M.after_snacks(fn)
  if _G.Snacks then
    return fn()
  end
  Lumen.on_load("snacks.nvim", fn)
end

return M
