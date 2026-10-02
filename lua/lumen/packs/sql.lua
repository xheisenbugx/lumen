---@type lumen.Pack
return {
  desc = "SQL + database client (sqmeow: schema browser, queries, editable results)",
  ft = { "sql", "mysql", "plsql" },
  parsers = { "sql" },
  plugins = {
    {
      "2giosangmitom/sqmeow.nvim",
      dependencies = { "MunifTanjim/nui.nvim" },
      version = "*",
      -- downloads the engine binary matching the release
      build = function()
        require("sqmeow").install()
      end,
      cmd = "Sqmeow",
      opts = {},
      keys = {
        { "<leader>Dd", "<cmd>Sqmeow toggle<cr>", desc = "Toggle drawer" },
        { "<leader>Do", "<cmd>Sqmeow<cr>", desc = "Open drawer + results" },
        { "<leader>Da", "<cmd>Sqmeow add<cr>", desc = "Add connection" },
        { "<leader>Du", "<cmd>Sqmeow use<cr>", desc = "Use connection" },
        { "<leader>Ds", "<cmd>Sqmeow scratch<cr>", desc = "New scratchpad" },
        { "<leader>Dc", "<cmd>Sqmeow cancel<cr>", desc = "Cancel query" },
        { "<leader>Dl", "<cmd>Sqmeow log<cr>", desc = "Query history" },
      },
    },
    { "folke/which-key.nvim", opts = { spec = { { "<leader>D", group = "database", icon = "󰆼 " } } } },
  },
}
