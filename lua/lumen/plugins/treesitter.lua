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

-- nvim-treesitter echoes three or four lines per parser ("Downloading…", "Compiling parser",
-- "Language installed"): about 80 lines on a first launch, which bury the screen under ui2. While
-- Lumen's own background installs run, its per-parser info lines are only logged (still in
-- :TSLog), warnings and errors still show, and one notification reports progress instead.
-- `Logger.lumen_quiet` counts the running installs (feature-detected: older nvim-treesitter
-- versions without `log.Logger` just stay verbose).
local function hush()
  local ok, log = pcall(require, "nvim-treesitter.log")
  local Logger = ok and type(log) == "table" and log.Logger
  if type(Logger) ~= "table" or not Logger.info or not Logger.debug then
    return {}
  end
  if not Logger.lumen_info then
    Logger.lumen_quiet, Logger.lumen_info = 0, Logger.info
    Logger.info = function(self, ...)
      if Logger.lumen_quiet > 0 and type(self.ctx) == "string" and self.ctx:find("^install/") then
        return Logger.debug(self, ...)
      end
      return Logger.lumen_info(self, ...)
    end
  end
  return Logger
end

---@param langs string[]
---@param on_done fun()
local function install(langs, on_done)
  local Logger = hush()
  Logger.lumen_quiet = (Logger.lumen_quiet or 0) + 1
  local id = "lumen.treesitter." .. table.concat(langs, ",")
  local what = #langs == 1 and ("the `%s` parser"):format(langs[1]) or ("%d treesitter parsers"):format(#langs)
  Lumen.notify(("Installing %s…"):format(what), nil, { id = id, timeout = false })
  require("nvim-treesitter").install(langs):await(function()
    Logger.lumen_quiet = Logger.lumen_quiet - 1
    refresh()
    local failed = vim.tbl_filter(function(lang)
      return not installed[lang]
    end, langs)
    vim.schedule(function()
      if #failed == 0 then
        Lumen.notify(("Installed %s"):format(what), nil, { id = id, timeout = 2500 })
      else
        Lumen.notify(
          ("Couldn't install %s — see `:TSLog`"):format(table.concat(failed, ", ")),
          vim.log.levels.WARN,
          { id = id, timeout = 5000 }
        )
      end
      on_done()
    end)
  end)
end

return {
  {
    "nvim-treesitter/nvim-treesitter",
    branch = "main",
    commit = vim.fn.has("nvim-0.12") == 0 and "7caec274fd19c12b55902a5b795100d21531391f" or nil,
    build = function()
      local ts = require("nvim-treesitter")
      -- on a fresh install there is nothing to update yet (it would only print "All parsers are
      -- up-to-date" right before the first parsers get installed)
      if ts.update and ts.get_installed and #ts.get_installed() > 0 then
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
      hush()

      -- Neovim 0.11 bundles older parsers (lua, c, vim, …) than nvim-treesitter's queries expect.
      -- Installing one mid-session links the new queries while the old parser stays loaded, so
      -- every buffer of that language errors until restart. Keep the bundled parser + queries.
      local keep_bundled = vim.fn.has("nvim-0.12") == 0
      local missing = vim.tbl_filter(function(lang)
        return not installed[lang]
          and not (keep_bundled and #vim.api.nvim_get_runtime_file("parser/" .. lang .. ".*", false) > 0)
      end, vim.fn.uniq(vim.fn.sort(opts.ensure_installed or {})) --[[@as string[] ]])
      if #missing > 0 and vim.fn.executable("tree-sitter") == 1 then
        install(missing, function()
          for _, b in ipairs(vim.api.nvim_list_bufs()) do
            if vim.api.nvim_buf_is_loaded(b) then
              attach(b)
            end
          end
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
            install({ lang }, function()
              for _, b in ipairs(vim.api.nvim_list_bufs()) do
                if vim.api.nvim_buf_is_loaded(b) and vim.treesitter.language.get_lang(vim.bo[b].filetype) == lang then
                  attach(b)
                end
              end
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
