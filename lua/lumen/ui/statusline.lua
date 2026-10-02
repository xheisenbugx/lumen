-- Lumen statusline: a single global line, no plugin, rendered in well under 0.1ms.
--
--  ◖ NORMAL ◗  main +3 ~1   lua/lumen/init.lua ●      ✖ 2 ⚠ 1   󰒋 lua_ls   lua  ◖ 12:4 · 38% ◗

local icons = require("lumen.icons")

local M = {}

local spinner = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }

local modes = {
  n = { "NORMAL", "Normal" },
  no = { "PENDING", "Normal" },
  nt = { "NORMAL", "Normal" },
  v = { "VISUAL", "Visual" },
  V = { "V-LINE", "Visual" },
  ["\22"] = { "V-BLOCK", "Visual" },
  s = { "SELECT", "Visual" },
  S = { "S-LINE", "Visual" },
  ["\19"] = { "S-BLOCK", "Visual" },
  i = { "INSERT", "Insert" },
  ic = { "INSERT", "Insert" },
  ix = { "INSERT", "Insert" },
  R = { "REPLACE", "Replace" },
  Rv = { "V-REPLACE", "Replace" },
  c = { "COMMAND", "Command" },
  cv = { "EX", "Command" },
  r = { "PROMPT", "Command" },
  rm = { "MORE", "Command" },
  ["r?"] = { "CONFIRM", "Command" },
  ["!"] = { "SHELL", "Terminal" },
  t = { "TERMINAL", "Terminal" },
}

-- friendly labels for special buffers
local special = {
  lazy = "󰒲  Lazy",
  mason = "󱌢  Mason",
  oil = "  Oil",
  snacks_dashboard = "󰛨  Lumen",
  snacks_picker_input = "  Picker",
  snacks_picker_list = "  Explorer",
  checkhealth = "󰓙  Health",
  help = "󰋖  Help",
  qf = "  Quickfix",
  trouble = "  Trouble",
  ["grug-far"] = "  Search & Replace",
  lazygit = "  Lazygit",
  snacks_terminal = "  Terminal",
}

local function esc(s)
  return (s:gsub("%%", "%%%%"))
end

local function hl(group, text)
  return "%#" .. group .. "#" .. text
end

local function mode()
  local m = vim.api.nvim_get_mode().mode
  local info = modes[m] or modes[m:sub(1, 1)] or { m:upper(), "Normal" }
  local group = "LumenStlMode" .. info[2]
  return hl(group .. "Sep", "") .. hl(group, " " .. info[1] .. " ") .. hl(group .. "Sep", "")
end

