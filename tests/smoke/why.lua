-- :Lumen why / :Lumen doctor (run by tests/smoke.lua)
---@param t lumen.test.Helpers
return function(t)
  local check, wait, child, fake_server, SLOW = t.check, t.wait, t.child, t.fake_server, t.SLOW

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

  check("why: no false alarm for a filetype without a treesitter parser", function()
    local buf = vim.api.nvim_create_buf(false, true)
    vim.bo[buf].filetype = "org"
    local text = table.concat(require("lumen.why").report(buf), "\n")
    vim.api.nvim_buf_delete(buf, { force = true })
    assert(text:find("no treesitter parser exists for `org`", 1, true), text)
    assert(not text:find("✗ no `org` parser", 1, true), text)
  end)

  check("doctor: deep report, JSON export and one-key fixes", function()
    vim.cmd.edit("lua/lumen/init.lua")
    wait(20000 * SLOW, function()
      return #vim.lsp.get_clients({ bufnr = 0, name = "lua_ls" }) > 0
    end)
    local why = require("lumen.why")
    local text = table.concat(why.report(0, { deep = true }), "\n")
    assert(text:find("## Environment", 1, true) and text:find("update channel", 1, true), text)
    assert(text:find("· command `lua-language-server", 1, true), "no binary details:\n" .. text)
    assert(text:find("· supports: ", 1, true), "no capabilities:\n" .. text)
    local data = vim.json.decode(why.json(0))
    assert(data.filetype == "lua" and #data.report > 10 and data.attached[1], vim.inspect(data))
    -- the fix for a status line is the → line under it; a line without one has no fix
    local lines = { "✗ `x` not installed", "   → `:MasonInstall x`", "✓ fine", "! off", "   → `<leader>uT`" }
    assert(why.fix_at(lines, 1) == ":MasonInstall x", tostring(why.fix_at(lines, 1)))
    assert(why.fix_at(lines, 2) == ":MasonInstall x")
    assert(why.fix_at(lines, 3) == nil)
    assert(why.fix_at(lines, 4) == "<leader>uT")
    assert(vim.fn.maparg("<leader>cD", "n") ~= "", "<leader>cD not mapped")
  end)

  check("doctor: the JSON export hides your home directory, log lines and roots included", function()
    local why = require("lumen.why")
    local out = why._redact({ a = "/home/u/x", b = { "/home/u", "/home/u-other/y" }, c = 1 }, "/home/u")
    assert(vim.deep_equal(out, { a = "~/x", b = { "~", "~-other/y" }, c = 1 }), vim.inspect(out))
    -- pattern characters in a home path are matched literally
    assert(why._redact("/h/a-b.c%/f", "/h/a-b.c%") == "~/f", why._redact("/h/a-b.c%/f", "/h/a-b.c%"))
    vim.cmd.edit("lua/lumen/init.lua")
    local home = vim.fs.normalize(assert(vim.uv.os_homedir()))
    local json = why.json(0)
    assert(not json:find(home .. "/", 1, true), "home directory in the doctor JSON:\n" .. json)
  end)

  check("why: a pack's missing toolchain is reported with the pack", function()
    local packs = require("lumen.packs")
    local orig = packs.missing
    packs.missing = function()
      return { "lumen-fake-toolchain" }
    end
    local ok, text = pcall(function()
      vim.cmd.edit("lua/lumen/init.lua")
      return table.concat(require("lumen.why").report(0), "\n")
    end)
    packs.missing = orig
    assert(ok, text)
    assert(text:find("`lumen-fake-toolchain` not found on PATH — the `lua` pack needs it", 1, true), text)
  end)
end
