---@type lumen.Pack
return {
  desc = "Go (gopls, goimports, gofumpt)",
  ft = { "go", "gomod", "gowork" },
  parsers = { "go", "gomod", "gowork", "gosum" },
  servers = {
    gopls = {
      settings = {
        gopls = {
          gofumpt = true,
          usePlaceholders = true,
          completeUnimported = true,
          staticcheck = true,
          semanticTokens = true,
          analyses = { nilness = true, unusedparams = true, unusedwrite = true, useany = true },
          hints = {
            assignVariableTypes = true,
            compositeLiteralFields = true,
            constantValues = true,
            functionTypeParameters = true,
            parameterNames = true,
            rangeVariableTypes = true,
          },
        },
      },
    },
  },
  tools = { "goimports", "gofumpt" },
  formatters = { go = { "goimports", "gofumpt" } },
}