local function git(buf)
  local head = vim.b[buf].gitsigns_head or vim.g.gitsigns_head
  if not head or head == "" then
    return ""
  end
  local out = { hl("LumenStlBranch", icons.git.branch .. esc(head)) }
  local d = vim.b[buf].gitsigns_status_dict
  if d then
    if (d.added or 0) > 0 then
      out[#out + 1] = hl("LumenStlAdded", icons.git.added .. d.added)
    end
    if (d.changed or 0) > 0 then
      out[#out + 1] = hl("LumenStlChanged", icons.git.changed .. d.changed)
    end
    if (d.removed or 0) > 0 then
      out[#out + 1] = hl("LumenStlRemoved", icons.git.removed .. d.removed)
    end
  end
  return table.concat(out, " ")
end

local function file(buf)
  local ft = vim.bo[buf].filetype
  if special[ft] then
    return hl("LumenStlFile", special[ft])
  end
  local name = vim.api.nvim_buf_get_name(buf)
  if vim.bo[buf].buftype == "terminal" then
    return hl("LumenStlFile", "  " .. esc(vim.fn.fnamemodify(name, ":t")))
  end
  if name == "" then
    return hl("LumenStlDim", "[No Name]")
  end

  local rel = vim.fn.fnamemodify(name, ":~:.")
  if #rel > math.floor(vim.o.columns * 0.4) then
    rel = vim.fn.pathshorten(rel, 2)
  end
  local dir, base = rel:match("^(.*/)([^/]*)$")
  if not dir then
    dir, base = "", rel
  end

  local icon, icon_hl = "󰈔", "LumenStlDim"
  local i, h = Lumen.icon("file", name)
  icon, icon_hl = i or icon, h or icon_hl

  local s = hl(M.icon_hl(icon_hl), icon .. " ") .. hl("LumenStlDim", esc(dir)) .. hl("LumenStlFile", esc(base))
  if vim.bo[buf].modified then
    s = s .. hl("LumenStlModified", " " .. icons.misc.modified)
  end
  if vim.bo[buf].readonly or not vim.bo[buf].modifiable then
    s = s .. hl("LumenStlDim", " " .. icons.misc.readonly)
  end
  return s
end

-- per-buffer diagnostic counts, invalidated on DiagnosticChanged
local diag_cache = {}

local function diagnostics(buf)
  local counts = diag_cache[buf]
  if not counts then
    counts = vim.diagnostic.count(buf)
    diag_cache[buf] = counts
  end
  local out = {}
  for sev, name in ipairs({ "Error", "Warn", "Info", "Hint" }) do
    local n = counts[sev]
    if n and n > 0 then
      out[#out + 1] = hl("LumenStl" .. name, icons.diagnostics[name] .. n)
    end
  end
  return table.concat(out, " ")
end

local function lsp(buf)
  local status = vim.lsp.status()
  if status ~= "" then
    local frame = spinner[math.floor(vim.uv.hrtime() / 1e8) % #spinner + 1]
    -- truncate by characters, then escape: cutting bytes could split a multibyte char or a "%%"
    if vim.fn.strchars(status) > 40 then
      status = vim.fn.strcharpart(status, 0, 39) .. "…"
    end
    return hl("LumenStlProgress", frame .. " " .. esc(status))
  end
  local names = {}
  for _, c in ipairs(vim.lsp.get_clients({ bufnr = buf })) do
    if c.name ~= "copilot" then
      names[#names + 1] = c.name
    end
  end
  if #names == 0 then
    return ""
  end
  return hl("LumenStlLsp", icons.misc.lsp .. esc(table.concat(names, " ")))
end

local mc_ns = vim.api.nvim_create_namespace("nvim.multicursor")
local mc = { buf = -1, at = 0, n = 0 }
local search = { key = nil, res = {} }

local function extras()
  local out = {}
  -- org.nvim clock / timer (empty unless one is running)
  local org = package.loaded["org"]
  if org and org.statusline then
    local ok, clock = pcall(org.statusline)
    if ok and clock and clock ~= "" then
      out[#out + 1] = hl("LumenStlProgress", esc(clock))
    end
  end
  local tasks = package.loaded["lumen.tasks"]
  if tasks and next(tasks.running) then
    local frame = spinner[math.floor(vim.uv.hrtime() / 1e8) % #spinner + 1]
    out[#out + 1] = hl("LumenStlTask", frame .. " " .. esc(tasks.status()))
  end
  if vim.api.nvim_mcursor then
    -- extmark queries scan the whole mark tree (~0.3ms on busy buffers): sample at most every 250ms
    local buf, now = vim.api.nvim_get_current_buf(), vim.uv.now()
    if mc.buf ~= buf or now - mc.at > 250 then
      mc.buf, mc.at, mc.n = buf, now, #vim.api.nvim_buf_get_extmarks(buf, mc_ns, 0, -1, {})
    end
    local n = mc.n
    if n > 0 then
      out[#out + 1] = hl("LumenStlCursors", icons.misc.cursors .. (n + 1) .. " cursors")
    end
  end
  local reg = vim.fn.reg_recording()
  if reg ~= "" then
    out[#out + 1] = hl("LumenStlRecording", icons.misc.recording .. "@" .. reg)
  end
  if vim.v.hlsearch == 1 then
    -- searchcount() rescans the buffer (~1.5ms on 40k lines): reuse it until something changes
    local cur = vim.api.nvim_win_get_cursor(0)
    local key =
      table.concat({ vim.fn.getreg("/"), vim.api.nvim_get_current_buf(), vim.b.changedtick, cur[1], cur[2] }, "\0")
    if search.key ~= key then
      local ok, res = pcall(vim.fn.searchcount, { maxcount = 999, timeout = 20 })
      search.key, search.res = key, ok and res or {}
    end
    local sc = search.res
    if sc.total and sc.total > 0 then
      out[#out + 1] = hl("LumenStlDim", icons.misc.search .. ("%d/%d"):format(sc.current, sc.total))
    end
  end
  return table.concat(out, "  ")
end

local function filetype(buf)
  local ft = vim.bo[buf].filetype
  if ft == "" or special[ft] then
    return ""
  end
  local icon, icon_hl = "", "LumenStlDim"
  local i, h = Lumen.icon("filetype", ft)
  icon, icon_hl = i or icon, h or icon_hl
  return hl(M.icon_hl(icon_hl), icon .. " ") .. hl("LumenStl", ft)
end

local function position()
  return hl("LumenStlPosSep", "") .. hl("LumenStlPos", " %l:%v  %P ") .. hl("LumenStlPosSep", "")
end

-- icon highlight groups re-based onto the statusline background
local icon_cache = {}
function M.icon_hl(group)
  if icon_cache[group] then
    return icon_cache[group]
  end
  local name = "LumenStlIcon" .. group
  local fg = vim.api.nvim_get_hl(0, { name = group, link = false }).fg
  local bg = vim.api.nvim_get_hl(0, { name = "LumenStl", link = false }).bg
  vim.api.nvim_set_hl(0, name, { fg = fg, bg = bg })
  icon_cache[group] = name
  return name
end

local function join(parts, sep)
  local out = {}
  for _, p in ipairs(parts) do
    if p ~= "" then
      out[#out + 1] = p
    end
  end
  return table.concat(out, sep)
end

function M.render()
  local win = vim.g.statusline_winid or vim.api.nvim_get_current_win()
  local buf = vim.api.nvim_win_get_buf(win)
  local wide = vim.o.columns >= 100

  local left = join({ mode(), git(buf), file(buf) }, hl("LumenStl", "  "))
  local right = join({
    extras(),
    diagnostics(buf),
    wide and lsp(buf) or "",
    wide and filetype(buf) or "",
    position(),
  }, hl("LumenStl", "   "))

  return hl("LumenStl", " ") .. left .. hl("LumenStl", "%=") .. right .. hl("LumenStl", " ")
end

function M.setup()
  vim.o.statusline = "%!v:lua.require'lumen.ui.statusline'.render()"
  local group = vim.api.nvim_create_augroup("lumen_statusline", { clear = true })
  vim.api.nvim_create_autocmd("ColorScheme", {
    group = group,
    callback = function()
      icon_cache = {}
    end,
  })
  -- keep the lsp spinner moving & clear it when work finishes
  local timer = vim.uv.new_timer()
  vim.api.nvim_create_autocmd("LspProgress", {
    group = group,
    callback = function()
      vim.cmd.redrawstatus()
      if timer and not timer:is_active() then
        timer:start(
          100,
          100,
          vim.schedule_wrap(function()
            vim.cmd.redrawstatus()
            if vim.lsp.status() == "" then
              timer:stop()
            end
          end)
        )
      end
    end,
  })
  vim.api.nvim_create_autocmd({ "RecordingEnter", "RecordingLeave", "DiagnosticChanged", "BufWipeout" }, {
    group = group,
    callback = function(ev)
      diag_cache[ev.buf] = nil
      vim.schedule(vim.cmd.redrawstatus)
    end,
  })
end

return M
