---@type lumen.Pack
return {
  desc = "Yazi terminal file manager in a float",
  ft = {},
  plugins = {
    {
      "mikavilpas/yazi.nvim",
      cmd = "Yazi",
      opts = {
        open_for_directories = false,
        floating_window_scaling_factor = 0.88,
        yazi_floating_window_border = "rounded",
      },
      keys = {
        { "<leader>y", "<cmd>Yazi<cr>", desc = "Yazi (current file)" },
        { "<leader>Y", "<cmd>Yazi cwd<cr>", desc = "Yazi (cwd)" },
      },
    },
  },
}
