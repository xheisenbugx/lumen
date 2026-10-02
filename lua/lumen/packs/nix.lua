---@type lumen.Pack
return {
  desc = "Nix (nil, nixfmt)",
  ft = { "nix" },
  parsers = { "nix" },
  servers = { nil_ls = {} },
  tools = { "nixfmt" },
  formatters = { nix = { "nixfmt" } },
}
