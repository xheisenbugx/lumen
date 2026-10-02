-- Lumen settings. Every key is optional — delete what you don't change.
-- All options and defaults: lua/lumen/config.lua in the Lumen repo.
return {
  -- "lumen" (follows 'background'), "lumen-night", "lumen-dawn",
  -- "catppuccin" (latte/mocha by 'background'), "catppuccin-latte|frappe|macchiato|mocha",
  -- or any installed scheme. Browse them live with <leader>uC.
  colorscheme = "lumen",
  transparent = false,
  italics = true,
  -- focus glow: amber orange red rose violet blue sky cyan teal green yellow, or "#rrggbb"
  accent = "amber",
  -- colors = { night = { bg = "#0b0d12" } },               -- palette overrides
  -- on_highlights = function(hl, p) hl.Comment = { fg = p.teal, italic = true } end,

  -- language packs — browse them all with :Lumen packs (that picker remembers its own choices)
  packs = { "lua", "json", "yaml", "toml", "markdown", "bash" },

  format_on_save = true,
  -- :Lumen update → "stable": plugin versions CI tested together with Lumen · "latest": newest
  update_channel = "stable",
  winbar = true, -- breadcrumbs per window
  scrollbar = true, -- right-edge bar with diagnostic / git / search marks
  diagnostics = "text", -- "text" | "lines" | "signs"  (cycle live with <leader>uv)
  inlay_hints = true,
  smooth_scroll = true,
  tmux_navigation = true,

  -- extra tasks for <leader>rt next to the auto-discovered ones
  -- tasks = { { name = "deploy", cmd = "./scripts/deploy.sh" } },
}
