-- :Lumen update — updates with a safety net.
--   1. snapshot lazy-lock.json
--   2. sync plugins, update parsers & Mason registries
--   3. verify in a fresh headless Neovim: every plugin loads, no errors
--   4. if verification fails, offer a one-key rollback to the snapshot
-- :Lumen rollback — restore any earlier snapshot.

local M = {}

local lockfile = vim.fn.stdpath("config") .. "/lazy-lock.json"
local snap_dir = vim.fn.stdpath("state") .. "/lumen/snapshots"
local KEEP = 15

local function read(path)
  local f = io.open(path, "r")
  if not f then
    return
  end
  local s = f:read("*a")
  f:close()
  return s
end

local function write(path, s)
  vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
  local f = assert(io.open(path, "w"))
  f:write(s)
  f:close()
end

local function decode(s)
  local ok, data = pcall(vim.json.decode, s or "")
  return ok and type(data) == "table" and data or {}
end

---@return string? path
function M.snapshot()
  local s = read(lockfile)
  if not s then
    return
  end
  local path = ("%s/lock-%s.json"):format(snap_dir, os.date("%Y%m%d-%H%M%S"))
  write(path, s)
  local all = M.snapshots()
  for i = KEEP + 1, #all do
    os.remove(all[i].path)
  end
  return path
end

---@return {path:string, date:string}[] newest first
function M.snapshots()
  local out = {}
  for _, path in ipairs(vim.fn.glob(snap_dir .. "/lock-*.json", false, true)) do
    local y, mo, d, h, mi, se = path:match("lock%-(%d%d%d%d)(%d%d)(%d%d)%-(%d%d)(%d%d)(%d%d)%.json$")
    if y then
      out[#out + 1] = { path = path, date = ("%s-%s-%s %s:%s:%s"):format(y, mo, d, h, mi, se) }
    end
  end
  table.sort(out, function(a, b)
    return a.path > b.path
  end)
  return out
end

--- plugins whose commit differs between two lockfile contents
local function changed(before, after)
  local a, b = decode(before), decode(after)
  local names = {}
  for name, info in pairs(b) do
    if not a[name] or a[name].commit ~= info.commit then
      names[#names + 1] = name
    end
  end
  table.sort(names)
  return names
end

--- runs inside a headless child Neovim: load everything, report errors, exit
function M.selftest()
  local errors = {}
  local notify = vim.notify
  -- only real breakage counts: lazy.nvim load/config failures (not e.g. "Copilot: please sign in")
  vim.notify = function(msg, level, opts)
    local title = type(opts) == "table" and opts.title or ""
    if level == vim.log.levels.ERROR and (title == "lazy.nvim" or tostring(msg):find("Failed to")) then
      errors[#errors + 1] = tostring(msg)
    end
    return notify(msg, level, opts)
  end
  vim.cmd.edit(vim.fn.stdpath("config") .. "/init.lua")
  vim.defer_fn(function()
    for _, plugin in pairs(require("lazy.core.config").plugins) do
      local ok, err = pcall(require("lazy").load, { plugins = { plugin.name } })
      if not ok then
        errors[#errors + 1] = plugin.name .. ": " .. tostring(err)
      end
    end
    for _, mod in ipairs({ "statusline", "tabline", "winbar" }) do
      local ok, err = pcall(require("lumen.ui." .. mod).render)
      if not ok then
        errors[#errors + 1] = "lumen " .. mod .. ": " .. tostring(err)
      end
    end
    -- v:errmsg is not used: plugins routinely leave errors there that they caught themselves
    vim.defer_fn(function()
      io.stdout:write(vim.json.encode({ errors = errors }) .. "\n")
      vim.cmd(#errors == 0 and "qa!" or "cquit 1")
    end, 1500)
  end, 1000)
end

---@param cb fun(ok:boolean, errors:string[])
function M.verify(cb)
  local cmd = { vim.v.progpath, "--headless", "-c", "lua require('lumen.update').selftest()" }
  vim.system(cmd, { text = true, timeout = 60000 }, function(out)
    local errors = {}
    for line in (out.stdout or ""):gmatch("[^\n]+") do
      local ok, data = pcall(vim.json.decode, line)
      if ok and type(data) == "table" and data.errors then
        errors = data.errors
      end
    end
    if out.code ~= 0 and #errors == 0 then
      errors = { ("headless Neovim exited with code %d"):format(out.code), out.stderr or "" }
    end
    vim.schedule(function()
      cb(out.code == 0 and #errors == 0, errors)
    end)
  end)
end

---@param path string snapshot to restore
function M.restore(path)
  local s = read(path)
  if not s then
    return Lumen.error("snapshot not found: " .. path)
  end
  write(lockfile, s)
  Lumen.notify("Restoring plugins from " .. vim.fn.fnamemodify(path, ":t") .. "…")
  require("lazy").restore({ wait = false, show = true })
  vim.api.nvim_create_autocmd("User", {
    pattern = "LazyRestore",
    once = true,
    callback = function()
      require("lumen.packs").prompt_restart("Plugins rolled back")
    end,
  })
end

function M.update()
  local before = read(lockfile)
  local snap = M.snapshot()
  Lumen.notify("Snapshot saved — updating…")
  vim.api.nvim_create_autocmd("User", {
    pattern = "LazySync",
    once = true,
    callback = function()
      pcall(vim.cmd, "TSUpdate")
      pcall(vim.cmd, "MasonUpdate")
      vim.defer_fn(function()
        local after = read(lockfile)
        local names = changed(before, after)
        if #names == 0 then
          return Lumen.notify("✓ Everything is up to date")
        end
        Lumen.notify(("Verifying %d updated plugins in a clean Neovim…"):format(#names))
        M.verify(function(ok, errors)
          if ok then
            Lumen.notify(("✓ Update verified — %d plugins updated:\n%s"):format(#names, table.concat(names, ", ")))
            require("lumen.packs").prompt_restart("Update complete")
            return
          end
          vim.notify(
            "✗ Update broke something:\n" .. table.concat(errors, "\n"):sub(1, 1200),
            vim.log.levels.ERROR,
            { title = "Lumen update" }
          )
          if not snap then
            return
          end
          vim.ui.select(
            { "Roll back", "Keep the update" },
            { prompt = "Lumen: roll back to the snapshot?" },
            function(choice)
              if choice == "Roll back" then
                M.restore(snap)
              end
            end
          )
        end)
      end, 500)
    end,
  })
  require("lazy").sync({ wait = false, show = true })
end

function M.pick_rollback()
  local snaps = M.snapshots()
  if #snaps == 0 then
    return Lumen.warn("No snapshots yet — they are created by :Lumen update")
  end
  local current = read(lockfile)
  vim.ui.select(snaps, {
    prompt = "Roll back plugins to",
    format_item = function(s)
      local n = #changed(read(s.path), current)
      return ("%s   (%d plugins differ from now)"):format(s.date, n)
    end,
  }, function(choice)
    if choice then
      M.restore(choice.path)
    end
  end)
end

return M
