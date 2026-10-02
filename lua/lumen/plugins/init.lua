-- First module lazy.nvim imports from `lumen.plugins` (modules load in name order),
-- so this runs before any other spec: settings, options and the LazyFile event.
if vim.fn.has("nvim-0.11") == 0 then
  vim.api.nvim_echo({
    { "Lumen requires Neovim >= 0.11 (0.12+ recommended)\n", "ErrorMsg" },
    { "Press any key to exit", "MoreMsg" },
  }, true, {})
  vim.fn.getchar()
  vim.cmd.quit()
  return {}
end

require("lumen").init()

return {
  { "folke/lazy.nvim", version = false },
  {
    -- extends *your* spec for Lumen, which must be named "lumen" (see the starter's init.lua)
    "lumen",
    lazy = false,
    -- after snacks.nvim (1000), before everything else
    priority = 900,
    opts = {},
    config = function(_, opts)
      require("lumen").setup(opts)
    end,
  },
}
