---@type lumen.Pack
return {
  desc = "Typst (tinymist, typstyle)",
  ft = { "typst" },
  parsers = { "typst" },
  servers = { tinymist = { settings = { formatterMode = "typstyle", exportPdf = "onType" } } },
}
