---@type lumen.Pack
return {
  desc = "Swift (sourcekit-lsp from Xcode / toolchain)",
  ft = { "swift" },
  parsers = { "swift" },
  servers = { sourcekit = { mason = false } },
  tools = { "swiftformat" },
  formatters = { swift = { "swiftformat" } },
}
