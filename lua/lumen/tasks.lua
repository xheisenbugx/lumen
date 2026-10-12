-- Task runner: discovers project tasks and runs them in a terminal split or in the
-- background (errors → quickfix). The last task per project is one key away.
--
-- Sources: package.json (npm/pnpm/yarn/bun), deno.json, Makefile, justfile, Cargo,
-- go, uv/pytest, composer, mix, gradle, maven, dotnet, zig, cmake, docker compose,
-- .vscode/tasks.json, plus `tasks = {}` from lua/config/lumen.lua and the project's .lumen.lua.

local M = {}

---@class lumen.Task
---@field name string
---@field cmd string
---@field cwd string
---@field source string

local state_file = vim.fn.stdpath("state") .. "/lumen/tasks.json"

---@type table<string, {name:string, started:number}>
M.running = {}

local function read(path)
  local f = io.open(path, "r")
  if not f then
    return
  end
  local s = f:read("*a")
  f:close()
  return s
end

local function exists(dir, name)
  return vim.uv.fs_stat(dir .. "/" .. name) ~= nil
end

--- a script name as one shell word: names are free text in package.json & co (`build all`, `a&b`)
---@param name string
local function word(name)
  return name:find("^[%w_.:/@+=,-]+$") and name or vim.fn.shellescape(name)
end

