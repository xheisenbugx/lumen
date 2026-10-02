---@type lumen.Pack
return {
  desc = "Clojure (clojure-lsp)",
  ft = { "clojure", "edn" },
  parsers = { "clojure" },
  servers = { clojure_lsp = {} },
}
