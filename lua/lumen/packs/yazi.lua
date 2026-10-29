---@type lumen.Pack
return {
  desc = "Yazi terminal file manager in a float (replaces the explorer on <leader>e)",
  ft = {},
  plugins = {
    {
      "mikavilpas/yazi.nvim",
      cmd = "Yazi",
      -- the Snacks explorer is off with this pack (plugins/ui.lua), so yazi opens directories
      -- (`nvim .`, `:e dir/`): load it when one is entered, its setup then takes the current buffer
      init = function()
        vim.api.nvim_create_autocmd("BufEnter", {
          group = vim.api.nvim_create_augroup("lumen_yazi_dir", { clear = true }),
          callback = function(ev)
            if ev.file ~= "" and vim.fn.isdirectory(ev.file) == 1 then
              require("yazi")
              return true
            end
          end,
        })
      end,
      opts = {
        open_for_directories = true,
        floating_window_scaling_factor = 0.88,
        yazi_floating_window_border = "rounded",
      },
      -- stylua: ignore
      keys = {
        { "<leader>e", function() require("yazi").yazi(nil, Lumen.root()) end, desc = "Yazi (root)" },
        { "<leader>E", "<cmd>Yazi cwd<cr>", desc = "Yazi (cwd)" },
        { "<leader>y", "<cmd>Yazi<cr>", desc = "Yazi (current file)" },
      },
    },
  },
}
