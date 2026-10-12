-- :Lumen update — updates with a safety net.
--   1. snapshot lazy-lock.json
--   2. sync plugins, update parsers (to the revisions the new nvim-treesitter pins) & Mason registries
--   3. verify in a fresh headless Neovim: every plugin loads, no errors
--   4. if verification fails, offer a one-key rollback to the snapshot
--   5. show what's new in Lumen (NEWS.md) when Lumen itself moved
-- :Lumen rollback — restore any earlier snapshot (parsers follow nvim-treesitter back).

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

--- lazy.nvim caches lazy-lock.json in memory, and its load() is a no-op once it has run, so
--- restore() would silently use the old commits. Write the file and set the cache to match.
local function write_lock(content)
  write(lockfile, content)
  local ok, data = pcall(vim.json.decode, content)
  if ok and type(data) == "table" then
    pcall(function()
      local Lock = require("lazy.manage.lock")
      Lock.lock, Lock._loaded = data, true
    end)
  end
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
  -- an update that changed nothing would otherwise add a duplicate every time and, after KEEP
  -- of them, evict every snapshot worth rolling back to
  local newest = M.snapshots()[1]
  if newest and read(newest.path) == s then
    return newest.path
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
  local function finish()
    io.stdout:write(vim.json.encode({ errors = errors }) .. "\n")
    vim.cmd(#errors == 0 and "qa!" or "cquit 1")
  end
  local function run()
    vim.cmd.edit(vim.fn.stdpath("config") .. "/init.lua")
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
    -- let scheduled work (plugin setups, FileType handlers, highlighting) run: its errors are
    -- printed to stderr, which verify() reads. v:errmsg is not used: plugins routinely leave
    -- errors there that they caught themselves.
    vim.defer_fn(finish, 1000)
  end
  -- start once startup is over rather than after a guessed delay
  if vim.v.vim_did_enter == 1 then
    vim.schedule(run)
  else
    vim.api.nvim_create_autocmd("VimEnter", { once = true, callback = vim.schedule_wrap(run) })
  end
end

--- error lines a headless Neovim printed (it writes error messages to stderr): Lua errors in
--- autocmds and callbacks never reach vim.notify
---@param stderr string
---@return string[]
function M.stderr_errors(stderr)
  local out, keep = {}, false
  for line in (stderr or ""):gmatch("[^\r\n]+") do
    if line:find("^E%d+:") or line:find("^Error") or line:find("^Lua callback") then
      keep = true
    elseif not line:find("^%s") and not line:find("^stack traceback") then
      keep = false
    end
    if keep then
      out[#out + 1] = line
    end
  end
  return out
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
    vim.list_extend(errors, M.stderr_errors(out.stderr))
    if out.code ~= 0 and #errors == 0 then
      errors = { ("headless Neovim exited with code %d"):format(out.code), out.stderr or "" }
    end
    vim.schedule(function()
      cb(out.code == 0 and #errors == 0, errors)
    end)
  end)
end

--- Bring parsers in line with the installed nvim-treesitter (it pins their revisions), then `cb`.
--- Runs after plugins move either way: an update, and a rollback, which would otherwise leave
--- parsers newer than the queries that came back with nvim-treesitter.
---@param cb? fun()
---@param summary? boolean report "All parsers are up-to-date" and such (default true)
function M.update_parsers(cb, summary)
  cb = cb or function() end
  local ok, nts = pcall(require, "nvim-treesitter")
  if not ok or type(nts.update) ~= "function" then
    return cb()
  end
  local task_ok, task = pcall(nts.update, nil, { summary = summary ~= false })
  if task_ok and type(task) == "table" and type(task.await) == "function" then
    task:await(vim.schedule_wrap(cb))
  else
    cb()
  end
end

---@param path string snapshot to restore
function M.restore(path)
  local s = read(path)
  if not s then
    return Lumen.error("snapshot not found: " .. path)
  end
  write_lock(s)
  Lumen.notify("Restoring plugins from " .. vim.fn.fnamemodify(path, ":t") .. "…")
  -- blocking, for the same reason as step(): see above
  require("lazy.manage").restore({ wait = true, show = true })
  M.update_parsers(function()
    require("lumen.packs").prompt_restart("Plugins rolled back")
  end, false)
end

-- Lumen's version before this update, for "what's new" afterwards
local old_version ---@type string?

--- after plugins changed: parsers, Mason, then verify in a clean Neovim and offer rollback
---@param before string? lockfile content before the update
---@param snap string? snapshot path
local function finish(before, snap)
  pcall(vim.cmd, "MasonUpdate")
  -- the verification must see the parsers this update ends with, so it waits for them
  M.update_parsers(function()
    local after = read(lockfile)
    local names = changed(before, after)
    M.show_news(old_version)
    old_version = nil
    if #names == 0 then
      return Lumen.notify("✓ Everything is up to date")
    end
    local count = #names == 1 and "1 plugin" or (#names .. " plugins")
    Lumen.notify(("Verifying %s in a clean Neovim…"):format(count))
    M.verify(function(ok, errors)
      if ok then
        Lumen.notify(("✓ Update verified — %s updated:\n%s"):format(count, table.concat(names, ", ")))
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
  end)
end

--- Apply the vetted versions to the user's lockfile.
--- Plugins in both move to the vetted commit; plugins only the user has ("extras", e.g. their own
--- plugins) are returned so they can update to latest; vetted plugins the user doesn't use are skipped.
---@param current table<string, {branch:string, commit:string}> the user's lazy-lock.json
---@param vetted table<string, {branch:string, commit:string}> Lumen's lumen-lock.json
---@return table merged, string[] pinned, string[] extras
function M.merge_lock(current, vetted)
  local merged, pinned, extras = vim.deepcopy(current), {}, {}
  for name, info in pairs(current) do
    if name ~= "lumen" and vetted[name] and vetted[name].commit then
      merged[name] = { branch = vetted[name].branch or info.branch, commit = vetted[name].commit }
      pinned[#pinned + 1] = name
    elseif name ~= "lumen" then
      extras[#extras + 1] = name
    end
  end
  table.sort(pinned)
  table.sort(extras)
  return merged, pinned, extras
end

--- the vetted lockfile shipped with the installed Lumen (nil until CI has published one)
function M.vetted()
  local plugin = require("lazy.core.config").plugins.lumen
  local path = plugin and plugin.dir and (plugin.dir .. "/lumen-lock.json")
  local data = path and decode(read(path))
  return data and next(data) and data or nil
end

local function latest(before, snap)
  vim.api.nvim_create_autocmd("User", {
    pattern = "LazySync",
    once = true,
    callback = function()
      finish(before, snap)
    end,
  })
  require("lazy").sync({ wait = false, show = true })
end

--- run a lazy.nvim manage step to completion, then `next`. It must block (`wait = true`): with an
--- async runner lazy may record the lockfile from the *current* commits before its checkout runs,
--- undoing the versions we just asked for.
---@param fn "update"|"restore"
---@param opts table
---@param next fun()
local function step(fn, opts, next)
  require("lazy.manage")[fn](vim.tbl_extend("force", opts, { wait = true }))
  vim.schedule(next)
end

--- stable channel: Lumen first (it carries the vetted versions), then every plugin it vetted to
--- exactly that commit, and plugins it doesn't know about to latest
local function stable(before, snap)
  local function apply()
    local vetted = M.vetted()
    if not vetted then
      Lumen.warn('No vetted plugin versions yet — updating to latest (update_channel = "latest" behaviour)')
      return latest(before, snap)
    end
    local merged, pinned, extras = M.merge_lock(decode(read(lockfile)), vetted)
    write_lock(vim.json.encode(merged))
    Lumen.notify(
      ("Stable channel: %d plugins to their CI-tested versions, %d of your own to latest"):format(#pinned, #extras)
    )
    local function update_extras()
      if #extras == 0 then
        return finish(before, snap)
      end
      step("update", { plugins = extras, show = true }, function()
        finish(before, snap)
      end)
    end
    if #pinned == 0 then
      return update_extras()
    end
    step("restore", { plugins = pinned, show = true }, update_extras)
  end
  local lumen = require("lazy.core.config").plugins.lumen
  -- a local checkout (`dir =`, contributors) has nothing to fetch
  if lumen and lumen.url then
    step("update", { plugins = { "lumen" }, show = false }, apply)
  else
    apply()
  end
end

function M.update()
  old_version = require("lumen").version
  local before = read(lockfile)
  local snap = M.snapshot()
  local channel = require("lumen.config").update_channel or "stable"
  Lumen.notify(("Snapshot saved — updating (%s channel)…"):format(channel))
  if channel == "latest" then
    latest(before, snap)
  else
    stable(before, snap)
  end
end

-- ── what's new ───────────────────────────────────────────────

local function lumen_dir()
  local plugin = require("lazy.core.config").plugins.lumen
  return plugin and plugin.dir
end

--- the version of Lumen on disk (after an update it's newer than the running one)
---@return string?
function M.installed_version()
  local dir = lumen_dir()
  return dir and (read(dir .. "/lua/lumen/init.lua") or ""):match('M%.version = "([^"]+)"') or nil
end

--- NEWS.md sections (`## <version> …`), newest first
---@param text string
---@return {version:string, lines:string[]}[]
function M.parse_news(text)
  local sections, cur = {}, nil
  for line in (text .. "\n"):gmatch("(.-)\r?\n") do
    local v = line:match("^## v?(%d+%.%d+%.%d+)")
    if v then
      cur = { version = v, lines = { line } }
      sections[#sections + 1] = cur
    elseif cur then
      cur.lines[#cur.lines + 1] = line
    end
  end
  return sections
end

--- the NEWS.md lines for versions newer than `since` (all of them when it's nil)
---@param since? string
---@return string[]
function M.news_since(since)
  local dir = lumen_dir()
  local lines = {}
  for _, section in ipairs(M.parse_news(dir and read(dir .. "/NEWS.md") or "")) do
    local ok, newer = pcall(function()
      return not since or vim.version.gt(section.version, since)
    end)
    if ok and newer then
      vim.list_extend(lines, section.lines)
    end
  end
  return lines
end

--- :Lumen news — what's new, newest first
---@param since? string only versions after this one
function M.news(since)
  local lines = M.news_since(since)
  if #lines == 0 then
    return Lumen.notify("No news")
  end
  table.insert(lines, 1, "# What's new in Lumen")
  table.insert(lines, 2, "")
  vim.cmd("botright new")
  local buf = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].buftype, vim.bo[buf].bufhidden, vim.bo[buf].modifiable = "nofile", "wipe", false
  vim.bo[buf].filetype = "markdown"
  vim.keymap.set("n", "q", "<cmd>close<cr>", { buffer = buf, silent = true, desc = "Close" })
end

--- after an update: the news since the version that was running, if Lumen moved
---@param old? string
function M.show_news(old)
  local new = M.installed_version()
  local ok, newer = pcall(function()
    return old and new and vim.version.gt(new, old)
  end)
  if ok and newer and #M.news_since(old) > 0 then
    M.news(old)
  end
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
