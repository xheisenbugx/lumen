-- Vue 3: vue_ls handles templates/styles, vtsls (with the Vue TS plugin) handles <script>.
-- Builds on the typescript pack: this adds `vue` to vtsls and plugs the Vue TS plugin in.
-- `$MASON/` is Mason's install root, wherever `install_root_dir` puts it (resolved by lumen.lsp)
local vue_ts_plugin = "$MASON/packages/vue-language-server/node_modules/@vue/language-server"

---@type lumen.Pack
return {
  desc = "Vue (vue_ls + vtsls hybrid mode)",
  ft = { "vue" },
  requires = { "node", "npm" },
  extends = { "typescript" },
  parsers = { "vue", "css" },
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
  plugins = { { "windwp/nvim-ts-autotag", ft = require("lumen.packs").autotag_ft, opts = {} } },
}
