-- Task runner: discovers project tasks and runs them in a terminal split or in the
-- background (errors → quickfix). The last task per project is one key away.
--
-- Sources: package.json (npm/pnpm/yarn/bun), deno.json, Makefile, justfile, Cargo,
-- go, uv/pytest, composer, mix, gradle, maven, dotnet, zig, cmake, docker compose,
-- plus `tasks = {}` from lua/config/lumen.lua.

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

local function json(path)
  local s = read(path)
  if not s then
    return
  end
  local ok, data = pcall(vim.json.decode, s, { luanil = { object = true, array = true } })
  return ok and data or nil
end

---@param buf integer
---@param markers string|string[]
local function find(buf, markers)
  local dir = vim.fs.root(buf, markers)
  return dir and vim.fs.normalize(dir) or nil
end

---@type table<string, fun(dir:string, add:fun(name:string, cmd:string))>
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
    add(name, pm .. " " .. name)
  end
end

providers["deno.json"] = function(dir, add)
  local cfg = json(dir .. "/deno.json") or json(dir .. "/deno.jsonc") or {}
  for name in pairs(cfg.tasks or {}) do
    add(name, "deno task " .. name)
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
    add(name, "composer run " .. name)
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

local markers = {
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
    local ok, err = pcall(providers[source], dir, function(name, cmd)
      tasks[#tasks + 1] = { name = name, cmd = cmd, cwd = dir, source = source }
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
    tasks[#tasks + 1] = { name = t.name or t.cmd, cmd = t.cmd, cwd = t.cwd or Lumen.root(), source = "config" }
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
      wo = { winbar = ("%%#LumenWinbarFile#  %s  %%#LumenWinbar#%s"):format(esc(task.name), esc(task.cmd)) },
    },
  })
end

-- extra errorformats on top of 'errorformat': tsc (plain and pretty), rustc/cargo (the location
-- is on a ` --> file:line:col` line after the message), python tracebacks, then the defaults
-- (gcc/clang/go/eslint-unix/ruff all use file:line:col: message)
-- (global value on purpose: buffer-local ones, e.g. cargo's, can't parse other tools)
local function efm()
  return table.concat({
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
  local shell = vim.o.shell
  -- vim.system throws right away for a missing cwd or shell: don't leave the task "running"
  local ok, err = pcall(vim.system, { shell, "-c", task.cmd }, { cwd = task.cwd, text = true }, function(out)
    vim.schedule(function()
      local secs = (vim.uv.hrtime() - M.running[id].started) / 1e9
      M.running[id] = nil
      vim.cmd.redrawstatus()
      -- split the streams apart: stdout without a final newline must not swallow stderr's first line
      local lines = vim.split(out.stdout or "", "\n", { trimempty = true })
      vim.list_extend(lines, vim.split(out.stderr or "", "\n", { trimempty = true }))
      vim.fn.setqflist({}, " ", { title = task.name, lines = lines, efm = efm() })
      -- summaries such as cargo's "error: could not compile" parse as entries without a file
      local items, valid = vim.fn.getqflist(), 0
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