--- JSON with comments (deno.jsonc, tsconfig-style): drop // and /* */ comments outside strings,
--- then trailing commas, so vim.json can read it
---@param s string
function M.strip_jsonc(s)
  local out, i, n, in_str = {}, 1, #s, false
  while i <= n do
    local c = s:sub(i, i)
    if in_str then
      out[#out + 1] = c
      if c == "\\" then
        out[#out + 1] = s:sub(i + 1, i + 1)
        i = i + 1
      elseif c == '"' then
        in_str = false
      end
    elseif c == '"' then
      in_str = true
      out[#out + 1] = c
    elseif s:sub(i, i + 1) == "//" then
      i = (s:find("\n", i, true) or n + 1) - 1
    elseif s:sub(i, i + 1) == "/*" then
      i = (select(2, s:find("*/", i + 2, true)) or n)
    else
      out[#out + 1] = c
    end
    i = i + 1
  end
  return (table.concat(out):gsub(",(%s*[}%]])", "%1"))
end

local function json(path)
  local s = read(path)
  if not s then
    return
  end
  local opts = { luanil = { object = true, array = true } }
  local ok, data = pcall(vim.json.decode, s, opts)
  if not ok then
    ok, data = pcall(vim.json.decode, M.strip_jsonc(s), opts)
  end
  return ok and data or nil
end

---@param buf integer
---@param markers string|string[]
local function find(buf, markers)
  local dir = vim.fs.root(buf, markers)
  return dir and vim.fs.normalize(dir) or nil
end

---@type table<string, fun(dir:string, add:fun(name:string, cmd:string, cwd?:string))>
local providers = {}

providers["package.json"] = function(dir, add)
  local pkg = json(dir .. "/package.json") or {}
  local pm = "npm run"
  if exists(dir, "bun.lockb") or exists(dir, "bun.lock") then
    pm = "bun run"
  elseif exists(dir, "pnpm-lock.yaml") then
    pm = "pnpm run"
  elseif exists(dir, "yarn.lock") then
    pm = "yarn run"
  end
  local names = vim.tbl_keys(pkg.scripts or {})
  table.sort(names)
  for _, name in ipairs(names) do
    add(name, pm .. " " .. word(name))
  end
end

providers["deno.json"] = function(dir, add)
  local cfg = json(dir .. "/deno.json") or json(dir .. "/deno.jsonc") or {}
  for name in pairs(cfg.tasks or {}) do
    add(name, "deno task " .. word(name))
  end
end

providers["Makefile"] = function(dir, add)
  local seen = {}
  for line in (read(dir .. "/Makefile") or ""):gmatch("[^\n]+") do
    local target = line:match("^([%w][%w_./-]*)%s*:[^=]") or line:match("^([%w][%w_./-]*)%s*:$")
    if target and not seen[target] and not target:find("%.") then
      seen[target] = true
      add(target, "make " .. target)
    end
  end
end

providers["justfile"] = function(dir, add)
  if vim.fn.executable("just") == 0 then
    return
  end
  local out = vim.system({ "just", "--summary" }, { cwd = dir, text = true }):wait(1500)
  for name in (out.stdout or ""):gmatch("%S+") do
    add(name, "just " .. name)
  end
end

providers["Cargo.toml"] = function(_, add)
  for _, t in ipairs({ "build", "run", "test", "check", "clippy", "fmt", "build --release" }) do
    add(t, "cargo " .. t)
  end
end

providers["go.mod"] = function(_, add)
  add("build", "go build ./...")
  add("test", "go test ./...")
  add("run", "go run .")
  add("vet", "go vet ./...")
  add("tidy", "go mod tidy")
end

providers["pyproject.toml"] = function(dir, add)
  local run = exists(dir, "uv.lock") and "uv run " or (exists(dir, "poetry.lock") and "poetry run " or "")
  add("pytest", run .. "pytest")
  add("pytest (last failed)", run .. "pytest --lf")
  if run == "uv run " then
    add("sync", "uv sync")
  end
  local text = read(dir .. "/pyproject.toml") or ""
  local section = text:match("%[project%.scripts%]\n(.-)\n%[") or text:match("%[project%.scripts%]\n(.*)$") or ""
  for name in section:gmatch("\n?([%w_-]+)%s*=") do
    add(name, run .. name)
  end
end

providers["composer.json"] = function(dir, add)
  for name in pairs((json(dir .. "/composer.json") or {}).scripts or {}) do
    add(name, "composer run " .. word(name))
  end
end

providers["mix.exs"] = function(dir, add)
  add("test", "mix test")
  add("compile", "mix compile")
  add("deps.get", "mix deps.get")
  if (read(dir .. "/mix.exs") or ""):find("phoenix") then
    add("phx.server", "mix phx.server")
  end
end

providers["gradlew"] = function(_, add)
  for _, t in ipairs({ "build", "test", "run", "clean" }) do
    add(t, "./gradlew " .. t)
  end
end

providers["pom.xml"] = function(_, add)
  for _, t in ipairs({ "package", "test", "clean install" }) do
    add(t, "mvn " .. t)
  end
end

providers["build.zig"] = function(_, add)
  add("build", "zig build")
  add("test", "zig build test")
  add("run", "zig build run")
end

providers["CMakeLists.txt"] = function(_, add)
  add("configure", "cmake -B build -DCMAKE_EXPORT_COMPILE_COMMANDS=ON")
  add("build", "cmake --build build")
  add("test", "ctest --test-dir build")
end

providers["compose"] = function(_, add)
  add("up", "docker compose up")
  add("up -d", "docker compose up -d")
  add("down", "docker compose down")
  add("logs", "docker compose logs -f")
end

providers["dotnet"] = function(_, add)
  add("build", "dotnet build")
  add("test", "dotnet test")
  add("run", "dotnet run")
end

-- ${…} variables VS Code tasks use; unknown ones are left as they are
---@param s string
---@param dir string the folder holding .vscode/
local function vscode_vars(s, dir)
  -- the root comes back as a real path (macOS: /var → /private/var): compare like with like
  local name = vim.api.nvim_buf_get_name(0)
  local file = name ~= "" and vim.fs.normalize(vim.uv.fs_realpath(name) or name) or ""
  local vars = {
    workspaceFolder = dir,
    workspaceRoot = dir,
    workspaceFolderBasename = vim.fs.basename(dir),
    cwd = vim.uv.cwd(),
    file = file,
    fileDirname = vim.fs.dirname(file),
    fileBasename = vim.fs.basename(file),
    fileBasenameNoExtension = vim.fn.fnamemodify(file, ":t:r"),
    relativeFile = file:sub(1, #dir + 1) == dir .. "/" and file:sub(#dir + 2) or file,
    pathSeparator = "/",
  }
  return (
    s:gsub("%${([%w:_]+)}", function(name)
      local env = name:match("^env:(.+)$")
      if env then
        return vim.env[env] or ""
      end
      return vars[name]
    end)
  )
end

--- `args` items are strings or { value = "…", quoting = "…" }
---@param args any[]
local function vscode_args(args, dir)
  local out = {}
  for _, a in ipairs(type(args) == "table" and args or {}) do
    local v = vscode_vars(type(a) == "table" and tostring(a.value or "") or tostring(a), dir)
    -- quote what the shell would split or expand, like VS Code does
    out[#out + 1] = v:find("[%s'\"$`\\|&;<>()*?]") and vim.fn.shellescape(v) or v
  end
  return out
end

providers[".vscode"] = function(dir, add)
  local data = json(dir .. "/.vscode/tasks.json") or {}
  local os_key = vim.fn.has("mac") == 1 and "osx" or (vim.fn.has("win32") == 1 and "windows" or "linux")
  for _, t in ipairs(data.tasks or {}) do
    -- platform sections override the task's own fields
    t = vim.tbl_deep_extend("force", t, type(t[os_key]) == "table" and t[os_key] or {})
    local cmd
    if t.type == "npm" and t.script then
      cmd = "npm run " .. word(t.script)
      if t.path then
        t.options = vim.tbl_extend("force", t.options or {}, { cwd = dir .. "/" .. t.path })
      end
    elseif (t.type == "shell" or t.type == "process" or t.type == nil) and type(t.command) == "string" then
      cmd = table.concat(vim.list_extend({ vscode_vars(t.command, dir) }, vscode_args(t.args, dir)), " ")
    end
    local name = t.label or t.script or cmd
    if cmd and name then
      local cwd = type(t.options) == "table" and t.options.cwd
      add(name, cmd, cwd and vim.fs.normalize(vscode_vars(cwd, dir)) or nil)
    end
  end
end

local markers = {
  [".vscode"] = function(name, path)
    -- `path` is the folder holding the item on some Neovim versions, the item itself on others
    local dir = path:find("[/\\]%.vscode$") and path or (path .. "/.vscode")
    return name == ".vscode" and vim.uv.fs_stat(dir .. "/tasks.json") ~= nil
  end,
  ["package.json"] = "package.json",
  ["deno.json"] = { "deno.json", "deno.jsonc" },
  ["Makefile"] = "Makefile",
  ["justfile"] = { "justfile", "Justfile", ".justfile" },
  ["Cargo.toml"] = "Cargo.toml",
  ["go.mod"] = "go.mod",
  ["pyproject.toml"] = "pyproject.toml",
  ["composer.json"] = "composer.json",
  ["mix.exs"] = "mix.exs",
  ["gradlew"] = "gradlew",
  ["pom.xml"] = "pom.xml",
  ["build.zig"] = "build.zig",
  ["CMakeLists.txt"] = "CMakeLists.txt",
  ["compose"] = { "compose.yaml", "compose.yml", "docker-compose.yml", "docker-compose.yaml" },
  ["dotnet"] = function(name)
    return name:match("%.sln$") or name:match("%.csproj$") or name:match("%.fsproj$")
  end,
}

---@param buf? integer
---@return lumen.Task[]
function M.discover(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  local tasks = {}
  local function collect(source, dir)
    local ok, err = pcall(providers[source], dir, function(name, cmd, cwd)
      tasks[#tasks + 1] = { name = name, cmd = cmd, cwd = cwd or dir, source = source }
    end)
    if not ok then
      Lumen.warn(("tasks: %s provider failed: %s"):format(source, err))
    end
  end
  for source, marker in pairs(markers) do
    local dir = find(buf, marker)
    if dir then
      collect(source, dir)
    end
  end
  for _, t in ipairs(require("lumen.config").tasks or {}) do
    -- `{ name = "x", command = "…" }` or a plain string would crash the picker later: skip it
    if type(t) == "table" and type(t.cmd) == "string" then
      tasks[#tasks + 1] = { name = t.name or t.cmd, cmd = t.cmd, cwd = t.cwd or Lumen.root(), source = "config" }
    elseif not M._warned_bad then
      M._warned_bad = true
      Lumen.warn(
        'tasks: each entry in `tasks = {}` needs a `cmd` string, e.g. { name = "deploy", cmd = "./deploy.sh" }'
      )
    end
  end
  local project = require("lumen.project")
  for _, t in ipairs(project.tasks()) do
    if type(t) == "table" and type(t.cmd) == "string" then
      local cwd = t.cwd and vim.fs.normalize(t.cwd) or project.root()
      -- relative to the .lumen.lua, not to wherever Neovim was started
      if cwd and not cwd:find("^/") and project.root() then
        cwd = project.root() .. "/" .. cwd
      end
      tasks[#tasks + 1] = { name = t.name or t.cmd, cmd = t.cmd, cwd = cwd or Lumen.root(), source = "project" }
    end
  end
  table.sort(tasks, function(a, b)
    if a.source ~= b.source then
      return a.source < b.source
    end
    return a.name < b.name
  end)
  return tasks
end

-- ── last task per project ────────────────────────────────────

local function last_all()
  return json(state_file) or {}
end

function M.last()
  return last_all()[Lumen.root()]
end

local function remember(task, mode)
  local all = last_all()
  all[Lumen.root()] = vim.tbl_extend("force", task, { mode = mode })
  vim.fn.mkdir(vim.fn.fnamemodify(state_file, ":h"), "p")
  local f = io.open(state_file, "w")
  if f then
    f:write(vim.json.encode(all))
    f:close()
  end
end

-- ── running ──────────────────────────────────────────────────

local term ---@type snacks.win?
local term_win ---@type integer?

local function esc(s)
  return (s:gsub("%%", "%%%%"))
end

-- `cwd = "~/proj"` from the user's config: neither vim.system nor the terminal expand `~`
---@param task lumen.Task
local function normalize(task)
  return vim.tbl_extend("force", task, { cwd = vim.fs.normalize(task.cwd) })
end

---@param task lumen.Task
function M.run_terminal(task)
  task = normalize(task)
  remember(task, "terminal")
  local winbar = ("%%#LumenWinbarFile#  %s  %%#LumenWinbar#%s"):format(esc(task.name), esc(task.cmd))
  if not _G.Snacks then
    -- snacks.nvim disabled: a plain terminal split at the bottom
    if term_win and vim.api.nvim_win_is_valid(term_win) then
      vim.api.nvim_win_close(term_win, true)
    end
    vim.cmd("botright " .. math.max(8, math.floor(vim.o.lines * 0.3)) .. "new")
    term_win = vim.api.nvim_get_current_win()
    vim.wo[term_win].winbar = winbar
    vim.fn.jobstart(task.cmd, { term = true, cwd = task.cwd })
    vim.bo.bufhidden = "wipe"
    return
  end
  if term and term:valid() then
    term:close()
  end
  term = Snacks.terminal.open(task.cmd, {
    cwd = task.cwd,
    auto_close = false,
    start_insert = false,
    auto_insert = false,
    win = {
      position = "bottom",
      height = 0.3,
      title = (" %s "):format(task.name),
      -- both are statusline text: a raw `%` (e.g. `date +%s`) would be eaten or error
      wo = { winbar = winbar },
    },
  })
end

-- extra errorformats on top of 'errorformat': tsc (plain and pretty), rustc/cargo (the location
-- is on a ` --> file:line:col` line after the message), python tracebacks, then the defaults
-- (gcc/clang/go/eslint-unix/ruff all use file:line:col: message)
-- (global value on purpose: buffer-local ones, e.g. cargo's, can't parse other tools)
local DIR_MARK = "lumen-task-dir: "
local function efm()
  return table.concat({
    "%D" .. DIR_MARK .. "%f",
    "%f(%l\\,%c): %trror TS%n: %m",
    "%f:%l:%c - %trror TS%n: %m",
    "%E%trror[E%n]: %m",
    "%W%tarning[%.%#]: %m",
    "%E%trror: %m",
    "%W%tarning: %m",
    "%C%*\\s--> %f:%l:%c",
    "%-C%*\\s|%.%#",
    "%-C%*\\d%*\\s|%.%#",
    "%-C%*\\s= %.%#",
    '%*\\sFile "%f"\\, line %l\\, %m',
    vim.go.errorformat,
  }, ",")
end
M._efm = efm -- for tests

---@param task lumen.Task
function M.run_background(task)
  task = normalize(task)
  remember(task, "background")
  local id = task.cwd .. task.cmd
  if M.running[id] then
    return Lumen.warn(task.name .. " is already running")
  end
  M.running[id] = { name = task.name, started = vim.uv.hrtime() }
  -- animate the statusline spinner while anything runs
  if not M._timer then
    -- ticks are queued via schedule_wrap, so a stale one can run after the timer was closed
    local timer = assert(vim.uv.new_timer())
    M._timer = timer
    timer:start(
      0,
      120,
      vim.schedule_wrap(function()
        if timer:is_closing() then
          return
        end
        vim.cmd.redrawstatus()
        if not next(M.running) then
          timer:stop()
          timer:close()
          if M._timer == timer then
            M._timer = nil
          end
        end
      end)
    )
  end
  -- 'shellcmdflag', not a fixed `-c`: cmd.exe wants `/s /c`, PowerShell `-Command`
  local argv = { vim.o.shell }
  vim.list_extend(argv, vim.split(vim.o.shellcmdflag, "%s+", { trimempty = true }))
  argv[#argv + 1] = task.cmd
  -- vim.system throws right away for a missing cwd or shell: don't leave the task "running"
  local ok, err = pcall(vim.system, argv, { cwd = task.cwd, text = true }, function(out)
    vim.schedule(function()
      local secs = (vim.uv.hrtime() - M.running[id].started) / 1e9
      M.running[id] = nil
      vim.cmd.redrawstatus()
      -- split the streams apart: stdout without a final newline must not swallow stderr's first line
      -- relative paths are relative to the task's folder, not Neovim's cwd: the first line puts
      -- it on 'errorformat's directory stack (%D in efm())
      local lines = { DIR_MARK .. task.cwd }
      vim.list_extend(lines, vim.split(out.stdout or "", "\n", { trimempty = true }))
      vim.list_extend(lines, vim.split(out.stderr or "", "\n", { trimempty = true }))
      vim.fn.setqflist({}, " ", { title = task.name, lines = lines, efm = efm() })
      -- summaries such as cargo's "error: could not compile" parse as entries without a file
      local items, valid = vim.fn.getqflist(), 0
      -- the directory line (always the first) leaves an invalid entry of its own
      if items[1] and items[1].valid == 0 then
        table.remove(items, 1)
      end
      for _, e in ipairs(items) do
        if e.valid == 1 and e.bufnr == 0 then
          e.valid = 0
        end
        valid = valid + e.valid
      end
      vim.fn.setqflist({}, "r", { items = items })
      if out.code == 0 then
        Lumen.notify(("✓ %s finished in %.1fs"):format(task.name, secs))
      else
        vim.notify(
          ("✗ %s failed (exit %d) after %.1fs — %d locations in quickfix"):format(task.name, out.code, secs, valid),
          vim.log.levels.ERROR,
          { title = "Lumen" }
        )
        vim.cmd("botright copen")
      end
    end)
  end)
  if not ok then
    M.running[id] = nil
    Lumen.error(("%s: %s"):format(task.name, err))
  end
end

function M.status()
  local names = {}
  for _, r in pairs(M.running) do
    names[#names + 1] = r.name
  end
  return table.concat(names, ", ")
end

-- ── watch: re-run a task in the background whenever a file in its project is saved ──

---@type lumen.Task?
M.watching = nil
local watch_group

---@param task? lumen.Task the task to watch (default: the project's last task); nil toggles off
function M.watch(task)
  if watch_group then
    vim.api.nvim_del_augroup_by_id(watch_group)
    watch_group = nil
    local was = M.watching
    M.watching = nil
    vim.cmd.redrawstatus()
    if not task then
      return Lumen.notify(("Stopped watching %s"):format(was and was.name or "the task"))
    end
  end
  task = task or M.last()
  if not task then
    return Lumen.warn("No task to watch yet — run one first (<leader>rt)")
  end
  task = normalize(task)
  M.watching = task
  watch_group = vim.api.nvim_create_augroup("lumen_task_watch", { clear = true })
  vim.api.nvim_create_autocmd("BufWritePost", {
    group = watch_group,
    callback = function(ev)
      local file = vim.fs.normalize(vim.fn.fnamemodify(ev.match, ":p"))
      -- only saves inside the task's folder; a second save while it runs is skipped
      if file:sub(1, #task.cwd + 1) == task.cwd .. "/" and not M.running[task.cwd .. task.cmd] then
        M.run_background(task)
      end
    end,
  })
  vim.cmd.redrawstatus()
  Lumen.notify(("Watching: `%s` re-runs on every save in %s"):format(task.name, vim.fn.fnamemodify(task.cwd, ":~")))
end

---@param task lumen.Task
---@param mode? "terminal"|"background"
function M.run(task, mode)
  if mode == "background" then
    M.run_background(task)
  else
    M.run_terminal(task)
  end
end

function M.rerun()
  local last = M.last()
  if not last then
    return M.pick()
  end
  M.run(last, last.mode)
end

function M.pick()
  local tasks = M.discover()
  if #tasks == 0 then
    return Lumen.warn("No tasks found for this project — add your own with `tasks = {}` in lua/config/lumen.lua")
  end
  local last = M.last()
  local root = Lumen.root()
  local items = {}
  for _, t in ipairs(tasks) do
    local is_last = last and last.cmd == t.cmd and last.cwd == t.cwd
    local where = t.cwd == root and "" or ("  " .. vim.fn.fnamemodify(t.cwd, ":."))
    items[#items + 1] = {
      text = t.name .. " " .. t.cmd .. " " .. t.source,
      task = t,
      last = is_last,
      score_add = is_last and 1000 or 0,
      preview = { text = ("# %s  (%s)\ncd %s\n%s\n"):format(t.name, t.source, t.cwd, t.cmd), ft = "sh" },
      where = where,
    }
  end
  if not _G.Snacks then
    -- snacks.nvim disabled: the plain vim.ui.select list
    return vim.ui.select(items, {
      prompt = "Run task",
      format_item = function(item)
        return ("%s%-26s %-15s %s%s"):format(
          item.last and "↻ " or "  ",
          item.task.name,
          item.task.source,
          item.task.cmd,
          item.where
        )
      end,
    }, function(item)
      if item then
        M.run_terminal(item.task)
      end
    end)
  end
  Snacks.picker({
    title = "Tasks",
    items = items,
    preview = "preview",
    layout = { preset = "select", layout = { width = 0.6 } },
    format = function(item)
      return {
        { item.last and "↻ " or "  ", "LumenStlModified" },
        { ("%-26s"):format(item.task.name), "SnacksPickerFile" },
        { ("%-15s"):format(item.task.source), "SnacksPickerDir" },
        { item.task.cmd, "Comment" },
        { item.where, "SnacksPickerDir" },
      }
    end,
    win = {
      input = {
        keys = {
          ["<c-q>"] = { "task_background", mode = { "n", "i" }, desc = "Run in background → quickfix" },
          ["<c-e>"] = { "task_edit", mode = { "n", "i" }, desc = "Edit command, then run" },
        },
      },
    },
    actions = {
      task_background = function(picker, item)
        picker:close()
        if item then
          M.run_background(item.task)
        end
      end,
      task_edit = function(picker, item)
        picker:close()
        if not item then
          return
        end
        vim.ui.input({ prompt = "Run: ", default = item.task.cmd }, function(cmd)
          if cmd and cmd ~= "" then
            M.run_terminal(vim.tbl_extend("force", item.task, { cmd = cmd, name = cmd }))
          end
        end)
      end,
    },
    confirm = function(picker, item)
      picker:close()
      if item then
        M.run_terminal(item.task)
      end
    end,
  })
end

return M
