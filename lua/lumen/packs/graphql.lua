---@type lumen.Pack
return {
  desc = "GraphQL",
  ft = { "graphql" },
  requires = { "node", "npm" },
  parsers = { "graphql" },
  servers = { graphql = {} },
  formatters = { graphql = { "prettierd", "prettier", stop_after_first = true } },
}
