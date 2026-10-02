-- Lumen — your whole Neovim config is this folder:
--   init.lua               bootstrap (this file — you rarely touch it)
--   lua/config/lumen.lua   settings: theme, accent, language packs, toggles
--   lua/plugins/*.lua      extra plugins & overrides (lazy.nvim specs)
--   lua/config/options.lua · keymaps.lua · autocmds.lua   optional, same as LazyVim

local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.uv.fs_stat(lazypath) then
  vim.fn.system({
    "git",
    "clone",
    "--filter=blob:none",
    "--branch=stable",
    "https://github.com/folke/lazy.nvim.git",
    lazypath,
  })
end
vim.opt.rtp:prepend(lazypath)

require("lazy").setup({
  spec = {
    { "xheisenbugx/lumen", name = "lumen", import = "lumen.plugins" },
    { import = "plugins" },
  },
  defaults = { lazy = true, version = false },
  install = { colorscheme = { "lumen" } },
  checker = { enabled = true, notify = false },
  change_detection = { notify = false },
  rocks = { enabled = false },
  ui = { border = "rounded", backdrop = 100, title = " lumen " },
  performance = {
    rtp = { disabled_plugins = { "gzip", "netrwPlugin", "rplugin", "tarPlugin", "tohtml", "tutor", "zipPlugin" } },
  },
})
