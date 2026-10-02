local config = require("lumen.config")

-- installed parsers, refreshed after installs
local installed = {}
local function refresh()
  installed = {}
  for _, lang in ipairs(require("nvim-treesitter").get_installed()) do
    installed[lang] = true
  end
end

local function has_query(lang, query)
  return #vim.api.nvim_get_runtime_file(("queries/%s/%s.scm"):format(lang, query), false) > 0
end

---@param buf integer
local function attach(buf)
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  local lang = vim.treesitter.language.get_lang(vim.bo[buf].filetype)
  if not lang or not pcall(vim.treesitter.start, buf, lang) then
    return false
  end
  if has_query(lang, "indents") then
    vim.bo[buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
  end
  return true
end

local pending = {}

return {
  {
    "nvim-treesitter/nvim-treesitter",
    branch = "main",
    commit = vim.fn.has("nvim-0.12") == 0 and "7caec274fd19c12b55902a5b795100d21531391f" or nil,
    build = function()
      local ts = require("nvim-treesitter")
      if ts.update then
        ts.update(nil, { summary = true })
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
      local ts = require("nvim-treesitter")
      if not ts.get_installed then
        return Lumen.error("nvim-treesitter is outdated — run `:Lazy sync`")
      end
      ts.setup(opts)
      refresh()

      -- Neovim 0.11 bundles older parsers (lua, c, vim, …) than nvim-treesitter's queries expect.
      -- Installing one mid-session links the new queries while the old parser stays loaded, so
      -- every buffer of that language errors until restart. Keep the bundled parser + queries.
      local keep_bundled = vim.fn.has("nvim-0.12") == 0
      local missing = vim.tbl_filter(function(lang)
        return not installed[lang]
          and not (keep_bundled and #vim.api.nvim_get_runtime_file("parser/" .. lang .. ".*", false) > 0)
      end, vim.fn.uniq(vim.fn.sort(opts.ensure_installed or {})) --[[@as string[] ]])
      if #missing > 0 and vim.fn.executable("tree-sitter") == 1 then
        ts.install(missing, { summary = true }):await(function()
          refresh()
          vim.schedule(function()
            for _, b in ipairs(vim.api.nvim_list_bufs()) do
              if vim.api.nvim_buf_is_loaded(b) then
                attach(b)
              end
            end
          end)
        end)
      end

      local parsers = require("nvim-treesitter.parsers")
      vim.api.nvim_create_autocmd("FileType", {
        group = vim.api.nvim_create_augroup("lumen_treesitter", { clear = true }),
        callback = function(ev)
          if attach(ev.buf) ~= false then
            return
          end
          -- no parser yet: fetch it in the background, then light the buffer up
          local lang = vim.treesitter.language.get_lang(ev.match)
          if
            config.auto_install_parsers
            and lang
            and parsers[lang]
            and not installed[lang]
            and not pending[lang]
            and vim.fn.executable("tree-sitter") == 1
          then
            pending[lang] = true
            ts.install({ lang }):await(function()
              refresh()
              vim.schedule(function()
                for _, b in ipairs(vim.api.nvim_list_bufs()) do
                  if vim.api.nvim_buf_is_loaded(b) and vim.treesitter.language.get_lang(vim.bo[b].filetype) == lang then
                    attach(b)
                  end
                end
              end)
            end)
          end
        end,
      })

      -- buffers opened before treesitter loaded
      for _, b in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_loaded(b) and vim.bo[b].filetype ~= "" then
          attach(b)
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
      for method, keys in pairs(moves) do
        for key, query in pairs(keys) do
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
        end
      end
    end,
  },
}
