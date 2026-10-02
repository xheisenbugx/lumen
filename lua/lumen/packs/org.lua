-- Emacs Org mode in pure Lua: outlines, TODOs, agenda, capture, clocking, tables, Babel, export.
-- Notes live in ~/org. To move them, override all three paths from a file in your lua/plugins/:
--   { "xheisenbugx/org.nvim", opts = { org_directory = "~/notes",
--     agenda_files = { "~/notes/**/*.org" }, default_notes_file = "~/notes/refile.org" } }
---@type lumen.Pack
return {
  desc = "Org mode (org.nvim: agenda, capture, clocking, tables, Babel, export)",
  ft = { "org" },
  plugins = {
    {
      "xheisenbugx/org.nvim",
      main = "org",
      -- right after the UI appears, so the global <leader>o keys (agenda, capture) are ready
      -- without costing startup time; opening an .org file or :Org loads it immediately
      event = "VeryLazy",
      ft = "org",
      cmd = "Org",
      opts = {
        org_directory = "~/org",
        agenda_files = { "~/org/**/*.org" },
        default_notes_file = "~/org/refile.org",
      },
    },
    {
      "saghen/blink.cmp",
      opts = {
        sources = {
          per_filetype = { org = { inherit_defaults = true, "org" } },
          providers = { org = { name = "Org", module = "org.completion.blink" } },
        },
      },
    },
  },
}
