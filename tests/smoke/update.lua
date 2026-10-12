-- :Lumen update / rollback, stable channel (run by tests/smoke.lua)
---@param t lumen.test.Helpers
return function(t)
  local check, wait, child, fake_server, SLOW = t.check, t.wait, t.child, t.fake_server, t.SLOW

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

  check("stable channel: vetted versions pin known plugins, your extras stay on latest", function()
    local up = require("lumen.update")
    local merged, pinned, extras = up.merge_lock({
      ["flash.nvim"] = { branch = "main", commit = "new" },
      ["my-plugin"] = { branch = "main", commit = "mine" },
      lumen = { branch = "main", commit = "x" },
    }, {
      ["flash.nvim"] = { branch = "main", commit = "vetted" },
      ["not-installed"] = { branch = "main", commit = "y" },
    })
    assert(merged["flash.nvim"].commit == "vetted", vim.inspect(merged))
    assert(merged["my-plugin"].commit == "mine" and merged["not-installed"] == nil, vim.inspect(merged))
    assert(
      vim.deep_equal(pinned, { "flash.nvim" }) and vim.deep_equal(extras, { "my-plugin" }),
      vim.inspect({ pinned, extras })
    )

    -- the whole flow, with lazy.nvim's restore/update stubbed (no network) and the real lockfile restored after
    local lockfile = vim.fn.stdpath("config") .. "/lazy-lock.json"
    local saved = vim.fn.filereadable(lockfile) == 1 and vim.fn.readfile(lockfile) or nil
    local lazy = require("lazy.manage")
    local calls, orig = {}, { restore = lazy.restore, update = lazy.update, vetted = up.vetted, verify = up.verify }
    -- the restart prompt is a blocking vim.ui.select in headless runs
    local packs = require("lumen.packs")
    local prompt = packs.prompt_restart
    packs.prompt_restart = function() end
    local ok, err = pcall(function()
      local current = vim.json.decode(table.concat(vim.fn.readfile(lockfile), "\n"))
      local some = next(current)
      lazy.restore = function(opts)
        calls.restore = opts.plugins
      end
      lazy.update = function(opts)
        calls.update = calls.update or {}
        vim.list_extend(calls.update, opts.plugins or {})
      end
      up.vetted = function()
        return { [some] = { branch = current[some].branch, commit = "0000000000000000000000000000000000000000" } }
      end
      up.verify = function(cb)
        calls.verified = true
        cb(true, {})
      end
      require("lumen.config").update_channel = "stable"
      up.update()
      assert(
        wait(5000 * SLOW, function()
          return calls.verified
        end),
        "the update never reached verification: " .. vim.inspect(calls)
      )
      local written = vim.json.decode(table.concat(vim.fn.readfile(lockfile), "\n"))
      assert(written[some].commit == "0000000000000000000000000000000000000000", "vetted commit not written")
      assert(
        vim.deep_equal(calls.restore, { some }),
        "restore should pin exactly the vetted plugins: " .. vim.inspect(calls)
      )
      assert(not vim.tbl_contains(calls.update or {}, some), "a vetted plugin was also updated to latest")
    end)
    vim.wait(200)
    lazy.restore, lazy.update, up.vetted, up.verify = orig.restore, orig.update, orig.vetted, orig.verify
    packs.prompt_restart = prompt
    if saved then
      vim.fn.writefile(saved, lockfile)
    end
    for _, snap in ipairs(up.snapshots()) do
      os.remove(snap.path)
    end
    assert(ok, err)
  end)

  check("rollback really moves plugins (real lazy.nvim, in the same session as an update)", function()
    -- regression: lazy caches the lockfile and its load() is a no-op once run, and an async restore
    -- recorded the current commits before checking out, so rollbacks silently did nothing
    local up = require("lumen.update")
    local dir = require("lazy.core.config").plugins["flash.nvim"].dir
    local function head()
      return vim.trim(vim.fn.system({ "git", "-C", dir, "rev-parse", "HEAD" }))
    end
    local lockfile = vim.fn.stdpath("config") .. "/lazy-lock.json"
    local saved = vim.fn.readfile(lockfile)
    local current = head()
    local older = vim.trim(vim.fn.system({ "git", "-C", dir, "rev-parse", "HEAD~1" }))
    -- restore() prompts for a restart once parsers are synced again (async): count the prompts
    local prompt, prompts = require("lumen.packs").prompt_restart, 0
    require("lumen.packs").prompt_restart = function()
      prompts = prompts + 1
    end
    local ok, err = pcall(function()
      local lock = vim.json.decode(table.concat(saved, "\n"))
      lock["flash.nvim"].commit = older
      local tmp = vim.fn.tempname()
      vim.fn.writefile({ vim.json.encode(lock) }, tmp)
      up.restore(tmp)
      assert(head() == older, ("restore did not move flash.nvim: %s, wanted %s"):format(head(), older))
      local back = vim.fn.tempname()
      vim.fn.writefile(saved, back)
      up.restore(back)
      assert(head() == current, ("rollback did not return flash.nvim: %s, wanted %s"):format(head(), current))
    end)
    -- both restores prompt after their parser sync: let those land on the stub, not a real prompt
    wait(30000 * SLOW, function()
      return prompts >= 2
    end)
    require("lumen.packs").prompt_restart = prompt
    vim.fn.writefile(saved, lockfile)
    if head() ~= current then
      require("lazy.manage").restore({ plugins = { "flash.nvim" }, wait = true, show = false })
    end
    assert(ok, err)
    assert(prompts >= 2, "a rollback never finished its parser sync (no restart prompt)")
  end)

  check("update: errors printed to stderr fail the verification", function()
    local up = require("lumen.update")
    -- Lua errors in autocmds and callbacks never reach vim.notify: headless Neovim prints them
    local out = vim
      .system({
        vim.v.progpath,
        "--clean",
        "--headless",
        "-c",
        "lua vim.api.nvim_create_autocmd('User', { pattern = 'X', callback = function() error('lumen-boom') end })",
        "-c",
        "doautocmd User X",
        "-c",
        "qa!",
      }, { text = true })
      :wait(10000 * SLOW)
    local errors = up.stderr_errors(out.stderr)
    assert(table.concat(errors, "\n"):find("lumen-boom", 1, true), "error not found in stderr:\n" .. (out.stderr or ""))
    local sample =
      "Some info line\nError executing lua callback: x.lua:1: boom\nstack traceback:\n\tx.lua:1: in f\nE5108: also bad\nfine again"
    local parsed = up.stderr_errors(sample)
    assert(#parsed == 4 and parsed[1]:find("^Error executing") and parsed[4] == "E5108: also bad", vim.inspect(parsed))
    -- parsers are synced through a callback that always fires (rollback and update both wait on it)
    local done = false
    up.update_parsers(function()
      done = true
    end, false)
    assert(
      wait(30000 * SLOW, function()
        return done
      end),
      "update_parsers never called back"
    )
  end)

  check("update: what's new comes from NEWS.md, newer than the running version", function()
    local up = require("lumen.update")
    local sections = up.parse_news("# News\n\n## 1.2.0 — x\n- a\n\n## v1.1.0\n- b\n")
    assert(#sections == 2 and sections[1].version == "1.2.0" and sections[2].version == "1.1.0", vim.inspect(sections))
    local version = require("lumen").version
    assert(up.installed_version() == version, ("on disk %s, running %s"):format(up.installed_version(), version))
    local news = table.concat(up.news_since("0.0.1"), "\n")
    assert(news:find("## " .. version, 1, true), "NEWS.md has no section for " .. version)
    assert(#up.news_since(version) == 0, "news for the running version shows as new")
    local errmsg = vim.v.errmsg
    up.news("0.0.1")
    assert(vim.bo.filetype == "markdown" and vim.api.nvim_buf_get_lines(0, 0, 1, false)[1]:find("What's new"))
    vim.cmd.close()
    -- render-markdown.nvim loads on the first markdown buffer and leaves this (caught) error behind
    if vim.v.errmsg == "E31: No such mapping" then
      vim.v.errmsg = errmsg
    end
  end)
end
