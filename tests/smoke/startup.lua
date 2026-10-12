-- Startup paths, user config, commands, health, installer (run by tests/smoke.lua)
---@param t lumen.test.Helpers
return function(t)
  local check, wait, child, fake_server, SLOW = t.check, t.wait, t.child, t.fake_server, t.SLOW

  --- run `:checkhealth lumen` and return its text. Nightly fills the buffer asynchronously, so wait
  --- for the last section ("Updates" reports the lazy.nvim lockfile check either way)
  local function health()
    vim.cmd("checkhealth lumen")
    local buf = vim.api.nvim_get_current_buf()
    local function text()
      return table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
    end
    wait(10000 * SLOW, function()
      return text():find("lockfile internals", 1, true) ~= nil
    end)
    return text()
  end

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
    local text = health()
    assert(text:find("Lumen", 1, true), "empty health report")
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

  check("`q` mapping: a utility buffer wiped right after it opened leaves no error", function()
    -- regression: `:checkhealth` + `:bwipeout` in one go made the scheduled `q` mapping throw
    vim.v.errmsg = ""
    local buf = vim.api.nvim_create_buf(false, true)
    vim.bo[buf].filetype = "startuptime"
    vim.api.nvim_buf_delete(buf, { force = true })
    vim.wait(100)
    assert(vim.v.errmsg == "", vim.v.errmsg)
  end)

  check("project .lumen.lua: trusted applies packs/tasks/settings, untrusted is ignored, :Lumen trust", function()
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir .. "/sub", "p")
    local file = dir .. "/.lumen.lua"
    vim.fn.writefile({
      "return {",
      '  packs = { "go" },',
      '  tasks = { { name = "hello", cmd = "echo hi" }, { name = "in-sub", cmd = "ls", cwd = "sub" } },',
      "  format_on_save = false,",
      '  leader = ",",',
      "}",
    }, file)
    -- the probe runs before VimEnter, so nothing gets installed for the go pack
    local function probe(extra)
      local code = [[
        EXTRA
        local p, tasks = require("lumen.project"), {}
        for _, t in ipairs(require("lumen.tasks").discover()) do
          if t.source == "project" then tasks[t.name] = t.cwd end
        end
        io.stdout:write(vim.json.encode({
          trusted = p.trusted, go = require("lumen.packs").enabled().go == true,
          fos = vim.g.lumen_autoformat, leader = vim.g.mapleader, tasks = tasks,
          gopls = require("lumen.lsp").servers.gopls ~= nil,
        }) .. "\n")
        vim.cmd("qa!")
      ]]
      code = code:gsub("EXTRA", extra or "")
      local out = vim
        .system({ vim.v.progpath, "--headless", "-c", "lua " .. code:gsub("\n", " ") }, { text = true, cwd = dir })
        :wait(30000 * SLOW)
      return vim.json.decode((out.stdout or ""):match("{.*}") or "{}"), out
    end
    local ok, err = pcall(function()
      local res, out = probe()
      assert(
        res.trusted == false and not res.go,
        "an untrusted .lumen.lua was used: " .. vim.inspect(res) .. (out.stderr or "")
      )
      assert(res.fos ~= false, "untrusted settings applied")

      assert(vim.secure.trust({ action = "allow", path = file }))
      res, out = probe()
      local real = vim.fs.normalize(assert(vim.uv.fs_realpath(dir)))
      assert(res.trusted and res.go, "trusted .lumen.lua packs not enabled: " .. vim.inspect(res) .. (out.stderr or ""))
      assert(res.fos == false, "format_on_save not applied")
      assert(res.leader == " ", "leader can't be set per project, got " .. tostring(res.leader))
      assert(res.tasks.hello == real, "project task cwd: " .. vim.inspect(res.tasks))
      assert(res.tasks["in-sub"] == real .. "/sub", "relative task cwd: " .. vim.inspect(res.tasks))

      -- an edit invalidates the trust; :Lumen trust re-trusts it and applies it to the session
      vim.fn.writefile({ "-- edited" }, file, "a")
      res = probe()
      assert(res.trusted == false and not res.go, "an edited .lumen.lua kept its trust")
      res, out = probe("vim.cmd('Lumen trust')")
      assert(
        res.trusted and res.go and res.gopls,
        ":Lumen trust didn't apply the file: " .. vim.inspect(res) .. (out.stderr or "")
      )
    end)
    pcall(vim.secure.trust, { action = "remove", path = file })
    vim.fn.delete(dir, "rf")
    assert(ok, err)
  end)

  check("health: pack toolchains and lazy.nvim's lockfile internals", function()
    local packs = require("lumen.packs")
    local orig = packs.missing
    packs.missing = function(p)
      return p == packs.get("lua") and { "lumen-fake-toolchain" } or {}
    end
    local ok, text = pcall(health)
    packs.missing = orig
    pcall(vim.cmd, "bwipeout")
    assert(ok, text)
    assert(text:find("lua: `lumen-fake-toolchain` not found on PATH", 1, true), text)
    assert(text:find("lockfile internals are where :Lumen update expects them", 1, true), text)
  end)

  check(":help lumen opens Lumen's docs, and every tag resolves", function()
    local dir = require("lazy.core.config").plugins.lumen.dir .. "/doc"
    vim.cmd.helptags(vim.fn.fnameescape(dir)) -- errors on duplicate tags
    for _, tag in ipairs({ "lumen", "lumen-packs", "lumen-project", ":Lumen", "lumen-tasks", "lumen-update" }) do
      vim.cmd.help(tag)
      assert(vim.api.nvim_buf_get_name(0):find("doc/lumen.txt$"), tag .. " opened " .. vim.api.nvim_buf_get_name(0))
      vim.cmd.close()
    end
    -- every |link| in the file points to a tag that exists (Lumen's own or Neovim's)
    local text = table.concat(vim.fn.readfile(dir .. "/lumen.txt"), "\n")
    for link in text:gmatch("|([^|%s]+)|") do
      assert(pcall(vim.cmd.help, link), "dangling help link |" .. link .. "|")
      vim.cmd.close()
    end
  end)
end
