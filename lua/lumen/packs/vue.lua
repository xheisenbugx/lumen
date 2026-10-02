-- Vue 3: vue_ls handles templates/styles, vtsls (with the Vue TS plugin) handles <script>.
local vue_ts_plugin = vim.fn.stdpath("data") .. "/mason/packages/vue-language-server/node_modules/@vue/language-server"

---@type lumen.Pack
return {
  desc = "Vue (vue_ls + vtsls hybrid mode)",
  ft = { "vue" },
  parsers = { "vue", "typescript", "javascript", "css" },
  servers = {
    vue_ls = {},
    vtsls = {
      filetypes = { "javascript", "javascriptreact", "typescript", "typescriptreact", "vue" },
      settings = {
        vtsls = {
          tsserver = {
            globalPlugins = {
              {
                name = "@vue/typescript-plugin",
                location = vue_ts_plugin,
                languages = { "vue" },
                configNamespace = "typescript",
                enableForWorkspaceTypeScriptVersions = true,
              },
            },
          },
        },
      },
    },
  },
  tools = { "prettierd" },
  formatters = { vue = { "prettierd", "prettier", stop_after_first = true } },
  plugins = { { "windwp/nvim-ts-autotag", event = "LazyFile", opts = {} } },
}
