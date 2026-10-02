---@type lumen.Pack
return {
  desc = "GitHub issues & PRs in Neovim (octo)",
  ft = {},
  plugins = {
    {
      "pwntester/octo.nvim",
      cmd = "Octo",
      opts = { picker = "snacks", enable_builtin = true, use_local_fs = true },
      keys = {
        { "<leader>gi", "<cmd>Octo issue list<cr>", desc = "Issues (Octo)" },
        { "<leader>gp", "<cmd>Octo pr list<cr>", desc = "Pull requests (Octo)" },
        { "<leader>gr", "<cmd>Octo review<cr>", desc = "Review (Octo)" },
      },
    },
  },
}
