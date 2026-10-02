-- Test adapters are picked from your other enabled packs.
local enabled = require("lumen.packs").enabled()
local by_pack = {
  python = { { "nvim-neotest/neotest-python" }, "neotest-python" },
  typescript = {
    { "nvim-neotest/neotest-jest", "marilari88/neotest-vitest" },
    "neotest-jest",
    "neotest-vitest",
  },
  go = { { "fredrikaverpil/neotest-golang" }, "neotest-golang" },
  rust = { { "rouge8/neotest-rust" }, "neotest-rust" },
}
local deps, adapters = { "nvim-neotest/nvim-nio", "nvim-lua/plenary.nvim" }, {}
for pack, spec in pairs(by_pack) do
  if enabled[pack] then
    vim.list_extend(deps, spec[1])
    vim.list_extend(adapters, vim.list_slice(spec, 2))
  end
end

---@type lumen.Pack
return {
  desc = "Testing (neotest, adapters for your enabled languages)",
  ft = {},
  plugins = {
    {
      "nvim-neotest/neotest",
      dependencies = deps,
      opts = { status = { virtual_text = true }, output = { open_on_run = true } },
      config = function(_, opts)
        opts.adapters = {}
        for _, name in ipairs(adapters) do
          local ok, adapter = pcall(require, name)
          if ok then
            opts.adapters[#opts.adapters + 1] = adapter
          end
        end
        require("neotest").setup(opts)
      end,
      -- stylua: ignore
      keys = {
        { "<leader>tt", function() require("neotest").run.run(vim.fn.expand("%")) end, desc = "Run file" },
        { "<leader>tT", function() require("neotest").run.run(vim.uv.cwd()) end, desc = "Run all files" },
        { "<leader>tr", function() require("neotest").run.run() end, desc = "Run nearest" },
        { "<leader>tl", function() require("neotest").run.run_last() end, desc = "Run last" },
        { "<leader>td", function() require("neotest").run.run({ strategy = "dap" }) end, desc = "Debug nearest" },
        { "<leader>ts", function() require("neotest").summary.toggle() end, desc = "Summary" },
        { "<leader>to", function() require("neotest").output.open({ enter = true, auto_close = true }) end, desc = "Output" },
        { "<leader>tO", function() require("neotest").output_panel.toggle() end, desc = "Output panel" },
        { "<leader>tS", function() require("neotest").run.stop() end, desc = "Stop" },
        { "<leader>tw", function() require("neotest").watch.toggle(vim.fn.expand("%")) end, desc = "Watch file" },
        { "]T", function() require("neotest").jump.next({ status = "failed" }) end, desc = "Next failed test" },
        { "[T", function() require("neotest").jump.prev({ status = "failed" }) end, desc = "Prev failed test" },
      },
    },
    { "folke/which-key.nvim", opts = { spec = { { "<leader>t", group = "test", icon = "󰙨 " } } } },
  },
}
