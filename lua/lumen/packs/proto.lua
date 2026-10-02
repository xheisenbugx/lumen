---@type lumen.Pack
return {
  desc = "Protocol Buffers (buf)",
  ft = { "proto" },
  parsers = { "proto" },
  servers = { buf_ls = {} },
  formatters = { proto = { "buf" } },
}
