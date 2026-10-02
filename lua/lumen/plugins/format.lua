return {
  {
    "stevearc/conform.nvim",
    event = "BufWritePre",
    cmd = "ConformInfo",
    keys = {
      {
        "<leader>cf",
        function()
          require("conform").format({ async = true })
        end,
        mode = { "n", "x" },
        desc = "Format",
      },
    },
    init = function()
      vim.o.formatexpr = "v:lua.require'conform'.formatexpr()"
    end,
    opts = {
      default_format_opts = { lsp_format = "fallback", timeout_ms = 3000 },
      formatters_by_ft = {},
      format_on_save = function(buf)
        local enabled = vim.b[buf].lumen_autoformat
        if enabled == nil then
          enabled = vim.g.lumen_autoformat
        end
        if enabled == false then
          return
        end
        return {}
      end,
    },
  },

  {
    "mfussenegger/nvim-lint",
    event = "LazyFile",
    opts = { linters_by_ft = {} },
    config = function(_, opts)
      require("lumen.diagnostics").setup()
      local lint = require("lint")
      lint.linters_by_ft = opts.linters_by_ft

      local timer = assert(vim.uv.new_timer())
      local function run()
        local names = lint._resolve_linter_by_ft(vim.bo.filetype)
        names = vim.tbl_filter(function(name)
          local linter = lint.linters[name]
          local cmd = linter and (type(linter) == "function" and linter().cmd or linter.cmd)
          return cmd ~= nil and vim.fn.executable(type(cmd) == "function" and cmd() or cmd) == 1
        end, names)
        if #names > 0 then
          lint.try_lint(names)
        end
      end

      vim.api.nvim_create_autocmd({ "BufWritePost", "BufReadPost", "InsertLeave" }, {
        group = vim.api.nvim_create_augroup("lumen_lint", { clear = true }),
        callback = function()
          timer:stop()
          timer:start(100, 0, vim.schedule_wrap(run))
        end,
      })
    end,
  },
}
