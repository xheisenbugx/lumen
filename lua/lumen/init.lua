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

  -- `User LumenFileIdle`: the same moment, one tick later, i.e. after the file is on screen.
  -- For plugins that attach to already-open buffers by themselves (gitsigns) and so don't
  -- need to sit in the file-open path.
  vim.api.nvim_create_autocmd({ "BufReadPost", "BufNewFile", "BufWritePost" }, {
    group = vim.api.nvim_create_augroup("lumen_file_idle", { clear = true }),
    once = true,
    callback = function()
      vim.schedule(function()
        vim.api.nvim_exec_autocmds("User", { pattern = "LumenFileIdle", modeline = false })
      end)
    end,
  })
end

---@param opts? table settings from the lumen spec's `opts` (merged over lua/config/lumen.lua)
function M.setup(opts)
  M.init()
  local config = require("lumen.config")
  opts = opts or {}
  config.merge(opts)

  -- settings read before the spec opts existed (options.lua, snacks' spec): apply them now
  if opts.format_on_save ~= nil then
    vim.g.lumen_autoformat = config.format_on_save
  end
  if opts.smooth_scroll ~= nil and _G.Snacks then
    -- snacks enables scrolling on UIEnter, which comes after this
    Snacks.config.scroll.enabled = config.smooth_scroll
    if not config.smooth_scroll and Snacks.scroll.enabled then
      Snacks.scroll.disable()
    end
  end

  -- keeps Lumen's statusline/tabline/winbar styled under any colorscheme
  require("lumen.colors.compat").setup()

  -- lazy.nvim only loads a colorscheme plugin when no scheme of that name is on the rtp yet, but
  -- Neovim 0.12+ bundles `catppuccin`: `:colorscheme catppuccin` would get the bundled one, without
  -- the plugin or its options. Load the plugin that ships the scheme first, so it wins on the rtp.
  vim.api.nvim_create_autocmd("ColorSchemePre", {
    group = vim.api.nvim_create_augroup("lumen_colorscheme_plugins", { clear = true }),
    callback = function(ev)
      for _, plugin in pairs(require("lazy.core.config").plugins) do
        if not plugin._.loaded and plugin.dir then
          for _, ext in ipairs({ "lua", "vim" }) do
            if vim.uv.fs_stat(plugin.dir .. "/colors/" .. ev.match .. "." .. ext) then
              require("lazy").load({ plugins = { plugin.name } })
              return
            end
          end
        end
      end
    end,
  })

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
    -- cheaper sign lookup for Snacks' statuscolumn (after the UI is up: it's loaded on first use)
    Lumen.on_very_lazy(function()
      if vim.o.statuscolumn:find("snacks.statuscolumn", 1, true) then
        require("lumen.ui.statuscolumn").setup()
      end
    end)

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
  -- run now if snacks is loaded, or if the user disabled it (Lumen then falls back to built-ins)
  if _G.Snacks or not require("lazy.core.config").plugins["snacks.nvim"] then
    return fn()
  end
  Lumen.on_load("snacks.nvim", fn)
end

return M
