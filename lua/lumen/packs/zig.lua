---@type lumen.Pack
return {
  desc = "Zig (zls)",
  ft = { "zig", "zon" },
  requires = { "zig" },
  parsers = { "zig" },
  servers = { zls = { settings = { zls = { enable_build_on_save = true, semantic_tokens = "partial" } } } },
  formatters = { zig = { "zigfmt" } },
}
