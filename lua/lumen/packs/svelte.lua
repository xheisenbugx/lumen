---@type lumen.Pack
return {
  desc = "Svelte",
  ft = { "svelte" },
  parsers = { "svelte", "typescript", "css" },
  servers = { svelte = {} },
  tools = { "prettierd" },
  formatters = { svelte = { "prettierd", "prettier", stop_after_first = true } },
  plugins = { { "windwp/nvim-ts-autotag", event = "LazyFile", opts = {} } },
}
