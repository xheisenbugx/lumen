---@class lumen.Util
local M = {}

M.root = require("lumen.util.root")

---@param mod string
function M.try_require(mod)
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
function M.notify(msg, level)
  vim.notify(msg, level or vim.log.levels.INFO, { title = "Lumen" })
end

function M.warn(msg)
  M.notify(msg, vim.log.levels.WARN)
end

function M.error(msg)
  M.notify(msg, vim.log.levels.ERROR)
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
    opts = vim.tbl_extend("force", { cwd = M.root() }, opts or {})
    Snacks.picker.pick(source, opts)
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

function M.in_tmux()
  return vim.env.TMUX ~= nil and vim.env.TMUX ~= ""
end

return M
