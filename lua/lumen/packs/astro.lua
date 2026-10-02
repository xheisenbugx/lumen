---@type lumen.Pack
return {
  desc = "Astro",
  ft = { "astro" },
  parsers = { "astro", "typescript", "css" },
  servers = { astro = {} },
  tools = { "prettierd" },
  formatters = { astro = { "prettierd", "prettier", stop_after_first = true } },
  plugins = { { "windwp/nvim-ts-autotag", ft = require("lumen.packs").autotag_ft, opts = {} } },
}
