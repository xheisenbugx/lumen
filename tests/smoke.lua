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

  check("fold text keeps highlights + count", function()
    vim.v.foldstart, vim.v.foldend = 5, 10
    local chunks = require("lumen.ui.fold").text()
    assert(#chunks >= 3, "expected several chunks")
    assert(chunks[#chunks][1]:find("6 lines"), "missing count")
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
    -- outside Lumen's installs (a user's :TSInstall) it passes through to the original
    local orig, passed = Logger.lumen_info, false
    Logger.lumen_info = function()
      passed = true
    end
    pcall(logger.info, logger, "Compiling parser")
    Logger.lumen_info = orig
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

  check(":Lumen command + health", function()
    assert(vim.fn.exists(":Lumen") == 2)
    vim.cmd("checkhealth lumen")
    local text = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
    assert(not text:find("ERROR"), text)
    vim.cmd("bwipeout")
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
