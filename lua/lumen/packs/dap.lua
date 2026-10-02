-- Debug adapters are picked from your other enabled packs.
local enabled = require("lumen.packs").enabled()
local adapters = {}
for pack, adapter in pairs({
  python = "python",
  typescript = "js",
  go = "delve",
  rust = "codelldb",
  cpp = "codelldb",
  zig = "codelldb",
  dotnet = "coreclr",
  php = "php",
  dart = "dart",
  elixir = "elixir",
}) do
  if enabled[pack] and not vim.tbl_contains(adapters, adapter) then
    adapters[#adapters + 1] = adapter
  end
end

---@type lumen.Pack
return {
  desc = "Debugging (nvim-dap + UI, adapters for your enabled languages)",
  ft = {},
  plugins = {
    {
      "mfussenegger/nvim-dap",
      dependencies = {
        {
          "rcarriga/nvim-dap-ui",
          dependencies = { "nvim-neotest/nvim-nio" },
          opts = { floating = { border = "rounded" } },
          config = function(_, opts)
            local dap, dapui = require("dap"), require("dapui")
            dapui.setup(opts)
            dap.listeners.after.event_initialized.lumen = function()
              dapui.open({})
            end
            dap.listeners.before.event_terminated.lumen = function()
              dapui.close({})
            end
            dap.listeners.before.event_exited.lumen = function()
              dapui.close({})
            end
          end,
        },
        { "theHamsta/nvim-dap-virtual-text", opts = { virt_text_pos = "eol" } },
        {
          "jay-babu/mason-nvim-dap.nvim",
          dependencies = "mason-org/mason.nvim",
          cmd = { "DapInstall", "DapUninstall" },
          opts = { automatic_installation = true, ensure_installed = adapters, handlers = {} },
        },
      },
      config = function()
        local signs = {
          DapBreakpoint = { "●", "DiagnosticError" },
          DapBreakpointCondition = { "◆", "DiagnosticWarn" },
          DapBreakpointRejected = { "○", "DiagnosticHint" },
          DapLogPoint = { "◉", "DiagnosticInfo" },
          DapStopped = { "▶", "DiagnosticOk", "Visual" },
        }
        for name, s in pairs(signs) do
          vim.fn.sign_define(name, { text = s[1], texthl = s[2], linehl = s[3], numhl = s[3] })
        end
      end,
      -- stylua: ignore
      keys = {
        { "<F5>", function() require("dap").continue() end, desc = "Debug: continue" },
        { "<F10>", function() require("dap").step_over() end, desc = "Debug: step over" },
        { "<F11>", function() require("dap").step_into() end, desc = "Debug: step into" },
        { "<S-F11>", function() require("dap").step_out() end, desc = "Debug: step out" },
        { "<leader>db", function() require("dap").toggle_breakpoint() end, desc = "Toggle breakpoint" },
        { "<leader>dB", function() require("dap").set_breakpoint(vim.fn.input("Condition: ")) end, desc = "Conditional breakpoint" },
        { "<leader>dL", function() require("dap").set_breakpoint(nil, nil, vim.fn.input("Log: ")) end, desc = "Log point" },
        { "<leader>dc", function() require("dap").continue() end, desc = "Run / continue" },
        { "<leader>dC", function() require("dap").run_to_cursor() end, desc = "Run to cursor" },
        { "<leader>di", function() require("dap").step_into() end, desc = "Step into" },
        { "<leader>do", function() require("dap").step_out() end, desc = "Step out" },
        { "<leader>dO", function() require("dap").step_over() end, desc = "Step over" },
        { "<leader>dj", function() require("dap").down() end, desc = "Down the stack" },
        { "<leader>dk", function() require("dap").up() end, desc = "Up the stack" },
        { "<leader>dl", function() require("dap").run_last() end, desc = "Run last" },
        { "<leader>dp", function() require("dap").pause() end, desc = "Pause" },
        { "<leader>dr", function() require("dap").repl.toggle() end, desc = "REPL" },
        { "<leader>dt", function() require("dap").terminate() end, desc = "Terminate" },
        { "<leader>du", function() require("dapui").toggle({}) end, desc = "Debug UI" },
        { "<leader>de", function() require("dapui").eval() end, desc = "Eval", mode = { "n", "x" } },
        { "<leader>dw", function() require("dap.ui.widgets").hover() end, desc = "Hover value" },
      },
    },
  },
}
