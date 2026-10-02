---@type lumen.Pack
return {
  desc = "OCaml (ocaml-lsp, ocamlformat)",
  ft = { "ocaml", "dune" },
  parsers = { "ocaml", "ocaml_interface" },
  servers = { ocamllsp = {} },
  formatters = { ocaml = { "ocamlformat" } },
}
