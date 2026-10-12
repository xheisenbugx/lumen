-- Language packs: shape, references, pack behaviour (run by tests/smoke.lua)
---@param t lumen.test.Helpers
return function(t)
  local check, wait, child, fake_server, SLOW = t.check, t.wait, t.child, t.fake_server, t.SLOW

  check("every language pack is well-formed", function()
    local fields = { "ft", "parsers", "tools", "plugins" }
    for _, name in ipairs(require("lumen.packs").available()) do
      local p = require("lumen.packs." .. name)
      assert(type(p) == "table", name .. ": not a table")
      for _, f in ipairs(fields) do
        assert(p[f] == nil or type(p[f]) == "table", name .. "." .. f .. " must be a list")
      end
      assert(p.servers == nil or type(p.servers) == "table", name .. ".servers must be a table")
      for _, req in ipairs(p.requires or {}) do
        local ok = type(req) == "string" or (type(req) == "table" and #req > 0)
        assert(ok, name .. ".requires: each item is a binary name or a list of alternatives")
      end
      for _, dep in ipairs(p.extends or {}) do
        assert(require("lumen.packs").exists(dep), name .. ".extends: unknown pack " .. dep)
      end
    end
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

  check("sql pack: sqmeow runs the buffer with <leader>Dx, not <leader>E", function()
    local spec = require("lumen.packs.sql").plugins[1]
    assert(spec[1] == "2giosangmitom/sqmeow.nvim", "unexpected first plugin: " .. tostring(spec[1]))
    assert(spec.opts.keymaps.editor.execute_buffer == "<leader>Dx", vim.inspect(spec.opts))
  end)

  -- packs.json is real state: tests that toggle packs put it back afterwards
  local function with_pack_state(fn)
    local file = vim.fn.stdpath("state") .. "/lumen/packs.json"
    local saved = vim.fn.filereadable(file) == 1 and vim.fn.readfile(file) or nil
    local ok, err = pcall(fn)
    if saved then
      vim.fn.writefile(saved, file)
    else
      os.remove(file)
    end
    assert(ok, err)
  end

  check("packs: extends pulls in dependencies, requires reports missing binaries, suggestions", function()
    local packs = require("lumen.packs")
    with_pack_state(function()
      assert(not packs.enabled().vue, "vue should start disabled")
      packs.set("vue", true)
      local enabled, via = packs.enabled()
      assert(enabled.vue and enabled.typescript and via.typescript == "vue", vim.inspect({ enabled, via }))
      local order = packs.ordered({ vue = true, typescript = true, lua = true })
      local pos = {}
      for i, n in ipairs(order) do
        pos[n] = i
      end
      assert(pos.typescript < pos.vue, "a pack must come after the packs it extends: " .. vim.inspect(order))
      packs.set("vue", false)
      assert(not packs.enabled().typescript, "typescript stayed on after vue was disabled")

      local missing = packs.missing({ requires = { "lumen-no-such-binary", { "lumen-nope", "sh" }, "sh" } })
      assert(vim.deep_equal(missing, { "lumen-no-such-binary" }), vim.inspect(missing))

      -- a notification, not a prompt: what it says, and `dismiss` silences it
      assert(packs.suggestion("go") == "go", "no suggestion for go files")
      local msg = packs.suggest_message("go", "go")
      assert(msg:find(":Lumen packs enable go", 1, true) and msg:find(":Lumen packs dismiss go", 1, true), msg)
      packs.dismiss("go")
      assert(packs.suggestion("go") == nil, "a dismissed pack is still suggested")
      assert(packs.suggestion("lua") == nil, "an enabled pack is suggested")
    end)
  end)

  check("packs: a pack without plugins applies right away, one with plugins asks for a restart", function()
    local packs, lsp, ts = require("lumen.packs"), require("lumen.lsp"), require("lumen.treesitter")
    local notes, prompts, installs = {}, {}, {}
    local orig = {
      notify = Lumen.notify,
      prompt = packs.prompt_restart,
      install = lsp.install,
      _install = lsp._install,
      ensure = ts.ensure,
    }
    Lumen.notify = function(msg)
      notes[#notes + 1] = msg
    end
    packs.prompt_restart = function(msg)
      prompts[#prompts + 1] = msg
    end
    -- no downloads from the test: record what would be installed
    lsp.install = function(pkgs)
      vim.list_extend(installs, pkgs)
    end
    lsp._install = function() end
    ts.ensure = function(langs)
      vim.list_extend(installs, langs)
    end
    local enabled = function(name)
      return vim.lsp.is_enabled and vim.lsp.is_enabled(name) or vim.lsp._enabled_configs[name] ~= nil
    end
    local ok, err = pcall(with_pack_state, function()
      assert(not enabled("gopls"), "gopls is enabled before the test")
      packs.toggle("go", true)
      wait(1000, function()
        return enabled("gopls")
      end)
      assert(enabled("gopls"), "gopls not enabled in the running session")
      assert(require("conform").formatters_by_ft.go, "go formatters not registered with conform")
      assert(vim.tbl_contains(installs, "gofumpt") and vim.tbl_contains(installs, "go"), vim.inspect(installs))
      assert(#prompts == 0, "a pack without plugins asked for a restart: " .. vim.inspect(prompts))
      assert(table.concat(notes, "\n"):find("ready in this session", 1, true), vim.inspect(notes))

      packs.toggle("go", false)
      assert(#prompts == 1 and prompts[1]:find("Disabled pack `go`", 1, true), vim.inspect(prompts))

      -- rust brings crates.nvim: lazy.nvim can't add plugins to a running session
      packs.toggle("rust", true)
      assert(#prompts == 2 and prompts[2]:find("adds plugins", 1, true), vim.inspect(prompts))
      vim.wait(500) -- lumen.lsp resolves Mason packages 300ms after enabling: let it hit the stubs
    end)
    Lumen.notify, packs.prompt_restart = orig.notify, orig.prompt
    lsp.install, lsp._install, ts.ensure = orig.install, orig._install, orig.ensure
    pcall(vim.lsp.enable, "gopls", false)
    lsp.servers.gopls = nil
    require("conform").formatters_by_ft.go = nil
    assert(not enabled("rust_analyzer"), "a pack that needs a restart was half-applied")
    assert(ok, err)
  end)

  check("lsp: `$MASON/` in server settings resolves to Mason's install root", function()
    local lsp = require("lumen.lsp")
    local out = lsp.expand_mason({ a = "$MASON/packages/x", b = { "$MASON/y", 3 }, c = "$MASONX", d = "keep" }, "/m")
    assert(vim.deep_equal(out, { a = "/m/packages/x", b = { "/m/y", 3 }, c = "$MASONX", d = "keep" }), vim.inspect(out))
    assert(
      lsp.mason_root({ install_root_dir = "/opt/mason/" }) == "/opt/mason",
      lsp.mason_root({ install_root_dir = "/opt/mason/" })
    )
    -- the vue pack's TS plugin path is relative to Mason's root, not a hardcoded data dir
    local vtsls = require("lumen.packs.vue").servers.vtsls
    local plugin = vtsls.settings.vtsls.tsserver.globalPlugins[1].location
    assert(plugin:find("^%$MASON/"), plugin)
  end)

  check("lint: runnable linters are resolved once per filetype, and again after an install", function()
    require("lazy").load({ plugins = { "nvim-lint" } })
    local lint = require("lint")
    local orig, calls = lint._resolve_linter_by_ft, 0
    lint._resolve_linter_by_ft = function(...)
      calls = calls + 1
      return orig(...)
    end
    local ok, err = pcall(function()
      local function trigger()
        vim.api.nvim_exec_autocmds("InsertLeave", { group = "lumen_lint" })
        vim.wait(250)
      end
      -- start from an empty cache
      vim.api.nvim_exec_autocmds("User", { pattern = "LumenToolInstalled" })
      trigger()
      trigger()
      assert(calls == 1, ("resolved %d times for two lint runs"):format(calls))
      vim.api.nvim_exec_autocmds("User", { pattern = "LumenToolInstalled" })
      trigger()
      assert(calls == 2, ("an install didn't reset the cache (%d resolves)"):format(calls))
    end)
    lint._resolve_linter_by_ft = orig
    assert(ok, err)
  end)

  check("packs: disabling a pack that another pack extends says why it stays on", function()
    local packs = require("lumen.packs")
    local warned, orig = {}, { warn = Lumen.warn, notify = Lumen.notify, prompt = packs.prompt_restart }
    Lumen.warn = function(msg)
      warned[#warned + 1] = msg
    end
    Lumen.notify, packs.prompt_restart = function() end, function() end
    local ok, err = pcall(with_pack_state, function()
      packs.set("vue", true)
      packs.toggle("typescript", false)
      assert(packs.enabled().typescript, "typescript should stay on while vue extends it")
      assert(table.concat(warned, "\n"):find("the `vue` pack extends it", 1, true), vim.inspect(warned))
    end)
    Lumen.warn, Lumen.notify, packs.prompt_restart = orig.warn, orig.notify, orig.prompt
    assert(ok, err)
  end)

  check(
    "lsp: Mason batches are deduped, a failed registry refresh is reported, the update check installs nothing",
    function()
      local lsp = require("lumen.lsp")
      -- stub only these two on the real module: other code (mason-lspconfig) uses the rest
      local registry = require("mason-registry")
      local real = { refresh = registry.refresh, get_package = registry.get_package }
      local installs, refreshed, errors = {}, 0, {}
      local refresh_ok = true
      registry.refresh = function(cb)
        refreshed = refreshed + 1
        cb(refresh_ok)
      end
      registry.get_package = function(name)
        return {
          name = name,
          is_installed = function()
            return false
          end,
          is_installing = function()
            return false
          end,
          install = function(_, _, done)
            installs[#installs + 1] = name
            done(true)
          end,
        }
      end
      local orig = { error = Lumen.error, notify = Lumen.notify }
      Lumen.error = function(msg)
        errors[#errors + 1] = msg
      end
      Lumen.notify = function() end
      local ok, err = pcall(function()
        -- regression: vue/astro + typescript put prettierd in one batch twice: "already installing"
        lsp._install({ "prettierd", "prettierd", "eslint_d" })
        vim.wait(200)
        table.sort(installs)
        assert(vim.deep_equal(installs, { "eslint_d", "prettierd" }), vim.inspect(installs))
        -- regression: offline, every tool was reported as an unknown package
        refresh_ok = false
        lsp._install({ "stylua" })
        vim.wait(200)
        -- (installs queued by earlier checks may land in this window too: same message for each)
        assert(#errors > 0, "no error for a failed registry refresh")
        for _, e in ipairs(errors) do
          assert(e:find("refresh Mason's registry", 1, true), vim.inspect(errors))
        end
        -- the `:Lumen update` check (LUMEN_SELFTEST) starts no installs it would leave half-done
        refresh_ok, refreshed = true, 0
        vim.env.LUMEN_SELFTEST = "1"
        lsp._install({ "stylua" })
        vim.env.LUMEN_SELFTEST = nil
        vim.wait(100)
        assert(refreshed == 0, "the update check touched Mason")
      end)
      vim.env.LUMEN_SELFTEST = nil
      registry.refresh, registry.get_package = real.refresh, real.get_package
      Lumen.error, Lumen.notify = orig.error, orig.notify
      assert(ok, err)
    end
  )
end
