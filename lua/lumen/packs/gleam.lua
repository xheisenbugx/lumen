---@type lumen.Pack
return {
  desc = "Gleam (built-in language server)",
  ft = { "gleam" },
  parsers = { "gleam" },
  servers = { gleam = { mason = false } },
  formatters = { gleam = { "gleam" } },
}
