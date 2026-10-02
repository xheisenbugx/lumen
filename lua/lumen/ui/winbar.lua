-- Lumen winbar: per-window breadcrumbs  dir › file › Class › method
-- Native LSP document symbols, cached by changedtick; no plugin. Click a crumb to jump.

local M = {}

local SEP = "%#LumenWinbarSep# › "

-- symbol kinds worth showing (LSP SymbolKind)
local KINDS = {
  [2] = "Module",
  [3] = "Namespace",
  [4] = "Package",
  [5] = "Class",
  [6] = "Method",
  [7] = "Property",
  [8] = "Field",
  [9] = "Constructor",
  [10] = "Enum",
  [11] = "Interface",
  [12] = "Function",
  [19] = "Object",
  [20] = "Key",
  [22] = "EnumMember",
  [23] = "Struct",
  [26] = "TypeParameter",
}

---@class lumen.winbar.Symbol
---@field name string
---@field kind integer
---@field range {start:{line:integer, character:integer}, ["end"]:{line:integer, character:integer}}
---@field children lumen.winbar.Symbol[]

---@type table<integer, {tick:integer, symbols:lumen.winbar.Symbol[]}>
local cache = {}
---@type table<integer, lumen.winbar.Symbol[]> last rendered crumbs per window (for clicks)
local rendered = {}

local function esc(s)
  return (s:gsub("%%", "%%%%"))
end

local function contains(range, line, col)
  local s, e = range.start, range["end"]
  if line < s.line or line > e.line then
    return false
  end
  if line == s.line and col < s.character then
    return false
  end
  if line == e.line and col > e.character then
    return false
  end
  return true
end

