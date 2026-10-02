-- Extra colorschemes. All are lazy: they cost nothing at startup, show up in
-- <leader>uC (with live preview), and load the moment you select one or set
-- `colorscheme = "catppuccin"` in lua/config/lumen.lua.
return {
  {
    "catppuccin/nvim",
    name = "catppuccin",
    lazy = true,
    priority = 1000,
    opts = {
      -- "catppuccin" follows 'background': latte when light, mocha when dark.
      -- Pick a flavour directly with catppuccin-latte / -frappe / -macchiato / -mocha.
      flavour = "auto",
      background = { light = "latte", dark = "mocha" },
      transparent_background = require("lumen.config").transparent,
      float = { transparent = false, solid = false },
      term_colors = true,
      -- detect installed plugins (blink, snacks, which-key, gitsigns, flash, mini, …)
      auto_integrations = true,
      integrations = {
        blink_cmp = { style = "bordered" },
        snacks = { enabled = true, indent_scope_color = "lavender" },
        mini = { enabled = true },
        native_lsp = {
          enabled = true,
          underlines = {
            errors = { "undercurl" },
            hints = { "undercurl" },
            warnings = { "undercurl" },
            information = { "undercurl" },
          },
        },
      },
    },
  },
}
