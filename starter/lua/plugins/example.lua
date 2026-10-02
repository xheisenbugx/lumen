-- Every file in lua/plugins/ is a lazy.nvim spec: add plugins or override Lumen's.
return {
  -- add a plugin
  -- { "christoomey/vim-tmux-navigator", lazy = false },

  -- change Lumen settings (same keys as lua/config/lumen.lua, except packs)
  -- { "lumen", opts = { accent = "violet" } },

  -- tweak a built-in plugin (opts are deep-merged with Lumen's)
  -- { "folke/snacks.nvim", opts = { scroll = { enabled = false } } },

  -- disable one entirely
  -- { "stevearc/oil.nvim", enabled = false },
}
