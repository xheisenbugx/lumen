---@class lumen.Util
local M = {}

M.root = require("lumen.util.root")

--- whether `require(mod)` could find something. A failed require walks package.path,
--- package.cpath and then every runtimepath dir (~0.2ms per miss, and Lumen probes up to
--- seven optional user modules at startup); vim.loader.find() answers from its rtp index.
---@param mod string
function M.module_exists(mod)
  if package.loaded[mod] ~= nil or package.preload[mod] or not (vim.loader and vim.loader.find) then
    return true
  end
  return #vim.loader.find(mod) > 0
end

---@param mod string
function M.try_require(mod)
  if not M.module_exists(mod) then
    return
  end
  local ok, res = pcall(require, mod)
  if ok then
    return res
  end
  if not tostring(res):find("module '" .. mod .. "' not found", 1, true) then
    vim.schedule(function()
      M.error(("error loading `%s`\n%s"):format(mod, res))
    end)
  end
end

---@param msg string
---@param level? integer
---@param opts? table extra vim.notify opts, e.g. snacks' `id` to update a notification in place
function M.notify(msg, level, opts)
  vim.notify(msg, level or vim.log.levels.INFO, vim.tbl_extend("force", { title = "Lumen" }, opts or {}))
end

function M.warn(msg, opts)
  M.notify(msg, vim.log.levels.WARN, opts)
end

function M.error(msg, opts)
  M.notify(msg, vim.log.levels.ERROR, opts)
end

---@param name string
function M.has(name)
  return require("lazy.core.config").spec.plugins[name] ~= nil
end

---@param name string
function M.is_loaded(name)
  local p = require("lazy.core.config").plugins[name]
  return p ~= nil and p._.loaded ~= nil
end

--- run `fn` now if `name` is loaded, otherwise once it loads
---@param name string
---@param fn fun()
function M.on_load(name, fn)
  if M.is_loaded(name) then
    return fn()
  end
  vim.api.nvim_create_autocmd("User", {
    pattern = "LazyLoad",
    callback = function(ev)
      if ev.data == name then
        fn()
        return true
      end
    end,
  })
end

---@param fn fun()
function M.on_very_lazy(fn)
  vim.api.nvim_create_autocmd("User", { pattern = "VeryLazy", once = true, callback = fn })
end

---@param mode string|string[]
---@param lhs string
---@param rhs string|function
---@param opts? vim.keymap.set.Opts
function M.map(mode, lhs, rhs, opts)
  opts = opts or {}
  if opts.silent == nil then
    opts.silent = true
  end
  vim.keymap.set(mode, lhs, rhs, opts)
end

--- pick with Snacks rooted at the project root
---@param source string
---@param opts? table
function M.pick(source, opts)
  return function()
    -- a fresh table per call: the root depends on the buffer you're in *now*
    Snacks.picker.pick(source, vim.tbl_extend("force", { cwd = M.root() }, opts or {}))
  end
end

--- icon + highlight from mini.icons (loads it on first use)
---@param category string
---@param name string
---@return string? icon, string? hl
function M.icon(category, name)
  -- early redraws during startup use fallbacks; icons load once the UI is up
  if not _G.MiniIcons and vim.v.vim_did_enter == 0 then
    return
  end
  local ok, icons = pcall(require, "mini.icons")
  if ok and _G.MiniIcons then
    return icons.get(category, name)
  end
end

-- Terminals are keyed by their cwd (Snacks keys them by cmd + cwd). Inside one, the root of the
-- terminal buffer is not the root it was opened for (no file: it falls back to the cwd), so
-- toggling has to reuse the cwd stored on the terminal, or <C-/> opens a second terminal.
-- The same goes for any other window while a terminal is shown: its root can differ (a scratch
-- buffer, the explorer, an LSP root found since), so `opts.toggle` hides the shown terminal.
local fallback_terms = {} ---@type table<string, integer> cwd → terminal buffer (snacks.nvim disabled)

--- open, or hide, the terminal for `cwd` (default: the cwd)
---@param cwd? string
---@param opts? { toggle?: boolean } toggle: hide the terminal shown in this tab, whatever its cwd
function M.terminal(cwd, opts)
  local stored = vim.b.lumen_terminal_cwd
  if stored == nil and opts and opts.toggle then
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      stored = vim.b[vim.api.nvim_win_get_buf(win)].lumen_terminal_cwd
      if stored ~= nil then
        break
      end
    end
  end
  if stored ~= nil then
    cwd = stored ~= "" and stored or nil
  end
  if _G.Snacks then
    local term = Snacks.terminal(nil, { cwd = cwd })
    if term and term.buf and vim.api.nvim_buf_is_valid(term.buf) then
      vim.b[term.buf].lumen_terminal_cwd = cwd or ""
    end
    return term
  end
  -- snacks.nvim disabled: the same toggle with a plain split
  local key = cwd or ""
  local buf = fallback_terms[key]
  if buf and vim.api.nvim_buf_is_valid(buf) then
    local win = vim.fn.bufwinid(buf)
    if win ~= -1 then
      if #vim.api.nvim_list_wins() > 1 then
        vim.api.nvim_win_close(win, true)
      end
      return
    end
    vim.cmd("botright sbuffer " .. buf)
    vim.cmd.startinsert()
    return
  end
  vim.cmd("botright new")
  vim.fn.jobstart(vim.o.shell, { term = true, cwd = cwd })
  buf = vim.api.nvim_get_current_buf()
  vim.bo[buf].bufhidden = "hide"
  vim.b[buf].lumen_terminal_cwd = key
  fallback_terms[key] = buf
  vim.cmd.startinsert()
end

function M.in_tmux()
  return vim.env.TMUX ~= nil and vim.env.TMUX ~= ""
end

return M
