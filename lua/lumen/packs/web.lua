local prettier = { "prettierd", "prettier", stop_after_first = true }

---@type lumen.Pack
return {
  desc = "HTML, CSS, SCSS, Tailwind",
  ft = { "html", "css", "scss", "less" },
  parsers = { "html", "css", "scss" },
  servers = {
    html = {},
    cssls = {},
    tailwindcss = {},
  },
  tools = { "prettierd" },
  formatters = { html = prettier, css = prettier, scss = prettier, less = prettier },
  plugins = {
    { "windwp/nvim-ts-autotag", event = "LazyFile", opts = {} },
  },
}
