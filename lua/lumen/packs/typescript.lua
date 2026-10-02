-- biome when the project uses it, prettier otherwise
local function js_format(buf)
  if vim.fs.root(buf, { "biome.json", "biome.jsonc" }) then
    return { "biome-check" }
  end
  return { "prettierd", "prettier", stop_after_first = true }
end

local inlay = {
  enumMemberValues = { enabled = true },
  functionLikeReturnTypes = { enabled = true },
  parameterNames = { enabled = "literals" },
  parameterTypes = { enabled = true },
  propertyDeclarationTypes = { enabled = true },
  variableTypes = { enabled = false },
}

---@type lumen.Pack
return {
  desc = "TypeScript / JavaScript (vtsls, eslint, biome|prettier)",
  ft = { "typescript", "typescriptreact", "javascript", "javascriptreact" },
  parsers = { "javascript", "typescript", "tsx", "jsdoc" },
  servers = {
    vtsls = {
      settings = {
        complete_function_calls = true,
        vtsls = {
          enableMoveToFileCodeAction = true,
          autoUseWorkspaceTsdk = true,
          experimental = { completion = { enableServerSideFuzzyMatch = true } },
        },
        typescript = {
          updateImportsOnFileMove = { enabled = "always" },
          suggest = { completeFunctionCalls = true },
          inlayHints = inlay,
        },
        javascript = { updateImportsOnFileMove = { enabled = "always" }, inlayHints = inlay },
      },
      keys = {
        {
          "<leader>co",
          function()
            vim.lsp.buf.code_action({
              apply = true,
              context = { only = { "source.organizeImports" }, diagnostics = {} },
            })
          end,
          desc = "Organize imports",
        },
        {
          "<leader>cM",
          function()
            vim.lsp.buf.code_action({
              apply = true,
              context = { only = { "source.addMissingImports.ts" }, diagnostics = {} },
            })
          end,
          desc = "Add missing imports",
        },
      },
    },
    eslint = {},
    biome = { mason = false },
  },
  tools = { "prettierd" },
  formatters = {
    javascript = js_format,
    javascriptreact = js_format,
    typescript = js_format,
    typescriptreact = js_format,
  },
  plugins = {
    {
      "windwp/nvim-ts-autotag",
      event = "LazyFile",
      opts = {
        -- plain .ts has no JSX, yet autotag would reparse the whole buffer (with injections) on
        -- every InsertLeave and on every `>` typed: ~30ms each on a 40k-line file
        per_filetype = {
          typescript = { enable_close = false, enable_rename = false, enable_close_on_slash = false },
        },
      },
    },
  },
}
