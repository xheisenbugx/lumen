---@type lumen.Pack
return {
  desc = "Elixir (elixir-ls, mix format)",
  ft = { "elixir", "heex", "eelixir" },
  requires = { "elixir" },
  parsers = { "elixir", "heex", "eex" },
  servers = { elixirls = { settings = { elixirLS = { dialyzerEnabled = true, fetchDeps = false } } } },
  formatters = { elixir = { "mix" }, heex = { "mix" } },
}
