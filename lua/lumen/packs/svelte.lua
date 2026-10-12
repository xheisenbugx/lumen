---@type lumen.Pack
return {
  desc = "Svelte",
  ft = { "svelte" },
  requires = { "node", "npm" },
  parsers = { "svelte", "typescript", "css" },
  servers = { svelte = {} },
  tools = { "prettierd" },
  formatters = { svelte = { "prettierd", "prettier", stop_after_first = true } },
  plugins = { { "windwp/nvim-ts-autotag", ft = require("lumen.packs").autotag_ft, opts = {} } },
}
