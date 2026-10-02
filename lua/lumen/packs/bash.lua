---@type lumen.Pack
return {
  desc = "Shell scripts (bashls, shellcheck, shfmt)",
  ft = { "sh", "bash", "zsh" },
  parsers = { "bash" },
  servers = { bashls = {} },
  tools = { "shellcheck", "shfmt" },
  formatters = { sh = { "shfmt" }, bash = { "shfmt" } },
}
