-- Headless smoke test. Run with scripts/test.sh (isolated XDG dirs, never touches your config).
local failures, passes = {}, 0
-- shared CI runners are slower and download servers on first use: stretch time limits there
local SLOW = vim.env.CI and 4 or 1

local function check(name, fn)
  local ok, err = pcall(fn)
  if ok then
    passes = passes + 1
    io.stdout:write("  ✓ " .. name .. "\n")
  else
    failures[#failures + 1] = name
    io.stdout:write("  ✗ " .. name .. "\n      " .. tostring(err):gsub("\n", "\n      ") .. "\n")
  end
end

local function wait(ms, cond)
  return vim.wait(ms, cond, 50)
end

--- Starts an in-process fake language server `name` with `capabilities` for `buf`
---@return integer client_id
local function fake_server(name, capabilities, buf)
  return assert(vim.lsp.start({
    name = name,
    cmd = function()
      return {
        request = function(method, _, callback)
          if method == "initialize" then
            callback(nil, { capabilities = capabilities })
          end
          return true, 1
        end,
        notify = function()
          return true
        end,
        is_closing = function()
          return false
        end,
        terminate = function() end,
      }
    end,
  }, { bufnr = buf }))
end

--- Runs `probe` (Lua source; it must print one JSON object and quit) in a child Neovim using a
--- throwaway copy of the sandbox config with `files` added (e.g. `lua/plugins/x.lua`), so the
--- running suite never sees those specs. Returns the decoded JSON plus the raw result.
---@param probe string
---@param files? table<string, string> path (relative to the config dir) → contents
---@param args? string[] extra arguments for the child
local function child(probe, files, args)
  local cfg = vim.fn.stdpath("config")
  local root = vim.fn.tempname()
  local dir = root .. "/" .. vim.fn.fnamemodify(cfg, ":t")
  vim.fn.mkdir(dir, "p")
  vim.fn.system({ "cp", "-R", cfg .. "/.", dir })
  for path, text in pairs(files or {}) do
    vim.fn.mkdir(vim.fn.fnamemodify(dir .. "/" .. path, ":h"), "p")
    vim.fn.writefile(vim.split(text, "\n"), dir .. "/" .. path)
  end
  local cmd = { vim.v.progpath, "--headless", "-c", "lua " .. probe:gsub("\n", " ") }
  vim.list_extend(cmd, args or {})
  local out = vim.system(cmd, { text = true, env = { XDG_CONFIG_HOME = root } }):wait(60000 * SLOW)
  vim.fn.delete(root, "rf")
  return vim.json.decode((out.stdout or ""):match("{.*}") or "{}"), out
end

local function run()
  io.stdout:write("\nLumen smoke test\n")

  check("colorscheme loads", function()
    assert(vim.g.colors_name == "lumen", "colors_name = " .. tostring(vim.g.colors_name))
    for _, g in ipairs({ "LumenStl", "LumenTabActive", "LumenWinbar", "LumenFoldCount", "MCursor", "SnacksPickerMatch" }) do
      assert(next(vim.api.nvim_get_hl(0, { name = g })), "missing highlight " .. g)
    end
  end)

  check("dawn variant + background toggle", function()
    vim.o.background = "light"
    assert(
      wait(1000 * SLOW, function()
        return vim.api.nvim_get_hl(0, { name = "Normal" }).bg == tonumber("f7f3eb", 16)
      end),
      "dawn not applied"
    )
    vim.o.background = "dark"
    assert(
      wait(1000 * SLOW, function()
        return vim.api.nvim_get_hl(0, { name = "Normal" }).bg == tonumber("10131a", 16)
      end),
      "night not restored"
    )
  end)

  check("accent + on_highlights", function()
    local config = require("lumen.config")
    config.accent = "violet"
    config.on_highlights = function(hl, p)
      hl.LumenTest = { fg = p.teal }
    end
    vim.cmd.colorscheme("lumen")
    local p = require("lumen.colors.palettes").night
    assert(vim.api.nvim_get_hl(0, { name = "CursorLineNr" }).fg == tonumber(p.violet:sub(2), 16), "accent not applied")
    assert(
      vim.api.nvim_get_hl(0, { name = "LumenTest" }).fg == tonumber(p.teal:sub(2), 16),
      "on_highlights not applied"
    )
    config.accent, config.on_highlights = "amber", nil
    vim.cmd.colorscheme("lumen")
  end)

  check("a bad on_highlights group doesn't break the theme or the background toggle", function()
    local config = require("lumen.config")
    config.on_highlights = function(hl)
      hl.LumenBad = { fg = "not-a-color" }
    end
    local ok, err = pcall(vim.cmd.colorscheme, "lumen")
    config.on_highlights = nil
    assert(ok, "colorscheme failed: " .. tostring(err))
    assert(vim.g.colors_name == "lumen", "colors_name = " .. tostring(vim.g.colors_name))
    vim.o.background = "light"
    assert(
      wait(1000 * SLOW, function()
        return vim.api.nvim_get_hl(0, { name = "Normal" }).bg == tonumber("f7f3eb", 16)
      end),
      "background toggle stuck after a failed load"
    )
    vim.o.background = "dark"
    vim.cmd.colorscheme("lumen")
  end)

  check("invalid palette overrides / accent are ignored with a warning", function()
    local config = require("lumen.config")
    local notify, warned = vim.notify, nil
    vim.notify = function(msg)
      warned = msg
    end
    config.colors, config.accent = { night = { bg = "black", red = "#ff0000" } }, "pinkish"
    local ok, err = pcall(vim.cmd.colorscheme, "lumen")
    wait(200, function()
      return warned ~= nil
    end)
    vim.notify, config.colors, config.accent = notify, {}, "amber"
    local normal, error_fg = vim.api.nvim_get_hl(0, { name = "Normal" }).bg, vim.api.nvim_get_hl(0, { name = "Error" })
    vim.cmd.colorscheme("lumen")
    assert(ok, "colorscheme failed: " .. tostring(err))
    assert(normal == tonumber("10131a", 16), "invalid bg not ignored")
    assert(next(error_fg), "valid override broke a group")
    assert(warned and warned:find("colors.night.bg", 1, true) and warned:find("pinkish", 1, true), tostring(warned))
  end)

  check("background toggle under lumen-dawn / lumen-night switches variant", function()
    -- Neovim unloads a scheme that sets 'background' back (colors_name = nil, default colors)
    for _, case in ipairs({ { "lumen-dawn", "dark", "10131a" }, { "lumen-night", "light", "f7f3eb" } }) do
      vim.cmd.colorscheme(case[1])
      vim.o.background = case[2]
      assert(
        wait(1000 * SLOW, function()
          return vim.g.colors_name == "lumen"
            and vim.api.nvim_get_hl(0, { name = "Normal" }).bg == tonumber(case[3], 16)
        end),
        ("%s + background=%s: colors_name=%s"):format(case[1], case[2], tostring(vim.g.colors_name))
      )
    end
    vim.o.background = "dark"
    vim.cmd.colorscheme("lumen")
  end)

  check("catppuccin is selectable and Lumen UI adapts", function()
    local names = vim.tbl_map(function(i)
      return i.text
    end, require("snacks.picker.source.vim").colorschemes())
    for _, want in ipairs({ "catppuccin", "catppuccin-mocha", "catppuccin-latte", "lumen", "lumen-dawn" }) do
      assert(vim.tbl_contains(names, want), want .. " missing from colorscheme picker")
    end
    vim.cmd.colorscheme("catppuccin-mocha")
    local mocha = require("catppuccin.palettes").get_palette("mocha")
    local stl = vim.api.nvim_get_hl(0, { name = "LumenStl", link = false })
    assert(stl.bg == tonumber(mocha.mantle:sub(2), 16), "statusline not adapted to catppuccin")
    local mode = vim.api.nvim_get_hl(0, { name = "LumenStlModeNormal", link = false })
    assert(mode.bg == tonumber(mocha.mauve:sub(2), 16), "accent should be catppuccin mauve")
    -- any other scheme gets derived colors
    vim.cmd.colorscheme("habamax")
    assert(next(vim.api.nvim_get_hl(0, { name = "LumenTabActive" })), "tabline groups missing under habamax")
    vim.cmd.colorscheme("lumen")
    assert(vim.api.nvim_get_hl(0, { name = "Normal" }).bg == tonumber("10131a", 16), "lumen not restored")
  end)

  check("treesitter highlights the buffer", function()
    assert(wait(5000 * SLOW, function()
      return vim.treesitter.highlighter.active[vim.api.nvim_get_current_buf()] ~= nil
    end))
  end)

  check("statusline / tabline / winbar render", function()
    for _, mod in ipairs({ "statusline", "tabline", "winbar" }) do
      local s = require("lumen.ui." .. mod).render()
      assert(type(s) == "string", mod .. " returned " .. type(s))
    end
    assert(require("lumen.ui.statusline").render():find("NORMAL"), "mode missing")
    assert(require("lumen.ui.tabline").render():find("init.lua", 1, true), "buffer missing from tabline")
  end)

  check("statusline: long LSP progress is cut by characters and stays escaped", function()
    local status, columns = vim.lsp.status, vim.o.columns
    vim.o.columns = 160 -- the LSP section only shows on wide screens
    local function render(msg)
      vim.lsp.status = function()
        return msg
      end
      local ok, res = pcall(vim.api.nvim_eval_statusline, require("lumen.ui.statusline").render(), {})
      vim.lsp.status = status
      assert(ok, res)
      return res.str
    end
    local ok, err = pcall(function()
      -- a cut "%%" used to leave a lone "%" that ate the "…"
      local s = render(string.rep("a", 38) .. "50%: indexing workspace")
      assert(s:find(string.rep("a", 38) .. "5…", 1, true), s)
      -- a byte cut used to split a multibyte character
      s = render(string.rep("é", 50))
      assert(s:find(string.rep("é", 39) .. "…", 1, true), s)
    end)
    vim.lsp.status, vim.o.columns = status, columns
    assert(ok, err)
  end)

  check("statusline: a narrow screen cuts the path, not the mode", function()
    local columns = vim.o.columns
    vim.o.columns = 40
    local ok, res = pcall(vim.api.nvim_eval_statusline, require("lumen.ui.statusline").render(), { maxwidth = 40 })
    vim.o.columns = columns
    assert(ok, res)
    assert(res.str:find("NORMAL", 1, true), res.str)
  end)

  check("tabline: duplicate names are disambiguated, tabpages stay visible", function()
    local cur = vim.api.nvim_get_current_buf()
    local a = vim.fn.bufadd("/tmp/lumen-smoke/a/src/util.lua")
    local b = vim.fn.bufadd("/tmp/lumen-smoke/b/src/util.lua")
    local n1, n2 = vim.api.nvim_create_buf(true, false), vim.api.nvim_create_buf(true, false)
    for _, buf in ipairs({ a, b }) do
      vim.bo[buf].buflisted = true
    end
    local str = vim.api.nvim_eval_statusline(require("lumen.ui.tabline").render(), { use_tabline = true }).str
    for _, buf in ipairs({ a, b, n1, n2 }) do
      vim.api.nvim_buf_delete(buf, { force = true })
    end
    assert(str:find("a/src/util.lua", 1, true) and str:find("b/src/util.lua", 1, true), str)
    assert(not str:find("./[No Name]", 1, true), str)
    assert(vim.api.nvim_get_current_buf() == cur)
    -- several tabpages but no file buffer: the tabline must still show them
    local listed = vim.tbl_filter(function(buf)
      return vim.bo[buf].buflisted
    end, vim.api.nvim_list_bufs())
    for _, buf in ipairs(listed) do
      vim.bo[buf].buflisted = false
    end
    vim.cmd("tab split")
    local shown = wait(1000, function()
      return vim.o.showtabline == 2
    end)
    vim.cmd("tabclose")
    for _, buf in ipairs(listed) do
      vim.bo[buf].buflisted = true
    end
    assert(shown, "tabline hidden with 2 tabpages")
  end)

  check("lua_ls attaches + winbar shows symbols", function()
    assert(
      wait(30000 * SLOW, function()
        return #vim.lsp.get_clients({ bufnr = 0, name = "lua_ls" }) > 0
      end),
      "lua_ls did not attach"
    )
    local line = vim.fn.search("^function M.setup", "nw")
    assert(line > 0, "M.setup not found")
    vim.api.nvim_win_set_cursor(0, { line + 2, 2 }) -- inside M.setup
    assert(
      wait(15000 * SLOW, function()
        require("lumen.ui.winbar").request(0)
        return require("lumen.ui.winbar").render():find("setup", 1, true) ~= nil
      end),
      "no symbols in winbar: " .. require("lumen.ui.winbar").render()
    )
  end)

  check("winbar: clicking a crumb jumps to the symbol", function()
    local win = vim.api.nvim_get_current_win()
    local cursor = vim.api.nvim_win_get_cursor(win)
    require("lumen.ui.winbar").render()
    local getmousepos = vim.fn.getmousepos
    vim.fn.getmousepos = function()
      return { winid = win }
    end
    local ok, err = pcall(_G.LumenWinbarClick, 1, 1, "l", "")
    vim.fn.getmousepos = getmousepos
    assert(ok, err)
    local line = vim.fn.search("^function M.setup", "nw")
    assert(vim.api.nvim_win_get_cursor(win)[1] == line, "cursor not on M.setup")
    vim.api.nvim_win_set_cursor(win, cursor)
  end)

  check("fold text keeps highlights + count", function()
    vim.v.foldstart, vim.v.foldend = 5, 10
    local chunks = require("lumen.ui.fold").text()
    assert(#chunks >= 3, "expected several chunks")
    assert(chunks[#chunks][1]:find("6 lines"), "missing count")
  end)

  check("fold text expands tabs to tab stops", function()
    vim.cmd("enew")
    vim.bo.tabstop = 4
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "\tab\tc", "x", "y" })
    vim.v.foldstart, vim.v.foldend = 1, 3
    local text = table.concat(vim.tbl_map(function(c)
      return c[1]
    end, require("lumen.ui.fold").text()))
    vim.cmd("bwipeout!")
    assert(vim.startswith(text, "    ab  c "), vim.inspect(text))
  end)

  check("diagnostics cycle", function()
    local d = require("lumen.diagnostics")
    d.setup()
    d.cycle()
    assert(vim.diagnostic.config().virtual_lines, "virtual lines not enabled")
    d.cycle()
    d.cycle()
    assert(vim.diagnostic.config().virtual_text, "virtual text not restored")
  end)

  check("every language pack is well-formed", function()
    local fields = { "ft", "parsers", "tools", "plugins" }
    for _, name in ipairs(require("lumen.packs").available()) do
      local p = require("lumen.packs." .. name)
      assert(type(p) == "table", name .. ": not a table")
      for _, f in ipairs(fields) do
        assert(p[f] == nil or type(p[f]) == "table", name .. "." .. f .. " must be a list")
      end
      assert(p.servers == nil or type(p.servers) == "table", name .. ".servers must be a table")
    end
  end)

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

  check("why: explains the lua buffer", function()
    vim.cmd.edit("lua/lumen/init.lua")
    wait(20000 * SLOW, function()
      return #vim.lsp.get_clients({ bufnr = 0, name = "lua_ls" }) > 0
        and vim.treesitter.highlighter.active[vim.api.nvim_get_current_buf()] ~= nil
    end)
    local text = table.concat(require("lumen.why").report(0), "\n")
    assert(text:find("`lua` enabled", 1, true), "pack line missing\n" .. text)
    assert(text:find("`lua_ls` attached", 1, true), "lsp line missing\n" .. text)
    assert(text:find("stylua", 1, true), "formatter missing\n" .. text)
    assert(text:find("Project root", 1, true), "root missing")
    -- regression: fixes suggested `:MasonInstall ruff_format` (a conform name, not a package)
    local why = require("lumen.why")
    require("lazy").load({ plugins = { "mason.nvim" } })
    assert(why.mason_pkg("ruff_format") == "ruff", "ruff_format → " .. tostring(why.mason_pkg("ruff_format")))
    assert(why.mason_pkg("biome-check") == "biome", "biome-check → " .. tostring(why.mason_pkg("biome-check")))
    assert(why.mason_pkg("prettierd") == "prettierd")
    assert(why.mason_pkg("lumen_no_such_tool") == nil)

    -- regression: servers with a function `cmd` (jsonls, yamlls, eslint…) always read
    -- "installed but not attached", even when their Mason package was missing
    local registry = require("mason-registry")
    local is_installed = registry.is_installed
    registry.is_installed = function(name)
      return name ~= "json-lsp" and is_installed(name)
    end
    vim.cmd("enew")
    vim.bo.buftype, vim.bo.filetype = "nofile", "json"
    local ok, json = pcall(function()
      return table.concat(why.report(0), "\n")
    end)
    registry.is_installed = is_installed
    vim.cmd("bwipeout!")
    assert(ok, json)
    assert(json:find("`jsonls` not installed (Mason package `json-lsp` missing)", 1, true), json)

    -- a buffer without filetype isn't "missing the `` parser"
    vim.cmd("enew")
    local empty = table.concat(why.report(0), "\n")
    vim.cmd("bwipeout!")
    assert(not empty:find("``", 1, true), empty)
  end)

  check("why: buffers without a filetype get a sensible report", function()
    vim.cmd("enew")
    local text = table.concat(require("lumen.why").report(0), "\n")
    vim.cmd("bwipeout!")
    assert(not text:find("``", 1, true), text)
    assert(text:find("no filetype", 1, true), text)
  end)

  check("scrollbar: thumb + diagnostic mark", function()
    vim.cmd("enew")
    local lines = {}
    for i = 1, 400 do
      lines[i] = "line " .. i
    end
    vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
    vim.bo.buftype = ""
    local dns = vim.api.nvim_create_namespace("lumen_test")
    vim.diagnostic.set(dns, 0, { { lnum = 199, col = 0, message = "x", severity = vim.diagnostic.severity.ERROR } })
    require("lumen.ui.scrollbar").refresh()
    local target, float = vim.api.nvim_get_current_win(), nil
    for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      local cfg = vim.api.nvim_win_get_config(w)
      if cfg.relative == "win" and cfg.win == target and cfg.width == 1 then
        float = w
      end
    end
    assert(float, "no scrollbar float")
    local text = table.concat(vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(float), 0, -1, false))
    assert(text:find("━", 1, true), "error mark missing")
    vim.diagnostic.reset(dns, 0)
    vim.cmd("bwipeout!")
  end)

  check("scrollbar: search marks follow `*` without a cmdline or a scroll", function()
    vim.cmd("enew")
    local lines = {}
    for i = 1, 400 do
      lines[i] = i == 300 and "needle" or ("line " .. i)
    end
    vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
    local target = vim.api.nvim_get_current_win()
    require("lumen.ui.scrollbar").refresh()
    vim.wait(400) -- let refreshes queued by :enew run first
    vim.fn.setreg("/", "\\<needle\\>")
    vim.v.hlsearch = 1
    vim.api.nvim_exec_autocmds("CursorMoved", {}) -- what `*` / `n` trigger
    local function text()
      for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
        local cfg = vim.api.nvim_win_get_config(w)
        if cfg.relative == "win" and cfg.win == target and cfg.width == 1 then
          return table.concat(vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(w), 0, -1, false))
        end
      end
      return ""
    end
    local ok = wait(1000, function()
      return text():find("─", 1, true) ~= nil
    end)
    vim.cmd("nohlsearch")
    vim.cmd("bwipeout!")
    assert(ok, "no search mark: " .. text())
  end)

  check("scrollbar: stays inside the text area of a window with a winbar", function()
    vim.cmd("enew")
    local lines = {}
    for i = 1, 400 do
      lines[i] = "line " .. i
    end
    vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
    local target = vim.api.nvim_get_current_win()
    vim.wo[target].winbar = "winbar"
    require("lumen.ui.scrollbar").refresh()
    local height
    for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      local cfg = vim.api.nvim_win_get_config(w)
      if cfg.relative == "win" and cfg.win == target and cfg.width == 1 then
        height = cfg.height
      end
    end
    local want = vim.fn.winheight(target)
    vim.wo[target].winbar = ""
    vim.cmd("bwipeout!")
    assert(height == want, ("scrollbar height %s, text area %d"):format(tostring(height), want))
  end)

  check("update: snapshot + verification in a clean Neovim", function()
    local up = require("lumen.update")
    local path = up.snapshot()
    assert(path and vim.uv.fs_stat(path), "snapshot not written")
    assert(up.snapshots()[1].path == path, "snapshot not listed first")
    -- an unchanged lockfile reuses the newest snapshot instead of evicting older ones
    local count = #up.snapshots()
    vim.wait(1100) -- snapshot names have a 1s resolution
    assert(up.snapshot() == path and #up.snapshots() == count, "duplicate snapshot written")
    local result
    up.verify(function(ok, errors)
      result = { ok = ok, errors = errors }
    end)
    assert(
      wait(60000 * SLOW, function()
        return result ~= nil
      end),
      "verification timed out"
    )
    assert(result.ok, "verification failed:\n" .. table.concat(result.errors, "\n"))
    os.remove(path)
  end)

  check("opening a file after startup (dashboard → :e) gets filetype, treesitter, LSP", function()
    -- regression: LazyFile loading lspconfig mid-BufReadPost used to swallow filetype detection
    local probe = [[
      vim.defer_fn(function()
        vim.cmd.edit("lua/lumen/icons.lua")
        vim.wait(SLOW_MS, function()
          return #vim.lsp.get_clients({ bufnr = 0, name = "lua_ls" }) > 0
        end, 100)
        io.stdout:write(vim.json.encode({
          ft = vim.bo.filetype,
          ts = vim.treesitter.highlighter.active[vim.api.nvim_get_current_buf()] ~= nil,
          lsp = #vim.lsp.get_clients({ bufnr = 0, name = "lua_ls" }) > 0,
        }) .. "\n")
        vim.cmd("qa!")
      end, 300)
    ]]
    probe = probe:gsub("SLOW_MS", tostring(20000 * SLOW))
    local out = vim
      .system({ vim.v.progpath, "--headless", "-c", "lua " .. probe:gsub("\n", " ") }, { text = true })
      :wait(40000 * SLOW)
    local res = vim.json.decode((out.stdout or ""):match("{.-}") or "{}")
    assert(res.ft == "lua", "filetype not detected: " .. vim.inspect(res) .. (out.stderr or ""))
    assert(res.ts, "treesitter not active")
    assert(res.lsp, "lua_ls did not attach")
  end)

  check("nvim -d: no diff pane gets a winbar (panes stay aligned)", function()
    local probe = [[
      vim.defer_fn(function()
        local bars = {}
        for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
          if vim.api.nvim_win_get_config(w).relative == "" then
            bars[#bars + 1] = { diff = vim.wo[w].diff, winbar = vim.wo[w].winbar }
          end
        end
        io.stdout:write(vim.json.encode(bars) .. "\n")
        vim.cmd("qa!")
      end, 500)
    ]]
    local out = vim
      .system({
        vim.v.progpath,
        "--headless",
        "-d",
        "lua/lumen/ui/fold.lua",
        "lua/lumen/ui/tabline.lua",
        "-c",
        "lua " .. probe:gsub("\n", " "),
      }, { text = true })
      :wait(20000 * SLOW)
    local bars = vim.json.decode((out.stdout or ""):match("%[.*%]") or "[]")
    assert(#bars == 2, "expected 2 windows: " .. (out.stdout or "") .. (out.stderr or ""))
    for _, b in ipairs(bars) do
      assert(b.diff and b.winbar == "", vim.inspect(bars))
    end
  end)

  check("Lumen starts and edits with snacks.nvim disabled", function()
    -- regression: keymaps.lua called Snacks.toggle at setup, so the lumen config aborted
    local probe = [[
      vim.defer_fn(function()
        vim.cmd.edit("lua/lumen/icons.lua")
        vim.wait(SLOW_MS, function()
          return #vim.lsp.get_clients({ bufnr = 0, name = "lua_ls" }) > 0
        end, 100)
        local gd = vim.fn.maparg("gd", "n", false, true)
        local ft, errmsg = vim.bo.filetype, vim.v.errmsg
        local why = pcall(vim.cmd, "Lumen why") and vim.bo.filetype == "markdown"
        io.stdout:write(vim.json.encode({
          lumen = vim.fn.exists(":Lumen") == 2,
          snacks = _G.Snacks ~= nil,
          ft = ft,
          gd = gd.buffer == 1,
          why = why,
          errmsg = errmsg,
        }) .. "\n")
        vim.cmd("qa!")
      end, 300)
    ]]
    probe = probe:gsub("SLOW_MS", tostring(20000 * SLOW))
    local res, out =
      child(probe, { ["lua/plugins/zz_no_snacks.lua"] = 'return { { "folke/snacks.nvim", enabled = false } }' })
    assert(res.snacks == false, "snacks still loaded: " .. vim.inspect(res) .. (out.stderr or ""))
    assert(res.lumen, ":Lumen missing, setup aborted: " .. vim.inspect(res) .. (out.stderr or ""))
    assert(res.ft == "lua" and res.gd, "no filetype / LSP keymaps: " .. vim.inspect(res))
    assert(res.why, ":Lumen why failed: " .. vim.inspect(res))
    assert(res.errmsg == "", res.errmsg)
  end)

  check("lumen spec opts apply (format_on_save, transparent) + catppuccin is the plugin", function()
    -- regressions: options.lua / the catppuccin spec read these before spec opts were merged,
    -- and `colorscheme catppuccin` loaded Neovim's bundled scheme (0.12+) instead of the plugin
    local probe = [[
      vim.defer_fn(function()
        io.stdout:write(vim.json.encode({
          autoformat = vim.g.lumen_autoformat,
          colors = vim.g.colors_name,
          plugin = package.loaded.catppuccin ~= nil,
          transparent = vim.api.nvim_get_hl(0, { name = "Normal" }).bg == nil,
        }) .. "\n")
        vim.cmd("qa!")
      end, 300)
    ]]
    local res, out = child(probe, {
      ["lua/plugins/zz_opts.lua"] = [[return { { "lumen", opts = {
        format_on_save = false, transparent = true, colorscheme = "catppuccin" } } }]],
    })
    assert(res.autoformat == false, "format_on_save opt ignored: " .. vim.inspect(res) .. (out.stderr or ""))
    assert(res.plugin and res.colors ~= "catppuccin", "bundled catppuccin loaded, not the plugin: " .. vim.inspect(res))
    assert(res.transparent, "transparent opt ignored by catppuccin: " .. vim.inspect(res))
  end)

  check("lua/config/options.lua wins over Lumen's deferred clipboard", function()
    local probe = [[
      vim.defer_fn(function()
        io.stdout:write(vim.json.encode({ clipboard = vim.o.clipboard }) .. "\n")
        vim.cmd("qa!")
      end, 300)
    ]]
    local res, out = child(probe, { ["lua/config/options.lua"] = 'vim.opt.clipboard = ""' })
    assert(res.clipboard == "", "user clipboard overridden: " .. vim.inspect(res) .. (out.stderr or ""))
    if not vim.env.SSH_TTY then
      assert(vim.o.clipboard == "unnamedplus", "default clipboard not set: " .. vim.o.clipboard)
    end
  end)

  check("`q` closes a help window even when it is the last one", function()
    local probe = [[
      vim.defer_fn(function()
        vim.cmd("help | only")
        vim.wait(200)
        local ok, err = pcall(vim.api.nvim_feedkeys, "q", "x", false)
        io.stdout:write(vim.json.encode({ ok = ok, err = tostring(err or ""), ft = vim.bo.filetype }) .. "\n")
        vim.cmd("qa!")
      end, 300)
    ]]
    local res, out = child(probe)
    assert(res.ok and res.ft ~= "help", "q failed: " .. vim.inspect(res) .. (out.stderr or ""))
  end)

  check("Lumen.pick follows the current buffer's root", function()
    -- regression: the first call saved its cwd into the shared opts, freezing the root forever
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir, "p")
    vim.fn.writefile({}, dir .. "/.root")
    local pick, cwds = Snacks.picker.pick, {}
    Snacks.picker.pick = function(_, opts)
      cwds[#cwds + 1] = opts.cwd
    end
    local open = Lumen.pick("files")
    local ok, err = pcall(function()
      vim.cmd.edit("lua/lumen/init.lua")
      open()
      vim.cmd.edit(dir .. "/x.txt")
      open()
    end)
    Snacks.picker.pick = pick
    vim.cmd("bwipeout! " .. vim.fn.fnameescape(dir .. "/x.txt"))
    vim.fn.delete(dir, "rf")
    assert(ok, err)
    local tail = vim.fn.fnamemodify(dir, ":t")
    assert(cwds[2] and cwds[2]:sub(-#tail) == tail and cwds[1] ~= cwds[2], "root frozen: " .. vim.inspect(cwds))
  end)

  check("LSP keymaps only for capabilities the client has", function()
    -- regression: K was mapped to LSP hover for any client, even one without hover (copilot),
    -- hiding 'keywordprg' behind a "method not supported" error
    vim.cmd("enew")
    local buf = vim.api.nvim_get_current_buf()
    local id = fake_server("lumen_fake", {}, buf)
    assert(
      wait(3000, function()
        return #vim.lsp.get_clients({ bufnr = buf, name = "lumen_fake" }) > 0
      end),
      "fake server did not attach"
    )
    vim.wait(100)
    local k = vim.fn.maparg("K", "n", false, true)
    vim.lsp.get_client_by_id(id):stop(true)
    vim.cmd("bwipeout!")
    assert(k.buffer ~= 1, "K mapped for a client without hover")
  end)

  check("ai pack turns on Copilot inline suggestions", function()
    -- regression: copilot attached but Neovim's inline completion stayed off, so no suggestions
    if not vim.lsp.inline_completion then
      return -- Neovim < 0.12
    end
    require("lumen.packs.ai").setup()
    vim.cmd("enew")
    local buf = vim.api.nvim_get_current_buf()
    local id = fake_server("copilot", { inlineCompletionProvider = true }, buf)
    assert(
      wait(3000, function()
        return vim.lsp.inline_completion.is_enabled({ bufnr = buf })
      end),
      "inline completion not enabled for copilot"
    )
    vim.lsp.get_client_by_id(id):stop(true)
    vim.cmd("bwipeout!")
  end)

  check("every pack reference resolves (parsers, servers, mason, formatters, linters)", function()
    require("lazy").load({ plugins = { "nvim-lspconfig", "conform.nvim", "nvim-lint", "mason-lspconfig.nvim" } })
    local parsers = require("nvim-treesitter.parsers")
    local mapping = require("mason-lspconfig").get_mappings().lspconfig_to_package
    local reg_file = vim.fn.stdpath("data") .. "/mason/registries/github/mason-org/mason-registry/registry.json"
    local mason
    if vim.uv.fs_stat(reg_file) then
      mason = {}
      for _, pkg in ipairs(vim.json.decode(table.concat(vim.fn.readfile(reg_file), "\n"))) do
        mason[pkg.name] = true
      end
    end
    local problems = {}
    for _, name in ipairs(require("lumen.packs").available()) do
      local p = require("lumen.packs." .. name)
      for _, lang in ipairs(p.parsers or {}) do
        if not parsers[lang] then
          problems[#problems + 1] = name .. ": parser " .. lang
        end
      end
      for server, cfg in pairs(p.servers or {}) do
        if not (vim.lsp.config[server] and vim.lsp.config[server].cmd) then
          problems[#problems + 1] = name .. ": server " .. server
        end
        if cfg.mason ~= false and not mapping[server] then
          problems[#problems + 1] = name .. ": no mason package for " .. server
        end
      end
      for _, tool in ipairs(mason and p.tools or {}) do
        if not mason[tool] then
          problems[#problems + 1] = name .. ": mason tool " .. tool
        end
      end
      for _, list in pairs(p.formatters or {}) do
        for _, f in ipairs(type(list) == "function" and list(0) or list) do
          if not pcall(require, "conform.formatters." .. f) then
            problems[#problems + 1] = name .. ": formatter " .. f
          end
        end
      end
      for _, list in pairs(p.linters or {}) do
        for _, l in ipairs(list) do
          if not require("lint").linters[l] then
            problems[#problems + 1] = name .. ": linter " .. l
          end
        end
      end
    end
    assert(#problems == 0, table.concat(problems, "\n"))
  end)

  check("performance budgets on a 20k-line buffer with 3k diagnostics", function()
    vim.cmd("enew")
    local lines = {}
    for i = 1, 20000 do
      lines[i] = ("local value_%d = compute(%d) -- line %d"):format(i, i, i)
    end
    vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
    vim.bo.filetype = "lua"
    local diags = {}
    for i = 1, 3000 do
      diags[i] = { lnum = i * 6, col = 0, message = "x", severity = (i % 4) + 1 }
    end
    vim.diagnostic.set(vim.api.nvim_create_namespace("lumen_perf"), 0, diags)
    vim.wait(50)
    local function cost(fn, n)
      fn()
      local t = vim.uv.hrtime()
      for _ = 1, n do
        fn()
      end
      return (vim.uv.hrtime() - t) / n / 1000
    end
    local stl = cost(require("lumen.ui.statusline").render, 500)
    local bar = cost(require("lumen.ui.scrollbar").refresh, 100)
    local tab = cost(require("lumen.ui.tabline").render, 500)
    io.stdout:write(("      statusline %.0fµs · scrollbar %.0fµs · tabline %.0fµs\n"):format(stl, bar, tab))
    assert(stl < 150 * SLOW, ("statusline too slow: %.0fµs"):format(stl))
    assert(bar < 1000 * SLOW, ("scrollbar too slow: %.0fµs"):format(bar))
    assert(tab < 150 * SLOW, ("tabline too slow: %.0fµs"):format(tab))
    vim.cmd("bwipeout!")
  end)

  check("statuscolumn signs: windowed lookup matches Snacks and stays cheap", function()
    vim.cmd("enew")
    local lines = {}
    for i = 1, 20000 do
      lines[i] = ("local value_%d = compute(%d)"):format(i, i)
    end
    vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
    local diags = {}
    for i = 1, 3000 do
      diags[i] = { lnum = i * 6, col = 0, message = "x", severity = (i % 4) + 1 }
    end
    vim.diagnostic.set(vim.api.nvim_create_namespace("lumen_signs"), 0, diags)
    vim.api.nvim_buf_set_mark(0, "a", 300, 0, {})
    local sc = require("snacks.statuscolumn")
    local lsc = require("lumen.ui.statuscolumn")
    lsc.setup()
    assert(sc._lumen_windowed and lsc.original, "Snacks.statuscolumn.buf_signs not patched")
    local wanted = { git = true, sign = true, mark = true, fold = true }
    local function key(list)
      local out = {}
      for _, s in ipairs(list or {}) do
        out[#out + 1] = table.concat({ tostring(s.name), s.type, tostring(s.text), tostring(s.priority) }, "|")
      end
      table.sort(out)
      return table.concat(out, ";")
    end
    local buf = vim.api.nvim_get_current_buf()
    local full, win = lsc.original(buf, wanted), sc.buf_signs(buf, wanted)
    for l = 1, 20000 do
      assert(key(full[l]) == key(win[l]), ("signs differ on line %d: %s vs %s"):format(l, key(full[l]), key(win[l])))
    end
    assert(key(win[300]):find("mark", 1, true), "mark missing")
    -- what a redraw needs after Snacks drops its cache: a fresh lookup of ~60 visible lines
    local t = vim.uv.hrtime()
    for _ = 1, 50 do
      local signs = sc.buf_signs(buf, wanted)
      for l = 10000, 10060 do
        local _ = signs[l]
      end
    end
    local us = (vim.uv.hrtime() - t) / 50 / 1000
    io.stdout:write(("      statuscolumn sign lookup %.0fµs\n"):format(us))
    assert(us < 500 * SLOW, ("statuscolumn sign lookup too slow: %.0fµs"):format(us))
    vim.cmd("bwipeout!")
  end)

  check("theme contrast (WCAG) in both variants", function()
    local function lum(h)
      local function ch(i)
        local c = tonumber(h:sub(i, i + 1), 16) / 255
        return c <= 0.03928 and c / 12.92 or ((c + 0.055) / 1.055) ^ 2.4
      end
      return 0.2126 * ch(2) + 0.7152 * ch(4) + 0.0722 * ch(6)
    end
    local function ratio(a, b)
      local x, y = lum(a), lum(b)
      return (math.max(x, y) + 0.05) / (math.min(x, y) + 0.05)
    end
    local bad = {}
    for variant, p in pairs(require("lumen.colors.palettes")) do
      for _, k in ipairs({
        "fg",
        "fg_dim",
        "member",
        "param",
        "amber",
        "orange",
        "red",
        "rose",
        "violet",
        "blue",
        "sky",
        "cyan",
        "teal",
        "green",
        "yellow",
      }) do
        if ratio(p[k], p.bg) < 4.5 then
          bad[#bad + 1] = ("%s.%s %.2f"):format(variant, k, ratio(p[k], p.bg))
        end
      end
      for k, min in pairs({ comment = 3.5, gutter = 2.5 }) do
        if ratio(p[k], p.bg) < min then
          bad[#bad + 1] = ("%s.%s %.2f"):format(variant, k, ratio(p[k], p.bg))
        end
      end
    end
    assert(#bad == 0, "below contrast floor: " .. table.concat(bad, ", "))
  end)

  check("treesitter: Lumen's background parser installs don't echo per-parser lines", function()
    local Logger = require("nvim-treesitter.log").Logger
    assert(Logger.lumen_info, "nvim-treesitter's logger is not hooked")
    -- nvim-treesitter echoes with history, so count its lines in :messages
    local function echoed()
      local _, n = vim.api.nvim_exec2("messages", { output = true }).output:gsub("install/lumentest", "")
      return n
    end
    local logger = require("nvim-treesitter.log").new("install/lumentest")
    Logger.lumen_quiet = Logger.lumen_quiet + 1
    pcall(logger.info, logger, "Compiling parser")
    Logger.lumen_quiet = Logger.lumen_quiet - 1
    assert(echoed() == 0, "echoed while a Lumen install runs")
    -- outside Lumen's installs (a user's :TSInstall) it passes through to the original.
    -- Force "no Lumen install running": on a fresh machine (CI) the startup installs may still be going.
    local orig, quiet, passed = Logger.lumen_info, Logger.lumen_quiet, false
    Logger.lumen_quiet = 0
    Logger.lumen_info = function()
      passed = true
    end
    pcall(logger.info, logger, "Compiling parser")
    Logger.lumen_info, Logger.lumen_quiet = orig, quiet
    assert(passed, "user-run installs must stay verbose")
  end)

  check("why: no false alarm for a filetype without a treesitter parser", function()
    local buf = vim.api.nvim_create_buf(false, true)
    vim.bo[buf].filetype = "org"
    local text = table.concat(require("lumen.why").report(buf), "\n")
    vim.api.nvim_buf_delete(buf, { force = true })
    assert(text:find("no treesitter parser exists for `org`", 1, true), text)
    assert(not text:find("✗ no `org` parser", 1, true), text)
  end)

  check("install.sh rejects unsafe arguments before touching anything", function()
    local tmp = vim.fn.tempname()
    vim.fn.mkdir(tmp, "p")
    local env = { XDG_CONFIG_HOME = tmp, XDG_DATA_HOME = tmp, XDG_STATE_HOME = tmp, XDG_CACHE_HOME = tmp }
    for _, args in ipairs({ { "--appname", "" }, { "--appname" }, { "--appname", "../x" }, { "--repo", "x" }, { "-z" } }) do
      local out = vim.system(vim.list_extend({ "bash", "install.sh" }, args), { env = env, text = true }):wait(10000)
      assert(out.code == 1, ("install.sh %s exited %s"):format(table.concat(args, " "), out.code))
      assert(out.stderr:find("error:", 1, true), out.stderr)
    end
    assert(#vim.fn.readdir(tmp) == 0, "install.sh wrote to " .. tmp)
    local help = vim
      .system({ "bash", "-s", "--", "--help" }, { stdin = table.concat(vim.fn.readfile("install.sh"), "\n") })
      :wait(10000)
    assert(help.code == 0 and help.stdout:find("usage:", 1, true), "--help when piped: " .. tostring(help.stdout))
    vim.fn.delete(tmp, "rf")
  end)

  check(":Lumen menu lists every subcommand", function()
    local items
    local select = vim.ui.select
    vim.ui.select = function(list)
      items = list
    end
    pcall(vim.cmd, "Lumen")
    vim.ui.select = select
    assert(items and #items >= 10, "menu items: " .. vim.inspect(items))
    assert(items[1].name == "packs", "packs should come first")
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

  check("]C / [C stay Neovim's multicursor keys on 0.13+", function()
    require("lazy").load({ plugins = { "nvim-treesitter-textobjects" } })
    local next_class = vim.fn.maparg("]c", "n", false, true)
    assert(next_class.desc == "Next class start", "]c should still jump to classes: " .. vim.inspect(next_class.desc))
    local mapped = vim.fn.maparg("]C", "n", false, true).desc
    if vim.api.nvim_mcursor then
      assert(mapped ~= "Next class end", "]C overrides Neovim's next-cursor key")
    else
      assert(mapped == "Next class end", "]C should jump to class ends before 0.13")
    end
  end)

  check("sql pack: sqmeow runs the buffer with <leader>Dx, not <leader>E", function()
    local spec = require("lumen.packs.sql").plugins[1]
    assert(spec[1] == "2giosangmitom/sqmeow.nvim", "unexpected first plugin: " .. tostring(spec[1]))
    assert(spec.opts.keymaps.editor.execute_buffer == "<leader>Dx", vim.inspect(spec.opts))
  end)

  check(":Lumen command + health", function()
    assert(vim.fn.exists(":Lumen") == 2)
    vim.cmd("checkhealth lumen")
    local text = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
    assert(not text:find("ERROR"), text)
    vim.cmd("bwipeout")
  end)

  check("every Mason command lazy-loads mason", function()
    -- regression: :MasonUninstall was "not an editor command" until mason happened to load
    -- (mason is loaded by now, so check the spec rather than the commands)
    local cmds = require("lazy.core.config").plugins["mason.nvim"].cmd or {}
    for _, cmd in ipairs({ "Mason", "MasonInstall", "MasonUninstall", "MasonUninstallAll", "MasonUpdate", "MasonLog" }) do
      assert(vim.tbl_contains(cmds, cmd), ":" .. cmd .. " does not load mason")
    end
  end)

  check("no startup errors", function()
    assert(vim.v.errmsg == "", vim.v.errmsg)
  end)

  io.stdout:write(("\n%d passed, %d failed\n"):format(passes, #failures))
  vim.cmd(#failures == 0 and "qa!" or "cquit 1")
end

vim.schedule(function()
  local ok, err = pcall(run)
  if not ok then
    io.stdout:write("crashed: " .. tostring(err) .. "\n")
    vim.cmd("cquit 2")
  end
end)
