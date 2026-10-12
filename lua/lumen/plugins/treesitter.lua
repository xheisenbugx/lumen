local config = require("lumen.config")
local ts = require("lumen.treesitter")

-- languages whose on-demand install was already tried this session (no retry on every FileType)
local tried = {}

return {
  {
    "nvim-treesitter/nvim-treesitter",
    branch = "main",
    commit = vim.fn.has("nvim-0.12") == 0 and "7caec274fd19c12b55902a5b795100d21531391f" or nil,
    build = function()
      local nts = require("nvim-treesitter")
      -- on a fresh install there is nothing to update yet (it would only print "All parsers are
      -- up-to-date" right before the first parsers get installed)
      if nts.update and nts.get_installed and #nts.get_installed() > 0 then
        nts.update(nil, { summary = true })
      end
    end,
    lazy = vim.fn.argc(-1) == 0, -- load early when opening a file from the cmdline
    event = { "LazyFile", "VeryLazy" },
    cmd = { "TSUpdate", "TSInstall", "TSLog", "TSUninstall" },
    opts_extend = { "ensure_installed" },
    opts = {
      ensure_installed = {
        "bash",
        "c",
        "diff",
        "html",
        "lua",
        "luadoc",
        "markdown",
        "markdown_inline",
        "printf",
        "query",
        "regex",
        "vim",
        "vimdoc",
        "gitcommit",
        "git_config",
        "git_rebase",
        "gitignore",
        "gitattributes",
      },
    },
    config = function(_, opts)
      local nts = require("nvim-treesitter")
      if not nts.get_installed then
        return Lumen.error("nvim-treesitter is outdated — run `:Lazy sync`")
      end
      nts.setup(opts)
      ts.refresh()
      ts.hush()
      ts.ensure(opts.ensure_installed or {})

      local parsers = require("nvim-treesitter.parsers")
      vim.api.nvim_create_autocmd("FileType", {
        group = vim.api.nvim_create_augroup("lumen_treesitter", { clear = true }),
        callback = function(ev)
          if ts.attach(ev.buf) ~= false then
            return
          end
          -- no parser yet: fetch it in the background, then light the buffer up
          local lang = vim.treesitter.language.get_lang(ev.match)
          if
            config.auto_install_parsers
            and lang
            and parsers[lang]
            and not ts.installed[lang]
            and not tried[lang]
            and not ts.is_pending(lang)
            and vim.fn.executable("tree-sitter") == 1
            and not require("lumen.lsp").selftest()
          then
            tried[lang] = true
            ts.install({ lang }, function()
              for _, b in ipairs(vim.api.nvim_list_bufs()) do
                if vim.api.nvim_buf_is_loaded(b) and vim.treesitter.language.get_lang(vim.bo[b].filetype) == lang then
                  ts.attach(b)
                end
              end
            end)
          end
        end,
      })

      -- buffers opened before treesitter loaded
      for _, b in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_loaded(b) and vim.bo[b].filetype ~= "" then
          ts.attach(b)
        end
      end
    end,
  },

  {
    "nvim-treesitter/nvim-treesitter-textobjects",
    branch = "main",
    event = "VeryLazy",
    opts = { move = { set_jumps = true }, select = { lookahead = true } },
    config = function(_, opts)
      require("nvim-treesitter-textobjects").setup(opts)
      local moves = {
        goto_next_start = { ["]f"] = "@function.outer", ["]c"] = "@class.outer", ["]a"] = "@parameter.inner" },
        goto_next_end = { ["]F"] = "@function.outer", ["]C"] = "@class.outer", ["]A"] = "@parameter.inner" },
        goto_previous_start = { ["[f"] = "@function.outer", ["[c"] = "@class.outer", ["[a"] = "@parameter.inner" },
        goto_previous_end = { ["[F"] = "@function.outer", ["[C"] = "@class.outer", ["[A"] = "@parameter.inner" },
      }
      local names = { f = "function", c = "class", a = "parameter" }
      -- Neovim 0.13+ uses ]C / [C to jump between multicursors: leave them to Neovim there
      local reserved = vim.api.nvim_mcursor and { ["]C"] = true, ["[C"] = true } or {}
      for method, keys in pairs(moves) do
        for key, query in pairs(keys) do
          if reserved[key] then
            goto continue
          end
          local what = names[key:sub(2, 2):lower()]
          local desc = (key:sub(1, 1) == "]" and "Next " or "Prev ")
            .. what
            .. (key:sub(2, 2):match("%u") and " end" or " start")
          vim.keymap.set({ "n", "x", "o" }, key, function()
            if vim.wo.diff and key:find("[cC]") then
              return vim.cmd.normal({ key, bang = true })
            end
            pcall(require("nvim-treesitter-textobjects.move")[method], query, "textobjects")
          end, { desc = desc, silent = true })
          ::continue::
        end
      end
    end,
  },
}
