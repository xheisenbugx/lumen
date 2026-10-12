---@type lumen.Pack
return {
  desc = "Dart / Flutter (dartls from the Dart SDK)",
  ft = { "dart" },
  requires = { "dart" },
  parsers = { "dart" },
  servers = { dartls = { mason = false } },
  formatters = { dart = { "dart_format" } },
}
