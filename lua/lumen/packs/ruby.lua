---@type lumen.Pack
return {
  desc = "Ruby (ruby-lsp, rubocop)",
  ft = { "ruby", "eruby" },
  parsers = { "ruby" },
  servers = { ruby_lsp = { init_options = { formatter = "auto", linters = { "rubocop" } } } },
}
