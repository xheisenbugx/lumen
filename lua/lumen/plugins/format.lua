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

      -- runnable linters per filetype: resolving them calls function linters and probes PATH,
      -- too much for every InsertLeave. Reset when a tool gets installed or packs change.
      local runnable = {} ---@type table<string, string[]>
      local function resolve(ft)
        if not runnable[ft] then
          runnable[ft] = vim.tbl_filter(function(name)
            local linter = lint.linters[name]
            local ok, cmd = pcall(function()
              local l = type(linter) == "function" and linter() or linter
              local c = l and l.cmd
              return type(c) == "function" and c() or c
            end)
            return ok and type(cmd) == "string" and vim.fn.executable(cmd) == 1
          end, lint._resolve_linter_by_ft(ft))
        end
        return runnable[ft]
      end

      local timer = assert(vim.uv.new_timer())
      local function run()
        local names = resolve(vim.bo.filetype)
        if #names > 0 then
          lint.try_lint(names)
        end
      end

      local group = vim.api.nvim_create_augroup("lumen_lint", { clear = true })
      vim.api.nvim_create_autocmd({ "BufWritePost", "BufReadPost", "InsertLeave" }, {
        group = group,
        callback = function()
          timer:stop()
          timer:start(100, 0, vim.schedule_wrap(run))
        end,
      })
      vim.api.nvim_create_autocmd("User", {
        group = group,
        pattern = { "LumenToolInstalled", "LumenPacksChanged" },
        callback = function()
          runnable = {}
        end,
      })
    end,
  },
}
