---@type lumen.Pack
return {
  desc = "AI: Copilot suggestions + sidekick (CLI agents & next-edit)",
  ft = {},
  servers = { copilot = {} },
  -- Copilot's ghost-text suggestions use Neovim's inline completion (0.12+), which is off by
  -- default. (Not via the server's on_attach: that would replace lspconfig's, with its sign-in commands.)
  setup = function()
    vim.api.nvim_create_autocmd("LspAttach", {
      group = vim.api.nvim_create_augroup("lumen_ai_inline", { clear = true }),
      callback = function(ev)
        local client = vim.lsp.get_client_by_id(ev.data.client_id)
        if client and client.name == "copilot" and vim.lsp.inline_completion then
          vim.lsp.inline_completion.enable(true, { bufnr = ev.buf })
        end
      end,
    })
  end,
  plugins = {
    -- <Tab> accepts a Copilot suggestion (after snippet jumps, before a plain tab)
    {
      "saghen/blink.cmp",
      opts = {
        keymap = {
          ["<Tab>"] = {
            "snippet_forward",
            function()
              return vim.lsp.inline_completion and vim.lsp.inline_completion.get()
            end,
            "fallback",
          },
        },
      },
    },
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
