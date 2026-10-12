---@type lumen.Pack
return {
  desc = "Kotlin (kotlin-lsp, ktlint)",
  ft = { "kotlin" },
  requires = { "java" },
  parsers = { "kotlin" },
  servers = { kotlin_lsp = {} },
  tools = { "ktlint" },
  formatters = { kotlin = { "ktlint" } },
}
