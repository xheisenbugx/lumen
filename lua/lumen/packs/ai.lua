---@type lumen.Pack
return {
  desc = "AI: Copilot suggestions + sidekick (CLI agents & next-edit)",
  ft = {},
  servers = { copilot = {} },
  plugins = {
    {
      "folke/sidekick.nvim",
      event = "LazyFile",
      opts = { cli = { mux = { enabled = vim.env.TMUX ~= nil, backend = "tmux" } } },
      -- stylua: ignore
      keys = {
        { "<tab>", function() if not require("sidekick").nes_jump_or_apply() then return "<Tab>" end end, expr = true, desc = "Next edit suggestion" },
        { "<c-.>", function() require("sidekick.cli").toggle() end, mode = { "n", "t", "i", "x" }, desc = "Sidekick toggle" },
        { "<leader>aa", function() require("sidekick.cli").toggle() end, desc = "Sidekick CLI" },
        { "<leader>as", function() require("sidekick.cli").select() end, desc = "Select CLI" },
        { "<leader>at", function() require("sidekick.cli").send({ msg = "{this}" }) end, mode = { "x", "n" }, desc = "Send this" },
        { "<leader>av", function() require("sidekick.cli").send({ msg = "{selection}" }) end, mode = { "x" }, desc = "Send selection" },
        { "<leader>ap", function() require("sidekick.cli").prompt() end, mode = { "n", "x" }, desc = "Prompt" },
      },
    },
    { "folke/which-key.nvim", opts = { spec = { { "<leader>a", group = "ai", icon = "󰚩 " } } } },
  },
}
