-- Lumen's UI and editing basics: treesitter, statusline, tabline, winbar, folds, scrollbar, perf budgets (run by tests/smoke.lua)
---@param t lumen.test.Helpers
return function(t)
  local check, wait, child, fake_server, SLOW = t.check, t.wait, t.child, t.fake_server, t.SLOW

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
    -- the best of 5 batches: on a shared CI runner one GC pause or preemption can push the mean of a
    -- single batch several times over budget; a real regression is slow in every batch
    local function cost(fn, n)
      fn()
      local best = math.huge
      for _ = 1, 5 do
        local t = vim.uv.hrtime()
        for _ = 1, math.ceil(n / 5) do
          fn()
        end
        best = math.min(best, (vim.uv.hrtime() - t) / math.ceil(n / 5) / 1000)
      end
      return best
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
end
