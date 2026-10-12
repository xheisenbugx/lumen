-- Treesitter helpers shared by the nvim-treesitter spec (plugins/treesitter.lua) and language
-- packs enabled while Neovim runs: attach buffers, and install parsers quietly in the background.
local M = {}

-- installed parsers, refreshed after installs
M.installed = {} ---@type table<string, boolean>

-- languages with an install in flight
local pending = {} ---@type table<string, boolean>

function M.refresh()
  M.installed = {}
  for _, lang in ipairs(require("nvim-treesitter").get_installed()) do
    M.installed[lang] = true
  end
end

local function has_query(lang, query)
  return #vim.api.nvim_get_runtime_file(("queries/%s/%s.scm"):format(lang, query), false) > 0
end

---@param buf integer
---@return boolean? false when there is no parser for the buffer
function M.attach(buf)
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

-- nvim-treesitter echoes three or four lines per parser ("Downloading…", "Compiling parser",
-- "Language installed"): about 80 lines on a first launch, which bury the screen under ui2. While
-- Lumen's own background installs run, its per-parser info lines are only logged (still in
-- :TSLog), warnings and errors still show, and one notification reports progress instead.
-- `Logger.lumen_quiet` counts the running installs (feature-detected: older nvim-treesitter
-- versions without `log.Logger` just stay verbose).
function M.hush()
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
function M.install(langs, on_done)
  for _, lang in ipairs(langs) do
    pending[lang] = true
  end
  local Logger = M.hush()
  Logger.lumen_quiet = (Logger.lumen_quiet or 0) + 1
  local id = "lumen.treesitter." .. table.concat(langs, ",")
  local what = #langs == 1 and ("the `%s` parser"):format(langs[1]) or ("%d treesitter parsers"):format(#langs)
  Lumen.notify(("Installing %s…"):format(what), nil, { id = id, timeout = false })
  require("nvim-treesitter").install(langs):await(function()
    Logger.lumen_quiet = Logger.lumen_quiet - 1
    M.refresh()
    local failed = vim.tbl_filter(function(lang)
      pending[lang] = nil
      return not M.installed[lang]
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

--- the parsers among `langs` that still need installing (and can be: nvim-treesitter knows them)
---@param langs string[]
---@return string[]
function M.missing(langs)
  -- Neovim 0.11 bundles older parsers (lua, c, vim, …) than nvim-treesitter's queries expect.
  -- Installing one mid-session links the new queries while the old parser stays loaded, so
  -- every buffer of that language errors until restart. Keep the bundled parser + queries.
  local keep_bundled = vim.fn.has("nvim-0.12") == 0
  return vim.tbl_filter(function(lang)
    return not M.installed[lang]
      and not pending[lang]
      and not (keep_bundled and #vim.api.nvim_get_runtime_file("parser/" .. lang .. ".*", false) > 0)
  end, vim.fn.uniq(vim.fn.sort(vim.deepcopy(langs))) --[[@as string[] ]])
end

--- install what's missing of `langs` in the background, then highlight the open buffers
---@param langs string[]
function M.ensure(langs)
  local missing = M.missing(langs)
  if #missing == 0 or vim.fn.executable("tree-sitter") == 0 then
    return
  end
  M.install(missing, function()
    for _, b in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_loaded(b) then
        M.attach(b)
      end
    end
  end)
end

--- whether a parser for `lang` is being installed right now
function M.is_pending(lang)
  return pending[lang] == true
end

return M
