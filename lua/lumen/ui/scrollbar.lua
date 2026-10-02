-- Lumen scrollbar: a 1-column overlay on the right edge of each window showing the
-- viewport plus marks for diagnostics, git hunks, search matches and multicursors.
-- No plugin; one tiny float per window, only for buffers taller than the window.

local M = {}

local ns = vim.api.nvim_create_namespace("lumen.scrollbar")
local mc_ns = vim.api.nvim_create_namespace("nvim.multicursor")

---@type table<integer, {win:integer, buf:integer}> target window → scrollbar float
local bars = {}
---@type table<integer, {diag?:table, search?:integer[], search_key?:string, mc?:table, mc_at?:number}>
local sources = {}

local KIND = {
  [vim.diagnostic.severity.ERROR] = "error",
  [vim.diagnostic.severity.WARN] = "warn",
  [vim.diagnostic.severity.INFO] = "info",
  [vim.diagnostic.severity.HINT] = "hint",
}

-- mark priority (higher wins a cell) and glyph / highlight
local MARKS = {
  error = { 60, "━", "LumenScrollError" },
  warn = { 50, "━", "LumenScrollWarn" },
  cursor = { 45, "━", "LumenScrollCursors" },
  search = { 40, "─", "LumenScrollSearch" },
  add = { 30, "▐", "LumenScrollAdd" },
  change = { 30, "▐", "LumenScrollChange" },
  delete = { 30, "▐", "LumenScrollDelete" },
  info = { 20, "─", "LumenScrollInfo" },
  hint = { 10, "─", "LumenScrollHint" },
}

local function eligible(win)
  if not vim.api.nvim_win_is_valid(win) or vim.api.nvim_win_get_config(win).relative ~= "" then
    return false
  end
  local buf = vim.api.nvim_win_get_buf(win)
  local bt = vim.bo[buf].buftype
  return (bt == "" or bt == "help") and vim.api.nvim_win_get_height(win) >= 5 and vim.api.nvim_win_get_width(win) >= 20
end

local function close(win)
  local bar = bars[win]
  if bar and vim.api.nvim_win_is_valid(bar.win) then
    vim.api.nvim_win_close(bar.win, true)
  end
  bars[win] = nil
end

