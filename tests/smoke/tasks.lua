-- Task runner: discovery, background runs, quickfix (run by tests/smoke.lua)
---@param t lumen.test.Helpers
return function(t)
  local check, wait, child, fake_server, SLOW = t.check, t.wait, t.child, t.fake_server, t.SLOW

  check("tasks: discovery across ecosystems", function()
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir .. "/sub", "p")
    local function write(name, text)
      local f = assert(io.open(dir .. "/" .. name, "w"))
      f:write(text)
      f:close()
    end
    write(".git", "")
    write("package.json", '{"scripts":{"dev":"vite","test":"vitest"}}')
    write("pnpm-lock.yaml", "")
    write("Makefile", "build:\n\tcc main.c\nclean: \n\trm -f a.out\n.PHONY: build\n")
    write("go.mod", "module x\n")
    write("sub/Cargo.toml", "[package]\nname='x'\n")
    vim.cmd.edit(dir .. "/sub/main.rs")
    local by = {}
    for _, t in ipairs(require("lumen.tasks").discover()) do
      by[t.source .. ":" .. t.name] = t
    end
    assert(by["package.json:dev"] and by["package.json:dev"].cmd == "pnpm run dev", "pnpm script not detected")
    assert(by["Makefile:build"] and by["Makefile:clean"], "make targets missing")
    assert(by["go.mod:test"], "go tasks missing")
    assert(by["Cargo.toml:test"] and by["Cargo.toml:test"].cwd:find("/sub$"), "nearest Cargo.toml not used")
    vim.cmd("bwipeout!")
  end)

  check("tasks: background run fills quickfix", function()
    vim.fn.setqflist({}, "r")
    local task = { name = "fail", cmd = "echo 'init.lua:3:5: boom'; exit 2", cwd = vim.fn.getcwd(), source = "test" }
    require("lumen.tasks").run_background(task)
    assert(
      wait(5000 * SLOW, function()
        return #vim.fn.getqflist() > 0 and not next(require("lumen.tasks").running)
      end),
      "task did not finish"
    )
    local e = vim.fn.getqflist()[1]
    assert(e.valid == 1 and e.lnum == 3 and e.col == 5, "error not parsed: " .. vim.inspect(e))
    assert(require("lumen.tasks").last().cmd == task.cmd, "last task not remembered")
    vim.cmd("cclose")
  end)

  check("tasks: escaping, bad cwd, stream order, rustc / python locations", function()
    local tasks = require("lumen.tasks")
    -- `%` in a task name / command must not be eaten by the terminal winbar
    tasks.run_terminal({ name = "date +%s", cmd = "date +%s", cwd = vim.fn.getcwd(), source = "config" })
    local win = vim.api.nvim_get_current_win()
    local bar = vim.api.nvim_eval_statusline(vim.wo[win].winbar, { winid = win, use_winbar = true }).str
    vim.api.nvim_win_close(win, true)
    assert(select(2, bar:gsub("date %+%%s", "")) == 2, "winbar: " .. bar)
    -- a missing cwd used to throw and leave the task "running" forever
    local notify = vim.notify
    vim.notify = function() end
    local ok, err =
      pcall(tasks.run_background, { name = "bad", cmd = "true", cwd = "/nonexistent/lumen", source = "x" })
    vim.notify = notify
    assert(ok, err)
    assert(not next(tasks.running), "task stuck in running")
    -- stdout without a final newline must not swallow stderr's first line; `~` cwd expands
    tasks.run_background({
      name = "streams",
      cmd = "printf 'out.c:1:1: error: a'; printf 'err.c:2:3: error: b' >&2; exit 1",
      cwd = "~",
      source = "x",
    })
    assert(wait(5000, function()
      return not next(tasks.running)
    end))
    vim.cmd("cclose")
    local files = vim.tbl_map(function(e)
      return vim.fn.fnamemodify(vim.fn.bufname(e.bufnr), ":t")
    end, vim.fn.getqflist())
    assert(vim.deep_equal(files, { "out.c", "err.c" }), vim.inspect(files))
    -- rustc puts the location on a " --> file:line:col" line; python tracebacks use File "x", line n
    vim.fn.setqflist({}, " ", {
      efm = tasks._efm(),
      lines = {
        "error[E0425]: cannot find value `x` in this scope",
        " --> src/main.rs:2:13",
        "  |",
        '  File "app/x.py", line 3, in <module>',
      },
    })
    local got = vim.tbl_map(
      function(e)
        return ("%s:%d:%d"):format(vim.fn.bufname(e.bufnr), e.lnum, e.col)
      end,
      vim.tbl_filter(function(e)
        return e.valid == 1
      end, vim.fn.getqflist())
    )
    assert(vim.deep_equal(got, { "src/main.rs:2:13", "app/x.py:3:0" }), vim.inspect(got))
    vim.fn.setqflist({}, "r", { items = {} })
  end)

  check("tasks: deno.jsonc with comments and trailing commas", function()
    local tasks = require("lumen.tasks")
    local text = '{\n  // tasks\n  "tasks": { "dev": "deno run -A main.ts", /* serve */ "url": "http://x//y", },\n}\n'
    local data = vim.json.decode(tasks.strip_jsonc(text))
    assert(data.tasks.dev == "deno run -A main.ts", vim.inspect(data))
    assert(data.tasks.url == "http://x//y", "a // inside a string was treated as a comment")
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir, "p")
    vim.fn.writefile(vim.split(text, "\n"), dir .. "/deno.jsonc")
    vim.cmd.edit(dir .. "/main.ts")
    local found = vim.tbl_filter(function(t)
      return t.cmd == "deno task dev"
    end, tasks.discover())
    vim.cmd("bwipeout!")
    assert(#found == 1, "deno.jsonc task not discovered")
  end)

  check("tasks: picker and terminal work with snacks.nvim disabled", function()
    local probe = [[
      vim.defer_fn(function()
        local tasks = require("lumen.tasks")
        local listed
        vim.ui.select = function(items, _, cb) listed = #items cb(items[1]) end
        tasks.discover = function()
          return { { name = "hello", cmd = "echo hello-from-task", cwd = vim.uv.cwd(), source = "test" } }
        end
        local ok, err = pcall(tasks.pick)
        vim.wait(3000, function() return vim.bo.buftype == "terminal" end, 50)
        io.stdout:write(vim.json.encode({ ok = ok, err = tostring(err), listed = listed, term = vim.bo.buftype == "terminal",
          snacks = _G.Snacks ~= nil }) .. "\n")
        vim.cmd("qa!")
      end, 500)
    ]]
    local res, out =
      child(probe, { ["lua/plugins/zz_no_snacks.lua"] = 'return { { "folke/snacks.nvim", enabled = false } }' })
    assert(res.snacks == false, "snacks still loaded: " .. vim.inspect(res) .. (out.stderr or ""))
    assert(res.ok, "tasks.pick failed without snacks: " .. tostring(res.err))
    assert(res.listed == 1 and res.term, "no task list / terminal: " .. vim.inspect(res))
  end)

  check("tasks: .vscode/tasks.json (shell, process, npm, variables, cwd, per-OS fields)", function()
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir .. "/.vscode", "p")
    vim.fn.mkdir(dir .. "/web", "p")
    vim.fn.writefile(
      vim.split(
        [[
{
  // VS Code allows comments and trailing commas here
  "version": "2.0.0",
  "tasks": [
    { "label": "build", "type": "shell", "command": "make", "args": ["-C", "${workspaceFolder}/src", "all"] },
    {
      "label": "lint file",
      "type": "process",
      "command": "eslint",
      "args": ["${relativeFile}", "two words"],
      "options": { "cwd": "${workspaceFolder}/web" },
    },
    { "type": "npm", "script": "dev", "path": "web" },
    { "label": "per os", "command": "echo other", "osx": { "command": "echo os" }, "linux": { "command": "echo os" } },
    { "label": "no command", "type": "shell" },
  ],
}
]],
        "\n"
      ),
      dir .. "/.vscode/tasks.json"
    )
    vim.cmd.edit(dir .. "/web/app.js")
    local by = {}
    for _, t in ipairs(require("lumen.tasks").discover()) do
      if t.source == ".vscode" then
        by[t.name] = t
      end
    end
    local root = vim.fs.root(0, ".vscode")
    assert(by.build and by.build.cmd == ("make -C %s/src all"):format(root), vim.inspect(by.build))
    assert(by.build.cwd == root, "default cwd is the workspace folder: " .. tostring(by.build.cwd))
    local lint = by["lint file"]
    assert(lint and lint.cmd == "eslint web/app.js 'two words'", vim.inspect(lint))
    assert(lint.cwd == root .. "/web", "options.cwd not used: " .. lint.cwd)
    assert(by.dev and by.dev.cmd == "npm run dev" and by.dev.cwd == root .. "/web", vim.inspect(by.dev))
    assert(by["per os"] and by["per os"].cmd == "echo os", vim.inspect(by["per os"]))
    assert(not by["no command"], "a task without a command was listed")
    vim.cmd("bwipeout!")
    vim.fn.delete(dir, "rf")
  end)

  check("tasks: watch re-runs the task when a file in its folder is saved", function()
    local tasks = require("lumen.tasks")
    local dir = vim.fs.normalize(vim.fn.tempname())
    vim.fn.mkdir(dir, "p")
    local runs, orig = 0, tasks.run_background
    tasks.run_background = function()
      runs = runs + 1
    end
    local ok, err = pcall(function()
      tasks.watch({ name = "unit", cmd = "true", cwd = dir, source = "test" })
      assert(tasks.watching and tasks.watching.name == "unit", "not watching")
      assert(require("lumen.ui.statusline").render():find("unit", 1, true), "statusline doesn't show the watch")
      vim.cmd.edit(dir .. "/a.txt")
      vim.cmd.write()
      assert(runs == 1, "a save inside the folder didn't re-run the task")
      local outside = vim.fn.tempname()
      vim.cmd.edit(outside)
      vim.cmd.write()
      assert(runs == 1, "a save outside the folder re-ran the task")
      tasks.watch() -- toggles off
      assert(tasks.watching == nil, "still watching")
      vim.cmd.edit(dir .. "/a.txt")
      vim.cmd.write()
      assert(runs == 1, "the watch kept running after it was turned off")
      vim.cmd("bwipeout! " .. vim.fn.fnameescape(outside))
      os.remove(outside)
    end)
    tasks.run_background = orig
    if tasks.watching then
      tasks.watch()
    end
    pcall(vim.cmd, "bwipeout!")
    vim.fn.delete(dir, "rf")
    assert(ok, err)
  end)
end
