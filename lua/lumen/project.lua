-- Per-project settings: a `.lumen.lua` in the project (found upward from the cwd at startup)
-- returns a table like lua/config/lumen.lua:
--
--   return {
--     packs = { "go" },                               -- added to your packs, for this project only
--     tasks = { { name = "e2e", cmd = "make e2e" } }, -- added to the task runner
--     format_on_save = false,                         -- any other setting overrides yours
--   }
--
-- It is code from the project, so it only runs once you trust it (Neovim's trust database, the
-- same one `:trust` and 'exrc' use). Startup never prompts: an untrusted file gets a notification,
-- `:Lumen project` opens it for review and `:Lumen trust` trusts it and applies it right away.

local M = {}

M.name = ".lumen.lua"

-- settings needed before plugins load, or that decide what gets downloaded: never per project
M.ignored = { "leader", "localleader", "ui2", "update_channel" }

---@type string? the .lumen.lua found at startup
M.path = nil
M.trusted = false

local settings = {} ---@type table

--- the nearest .lumen.lua at or above `dir`. A plain stat per directory: this runs on every
--- startup, before vim.fs is loaded
---@param dir? string
---@return string?
function M.find(dir)
  dir = dir or vim.uv.cwd()
  while dir and dir ~= "" do
    local path = dir .. (dir:sub(-1) == "/" and "" or "/") .. M.name
    local stat = vim.uv.fs_stat(path)
    if stat and stat.type == "file" then
      return path
    end
    local parent = dir:match("^(.*)[/\\][^/\\]+$")
    if parent == "" then
      parent = dir:sub(1, 1) == "/" and "/" or nil
    end
    dir = parent ~= dir and parent or nil
  end
end

---@param path string
---@return string?
local function fullpath(path)
  local real = vim.uv.fs_realpath(vim.fs.normalize(path))
  return real and vim.fs.normalize(real)
end

--- the file's contents if the trust database trusts them as they are now; never prompts
--- (vim.secure.read() would: a blocking confirm() while lazy.nvim reads specs)
---@param path string
---@return string?
function M.trusted_contents(path)
  local full = fullpath(path)
  local f = io.open(vim.fn.stdpath("state") .. "/trust", "r")
  if not f then
    return
  end
  if not full then
    f:close()
    return
  end
  local db = f:read("*a") or ""
  f:close()
  local hash
  for line in vim.gsplit(db, "\n") do
    local h, file = line:match("^(%S+) (.+)$")
    if file == full then
      hash = h
    end
  end
  local cf = hash and hash ~= "!" and io.open(full, "rb")
  if not cf then
    return
  end
  local contents = cf:read("*a")
  cf:close()
  return vim.fn.sha256(contents) == hash and contents or nil
end

---@param path string
---@param contents string
---@return table? settings, string? err
local function eval(path, contents)
  local fn, err = load(contents, "@" .. path)
  if not fn then
    return nil, err
  end
  local ok, res = pcall(fn)
  if not ok then
    return nil, tostring(res)
  end
  if type(res) ~= "table" then
    return nil, "it must return a table"
  end
  return res
end

local function report(msg, level)
  vim.schedule(function()
    vim.notify(msg, level or vim.log.levels.ERROR, { title = "Lumen" })
  end)
end

--- settings that override yours (no packs or tasks: those are added, see M.packs / M.tasks)
---@return table
function M.settings()
  local out = vim.deepcopy(settings)
  out.packs, out.tasks = nil, nil
  for _, k in ipairs(M.ignored) do
    out[k] = nil
  end
  return out
end

---@return string[]
function M.packs()
  return type(settings.packs) == "table" and settings.packs or {}
end

---@return {name?:string, cmd:string, cwd?:string}[]
function M.tasks()
  return type(settings.tasks) == "table" and settings.tasks or {}
end

--- the project root: where .lumen.lua lives
function M.root()
  return M.path and vim.fs.dirname(M.path)
end

--- Read the project's .lumen.lua if it's trusted. Called by lumen.config while it loads settings.
---@return table settings to merge over yours
function M.load()
  settings, M.trusted = {}, false
  M.path = M.find()
  local contents = M.path and M.trusted_contents(M.path)
  if not contents then
    return {}
  end
  local res, err = eval(M.path, contents)
  if not res then
    report(("Lumen: error in %s\n%s"):format(vim.fn.fnamemodify(M.path, ":~"), err))
    return {}
  end
  settings, M.trusted = res, true
  local ignored = vim.tbl_filter(function(k)
    return res[k] ~= nil
  end, M.ignored)
  if #ignored > 0 then
    report(
      ("Lumen: `%s` can't be set per project — ignored in %s"):format(table.concat(ignored, "`, `"), M.name),
      vim.log.levels.WARN
    )
  end
  return M.settings()
end

--- after startup: say once that an untrusted .lumen.lua is waiting
function M.check()
  if M.path and not M.trusted and #vim.api.nvim_list_uis() > 0 then
    Lumen.warn(
      ("This project has a `%s` that isn't trusted yet.\nReview it with `:Lumen project`, then run `:Lumen trust`"):format(
        M.name
      )
    )
  end
end

--- :Lumen project — open the project's .lumen.lua (or start one at the project root)
function M.edit()
  vim.cmd.edit(vim.fn.fnameescape(M.path or M.find() or (Lumen.root() .. "/" .. M.name)))
end

--- :Lumen trust — trust the project's .lumen.lua as it is now, and apply it to this session
function M.trust()
  local path = M.path or M.find()
  if not path then
    return Lumen.warn(("No %s in %s or above"):format(M.name, vim.fn.fnamemodify(vim.uv.cwd() or ".", ":~")))
  end
  local buf = vim.fn.bufnr(path)
  if buf ~= -1 and vim.bo[buf].modified then
    return Lumen.warn(("Save %s first: trust covers what's on disk"):format(M.name))
  end
  -- what you reviewed is the buffer: if the file changed on disk since (git pull), trust what's in
  -- the buffer. The file then doesn't match the trusted hash, so the unseen code still won't run
  local opts = (buf ~= -1 and vim.api.nvim_buf_is_loaded(buf)) and { action = "allow", bufnr = buf }
    or { action = "allow", path = path }
  local ok, err = vim.secure.trust(opts)
  if not ok then
    return Lumen.error(("couldn't trust %s: %s"):format(path, err))
  end
  M.apply(path)
end

--- apply a (now trusted) .lumen.lua to the running session
---@param path string
function M.apply(path)
  local contents = M.trusted_contents(path)
  if not contents then
    return Lumen.error(("%s is not trusted"):format(path))
  end
  local res, err = eval(path, contents)
  if not res then
    return Lumen.error(("%s: %s"):format(M.name, err))
  end
  local packs = require("lumen.packs")
  local before = packs.enabled()
  M.path, M.trusted, settings = path, true, res
  local config = require("lumen.config")
  for k, v in pairs(M.settings()) do
    config[k] = v
  end
  if res.format_on_save ~= nil then
    vim.g.lumen_autoformat = res.format_on_save
  end
  if res.diagnostics ~= nil and package.loaded["lumen.diagnostics"] then
    local diagnostics = require("lumen.diagnostics")
    diagnostics.mode = res.diagnostics
    diagnostics.setup()
  end
  Lumen.notify(("Trusted and applied %s"):format(vim.fn.fnamemodify(path, ":~:.")))
  packs.changed(before, packs.enabled())
end

return M
