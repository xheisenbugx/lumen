---@type lumen.Pack
return {
  desc = "Kotlin (kotlin-lsp, ktlint)",
  ft = { "kotlin" },
  parsers = { "kotlin" },
  servers = { kotlin_lsp = {} },
  tools = { "ktlint" },
  formatters = { kotlin = { "ktlint" } },
}