-- SymbolInformation[] (flat) → nested, by range containment
local function nest(flat)
  table.sort(flat, function(a, b)
    local ra, rb = a.location.range, b.location.range
    if ra.start.line ~= rb.start.line then
      return ra.start.line < rb.start.line
    end
    return ra["end"].line > rb["end"].line
  end)
  local root, stack = {}, {}
  for _, s in ipairs(flat) do
    local node = { name = s.name, kind = s.kind, range = s.location.range, children = {} }
    while #stack > 0 and not contains(stack[#stack].range, node.range.start.line, node.range.start.character) do
      stack[#stack] = nil
    end
    table.insert(#stack > 0 and stack[#stack].children or root, node)
    stack[#stack + 1] = node
  end
  return root
end

local function normalize(result)
  if not result or #result == 0 then
    return {}
  end
  if result[1].location then
    return nest(result)
  end
  local function walk(list)
    local out = {}
    for _, s in ipairs(list) do
      out[#out + 1] = { name = s.name, kind = s.kind, range = s.range, children = walk(s.children or {}) }
    end
    return out
  end
  return walk(result)
end

local pending = {}

---@param buf integer
function M.request(buf)
  if not vim.api.nvim_buf_is_valid(buf) or pending[buf] then
    return
  end
  local tick = vim.b[buf].changedtick
  if cache[buf] and cache[buf].tick == tick then
    return
  end
  local client = vim.lsp.get_clients({ bufnr = buf, method = "textDocument/documentSymbol" })[1]
  if not client then
    return
  end
  pending[buf] = true
  client:request(
    "textDocument/documentSymbol",
    { textDocument = vim.lsp.util.make_text_document_params(buf) },
    function(err, result)
      pending[buf] = nil
      if err or not vim.api.nvim_buf_is_valid(buf) then
        return
      end
      cache[buf] = { tick = tick, symbols = normalize(result) }
      vim.schedule(function()
        pcall(vim.cmd.redrawstatus, { bang = true })
      end)
    end,
    buf
  )
end

---@param symbols lumen.winbar.Symbol[]
local function path_at(symbols, line, col)
  local out = {}
  local list = symbols
  while list do
    local next_list
    for _, s in ipairs(list) do
      if contains(s.range, line, col) then
        if KINDS[s.kind] then
          out[#out + 1] = s
        end
        next_list = s.children
        break
      end
    end
    list = next_list
  end
  return out
end

function M.render()
  local win = vim.g.statusline_winid or vim.api.nvim_get_current_win()
  local buf = vim.api.nvim_win_get_buf(win)
  local name = vim.api.nvim_buf_get_name(buf)
  if name == "" then
    return ""
  end

  -- path: dim directories, bright filename
  local rel = vim.fn.fnamemodify(name, ":~:.")
  local parts = vim.split(rel, "/", { plain = true })
  local file = table.remove(parts)
  if #parts > 3 then
    parts = { "…", parts[#parts - 1], parts[#parts] }
  end
  local out = { "%#LumenWinbar# " }
  for _, p in ipairs(parts) do
    out[#out + 1] = "%#LumenWinbar#" .. esc(p) .. SEP
  end
  local icon, icon_hl = Lumen.icon("file", name)
  if icon then
    out[#out + 1] = "%#" .. icon_hl .. "#" .. icon .. " "
  end
  local active = win == vim.api.nvim_get_current_win()
  out[#out + 1] = "%#" .. (active and "LumenWinbarFile" or "LumenWinbar") .. "#" .. esc(file)
  if vim.bo[buf].modified then
    out[#out + 1] = "%#LumenStlModified# ●"
  end

  -- symbols
  local entry = cache[buf]
  rendered[win] = {}
  if entry then
    local cursor = vim.api.nvim_win_get_cursor(win)
    local crumbs = path_at(entry.symbols, cursor[1] - 1, cursor[2])
    local budget = vim.api.nvim_win_get_width(win) - vim.fn.strdisplaywidth(rel) - 10
    -- drop outermost crumbs until it fits
    local first = 1
    local function width(from)
      local w = 0
      for i = from, #crumbs do
        w = w + vim.fn.strdisplaywidth(crumbs[i].name) + 5
      end
      return w
    end
    while first < #crumbs and width(first) > budget do
      first = first + 1
    end
    if first > 1 then
      out[#out + 1] = SEP .. "%#LumenWinbar#…"
    end
    for i = first, #crumbs do
      local s = crumbs[i]
      rendered[win][#rendered[win] + 1] = s
      local kind = KINDS[s.kind]
      local ki, kh = Lumen.icon("lsp", kind:lower())
      out[#out + 1] = SEP
        .. ("%%%d@v:lua.LumenWinbarClick@"):format(#rendered[win])
        .. (ki and ("%#" .. kh .. "#" .. ki .. " ") or "")
        .. "%#LumenWinbarSymbol#"
        .. esc(s.name:gsub("\n.*", ""))
        .. "%T"
    end
  end
  return table.concat(out)
end

---@diagnostic disable-next-line: unused-local
function _G.LumenWinbarClick(idx, clicks, button, mods)
  local win = vim.fn.getmousepos().winid
  local s = rendered[win] and rendered[win][idx]
  if s and button == "l" then
    vim.api.nvim_set_current_win(win)
    vim.cmd("normal! m'")
    vim.api.nvim_win_set_cursor(win, { s.range.start.line + 1, s.range.start.character })
  end
end

local EXPR = "%{%v:lua.require'lumen.ui.winbar'.render()%}"

local function eligible(win, buf)
  return vim.api.nvim_win_get_config(win).relative == ""
    and vim.bo[buf].buftype == ""
    and vim.bo[buf].filetype ~= ""
    and vim.api.nvim_buf_get_name(buf) ~= ""
    and not vim.wo[win].diff
end

local function attach(win)
  win = win or vim.api.nvim_get_current_win()
  if not vim.api.nvim_win_is_valid(win) then
    return
  end
  local buf = vim.api.nvim_win_get_buf(win)
  if eligible(win, buf) then
    if vim.wo[win].winbar ~= EXPR then
      vim.wo[win].winbar = EXPR
    end
  elseif vim.wo[win].winbar == EXPR then
    vim.wo[win].winbar = ""
  end
end

function M.setup()
  local group = vim.api.nvim_create_augroup("lumen_winbar", { clear = true })
  vim.api.nvim_create_autocmd({ "BufWinEnter", "WinEnter", "FileType", "OptionSet" }, {
    group = group,
    callback = function(ev)
      if ev.event == "OptionSet" and ev.match ~= "diff" then
        return
      end
      attach()
    end,
  })

  local timer = assert(vim.uv.new_timer())
  local function refresh(buf)
    timer:stop()
    timer:start(
      250,
      0,
      vim.schedule_wrap(function()
        M.request(buf)
      end)
    )
  end
  vim.api.nvim_create_autocmd("LspAttach", {
    group = group,
    callback = function(ev)
      M.request(ev.buf)
    end,
  })
  vim.api.nvim_create_autocmd({ "BufEnter", "TextChanged", "InsertLeave", "BufWritePost" }, {
    group = group,
    callback = function(ev)
      refresh(ev.buf)
    end,
  })
  vim.api.nvim_create_autocmd("CursorMoved", {
    group = group,
    callback = function()
      if vim.wo.winbar == EXPR then
        vim.cmd.redrawstatus()
      end
    end,
  })
  vim.api.nvim_create_autocmd({ "BufWipeout", "WinClosed" }, {
    group = group,
    callback = function(ev)
      if ev.event == "BufWipeout" then
        cache[ev.buf] = nil
      else
        rendered[tonumber(ev.match)] = nil
      end
    end,
  })
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    attach(win)
  end
end

return M
