---@type lumen.Pack
return {
  desc = "Astro",
  ft = { "astro" },
  requires = { "node", "npm" },
  extends = { "typescript" },
  parsers = { "astro", "css" },
  servers = { astro = {} },
  tools = { "prettierd" },
  formatters = { astro = { "prettierd", "prettier", stop_after_first = true } },
  plugins = { { "windwp/nvim-ts-autotag", ft = require("lumen.packs").autotag_ft, opts = {} } },
}
