---@type lumen.Pack
return {
  desc = "SQL + database UI (dadbod)",
  ft = { "sql", "mysql", "plsql" },
  parsers = { "sql" },
  plugins = {
    {
      "kristijanhusak/vim-dadbod-ui",
      cmd = { "DBUI", "DBUIToggle", "DBUIAddConnection", "DBUIFindBuffer" },
      dependencies = { { "tpope/vim-dadbod", cmd = "DB" } },
      keys = { { "<leader>D", "<cmd>DBUIToggle<cr>", desc = "Database UI" } },
      init = function()
        vim.g.db_ui_use_nerd_fonts = 1
        vim.g.db_ui_show_database_icon = true
        vim.g.db_ui_auto_execute_table_helpers = 1
        vim.g.db_ui_save_location = vim.fn.stdpath("data") .. "/dadbod_ui"
      end,
    },
    { "kristijanhusak/vim-dadbod-completion", ft = { "sql", "mysql", "plsql" } },
    {
      "saghen/blink.cmp",
      opts = {
        sources = {
          per_filetype = {
            sql = { "snippets", "dadbod", "buffer" },
            mysql = { "snippets", "dadbod", "buffer" },
          },
          providers = { dadbod = { name = "Dadbod", module = "vim_dadbod_completion.blink" } },
        },
      },
    },
  },
}