---@param win integer
local function render(win)
  if not eligible(win) then
    return close(win)
  end
  local buf = vim.api.nvim_win_get_buf(win)
  local total = vim.api.nvim_buf_line_count(buf)
  -- text rows only: nvim_win_get_height() counts the winbar on newer Neovims, which made the
  -- bar (anchored below the winbar) spill onto the separator / statusline row
  local height = vim.fn.winheight(win)
  if total <= height then
    return close(win)
  end

  local function row(lnum) -- 1-based line → 0-based bar row
    return math.min(height - 1, math.floor((lnum - 1) / total * height))
  end

  ---@type table<integer, string> row → mark kind
  local cells = {}
  local function mark(lnum, kind)
    local r = row(lnum)
    local cur = cells[r]
    if not cur or MARKS[kind][1] > MARKS[cur][1] then
      cells[r] = kind
    end
  end

  local src = sources[buf] or {}
  sources[buf] = src

  -- diagnostics: vim.diagnostic.get() deep-copies every item (~9ms for 5k), so cache the
  -- line positions per buffer and rebuild only on DiagnosticChanged
  if not src.diag then
    local list = {}
    for _, d in ipairs(vim.diagnostic.get(buf)) do
      list[#list + 1] = { d.lnum + 1, KIND[d.severity] or "hint" }
    end
    src.diag = list
  end
  for _, d in ipairs(src.diag) do
    mark(d[1], d[2])
  end

  local gs = package.loaded.gitsigns
  if gs then
    for _, h in ipairs(gs.get_hunks(buf) or {}) do
      local kind = h.type == "add" and "add" or (h.type == "delete" and "delete" or "change")
      local start = math.max(h.added.start, 1)
      for l = start, start + math.max(h.added.count, 1) - 1, math.max(1, math.floor(total / height)) do
        mark(l, kind)
      end
    end
  end

  -- search hits, cached per pattern + buffer version
  local pattern = vim.v.hlsearch == 1 and vim.fn.getreg("/") or ""
  if pattern ~= "" and total < 100000 then
    local key = pattern .. "\0" .. vim.b[buf].changedtick
    if src.search_key ~= key then
      local ok, matches = pcall(vim.fn.matchbufline, buf, pattern, 1, "$")
      local list = {}
      for i, m in ipairs(ok and matches or {}) do
        if i > 5000 then
          break
        end
        list[#list + 1] = m.lnum
      end
      src.search, src.search_key = list, key
    end
    for _, l in ipairs(src.search) do
      mark(l, "search")
    end
  end

  -- multicursors: any extmark query scans the whole mark tree (~0.3ms on busy buffers),
  -- so look at most every 250ms
  local now = vim.uv.now()
  if not src.mc or now - src.mc_at > 250 then
    src.mc, src.mc_at = vim.api.nvim_buf_get_extmarks(buf, mc_ns, 0, -1, {}), now
  end
  for _, m in ipairs(src.mc) do
    mark(m[2] + 1, "cursor")
  end

  -- viewport thumb
  local top, bot = vim.fn.line("w0", win), vim.fn.line("w$", win)
  local t1, t2 = row(top), math.max(row(top), row(bot))

  local lines = {}
  for r = 0, height - 1 do
    lines[r + 1] = cells[r] and MARKS[cells[r]][2] or " "
  end

  local bar = bars[win]
  if not (bar and vim.api.nvim_win_is_valid(bar.win) and vim.api.nvim_buf_is_valid(bar.buf)) then
    local b = vim.api.nvim_create_buf(false, true)
    vim.bo[b].bufhidden = "wipe"
    local w = vim.api.nvim_open_win(b, false, {
      relative = "win",
      win = win,
      row = 0,
      col = vim.api.nvim_win_get_width(win) - 1,
      width = 1,
      height = height,
      focusable = false,
      style = "minimal",
      border = "none",
      zindex = 20,
      noautocmd = true,
    })
    vim.wo[w].winhighlight = "Normal:LumenScrollTrack,NormalFloat:LumenScrollTrack"
    vim.wo[w].winblend = 0
    bar = { win = w, buf = b }
    bars[win] = bar
  else
    vim.api.nvim_win_set_config(bar.win, {
      relative = "win",
      win = win,
      row = 0,
      col = vim.api.nvim_win_get_width(win) - 1,
      height = height,
    })
  end

  vim.api.nvim_buf_set_lines(bar.buf, 0, -1, false, lines)
  vim.api.nvim_buf_clear_namespace(bar.buf, ns, 0, -1)
  for r = 0, height - 1 do
    local in_thumb = r >= t1 and r <= t2
    local kind = cells[r]
    local hl = kind and MARKS[kind][3] or nil
    if hl and in_thumb then
      hl = hl .. "Thumb"
    elseif not hl then
      hl = in_thumb and "LumenScrollThumb" or nil
    end
    if hl then
      vim.api.nvim_buf_set_extmark(bar.buf, ns, r, 0, { end_col = #lines[r + 1], hl_group = hl, hl_eol = true })
    end
  end
end

local function refresh_all()
  for win in pairs(bars) do
    if not vim.api.nvim_win_is_valid(win) then
      close(win)
    end
  end
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    pcall(render, win)
  end
end

M.refresh = function()
  pcall(refresh_all)
end

function M.setup()
  local group = vim.api.nvim_create_augroup("lumen_scrollbar", { clear = true })
  local timer = assert(vim.uv.new_timer())
  local function schedule(delay)
    timer:stop()
    timer:start(delay, 0, vim.schedule_wrap(refresh_all))
  end
  -- scrolling must feel instant; content changes can wait a bit
  vim.api.nvim_create_autocmd({ "WinScrolled", "WinResized", "VimResized", "BufWinEnter", "TabEnter", "WinEnter" }, {
    group = group,
    callback = function()
      schedule(10)
    end,
  })
  vim.api.nvim_create_autocmd({ "TextChanged", "InsertLeave", "DiagnosticChanged", "CmdlineLeave" }, {
    group = group,
    callback = function(ev)
      if ev.event == "DiagnosticChanged" and sources[ev.buf] then
        sources[ev.buf].diag = nil
      end
      schedule(150)
    end,
  })
  vim.api.nvim_create_autocmd("BufWipeout", {
    group = group,
    callback = function(ev)
      sources[ev.buf] = nil
    end,
  })
  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = "GitSignsUpdate",
    callback = function()
      schedule(150)
    end,
  })
  vim.api.nvim_create_autocmd("WinClosed", {
    group = group,
    callback = function(ev)
      local win = tonumber(ev.match)
      if win then
        -- closing the float itself, or its target
        for target, bar in pairs(bars) do
          if target == win or bar.win == win then
            bars[target] = nil
            if bar.win ~= win and vim.api.nvim_win_is_valid(bar.win) then
              pcall(vim.api.nvim_win_close, bar.win, true)
            end
          end
        end
      end
    end,
  })
  schedule(50)
end

return M
