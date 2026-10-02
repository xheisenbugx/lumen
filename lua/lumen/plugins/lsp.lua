return {
  {
    "neovim/nvim-lspconfig",
    event = "LazyFile",
    dependencies = { "mason-org/mason.nvim", "mason-org/mason-lspconfig.nvim" },
    opts = {
      ---@type table<string, table|false>
      servers = {},
    },
    config = function(_, opts)
      require("lumen.lsp").setup(opts)
    end,
  },

  {
    "mason-org/mason.nvim",
    cmd = { "Mason", "MasonInstall", "MasonUninstall", "MasonUninstallAll", "MasonUpdate", "MasonLog" },
    build = ":MasonUpdate",
    opts_extend = { "ensure_installed" },
    keys = { { "<leader>cm", "<cmd>Mason<cr>", desc = "Mason" } },
    opts = {
      ensure_installed = {},
      ui = {
        border = "rounded",
        backdrop = 100,
        width = 0.8,
        height = 0.8,
        icons = { package_installed = "✓", package_pending = "➜", package_uninstalled = "✗" },
      },
    },
    config = function(_, opts)
      local tools = opts.ensure_installed or {}
      opts.ensure_installed = nil
      require("mason").setup(opts)
      require("lumen.lsp").install(tools)
    end,
  },

  -- only used for its server-name → mason-package mapping
  { "mason-org/mason-lspconfig.nvim", lazy = true },
}
