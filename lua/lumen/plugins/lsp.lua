return {
  {
    "neovim/nvim-lspconfig",
    event = "LazyFile",
    -- mason isn't needed to start servers (lumen.lsp puts its bin dir on PATH): it loads right
    -- after, off the file-open path, to install missing servers and tools
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
      -- already on PATH: don't let mason prepend its bin dir a second time
      if require("lumen.lsp").mason_path(opts) then
        opts.PATH = "skip"
      end
      require("mason").setup(opts)
      require("lumen.lsp").install(tools)
    end,
  },

  -- only used for its server-name → mason-package mapping
  { "mason-org/mason-lspconfig.nvim", lazy = true },
}
