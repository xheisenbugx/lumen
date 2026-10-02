---@type lumen.Pack
return {
  desc = "Python (basedpyright, ruff)",
  ft = { "python" },
  parsers = { "python", "rst", "ninja" },
  servers = {
    basedpyright = {
      settings = {
        basedpyright = { analysis = { typeCheckingMode = "standard", autoImportCompletions = true } },
      },
    },
    ruff = {
      -- let basedpyright own hover
      on_attach = function(client)
        client.server_capabilities.hoverProvider = false
      end,
    },
  },
  formatters = { python = { "ruff_organize_imports", "ruff_format" } },
}
