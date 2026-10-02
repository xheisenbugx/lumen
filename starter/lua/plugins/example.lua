-- Every file in lua/plugins/ is a lazy.nvim spec: add plugins or override Lumen's.
return {
  -- add a plugin
  -- { "tpope/vim-fugitive", cmd = "Git" },

  -- change Lumen settings (same keys as lua/config/lumen.lua, except packs, leader, localleader,
  -- format_on_save, ui2 and smooth_scroll, which are read before opts exist)
  -- { "lumen", opts = { accent = "violet" } },

  -- tweak a built-in plugin (opts are deep-merged with Lumen's)
  -- { "folke/snacks.nvim", opts = { scroll = { enabled = false } } },

  -- disable one entirely
  -- { "stevearc/oil.nvim", enabled = false },
}
