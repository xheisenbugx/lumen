---@type lumen.Pack
return {
  desc = "LaTeX (texlab, latexindent)",
  ft = { "tex", "plaintex", "bib" },
  parsers = { "latex", "bibtex" },
  servers = {
    texlab = {
      settings = {
        texlab = { build = { onSave = true }, chktex = { onEdit = false, onOpenAndSave = true } },
      },
    },
  },
  formatters = { tex = { "latexindent" } },
}
