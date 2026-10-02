---@type lumen.Pack
return {
  desc = "C# / F# (omnisharp, fsautocomplete, csharpier, fantomas, netcoredbg)",
  ft = { "cs", "fsharp" },
  parsers = { "c_sharp", "fsharp" },
  servers = {
    omnisharp = {
      settings = {
        FormattingOptions = { OrganizeImports = true },
        RoslynExtensionsOptions = { EnableAnalyzersSupport = true, EnableImportCompletion = true },
      },
    },
    fsautocomplete = {},
  },
  tools = { "csharpier", "fantomas", "netcoredbg" },
  formatters = { cs = { "csharpier" }, fsharp = { "fantomas" } },
}
