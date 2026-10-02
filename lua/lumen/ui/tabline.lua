-- Lumen tabline: listed buffers with icons, a glowing bar on the active one,
-- mouse support, smart disambiguation of duplicate names, and tabpages on the right.

local icons = require("lumen.icons")

local M = {}

local function esc(s)
  return (s:gsub("%%", "%%%%"))
end

local function listed()
  return vim.tbl_filter(function(b)
    return vim.api.nvim_buf_is_valid(b) and vim.bo[b].buflisted
  end, vim.api.nvim_list_bufs())
end

-- icon highlight groups re-based on the tab's background
local icon_cache = {}
local function icon_hl(group, active)
  local key = group .. (active and "A" or "I")
  if icon_cache[key] then
    return icon_cache[key]
  end
  local name = "LumenTabIcon" .. key
  local fg = vim.api.nvim_get_hl(0, { name = group, link = false }).fg
  local bg = vim.api.nvim_get_hl(0, { name = active and "LumenTabActive" or "LumenTab", link = false }).bg
  vim.api.nvim_set_hl(0, name, { fg = active and fg or nil, bg = bg, link = not active and "LumenTab" or nil })
  icon_cache[key] = name
  return name
end

-- shortest unique trailing path for each buffer: duplicate basenames grow parent dirs
-- until they differ (a/src/init.lua, b/src/init.lua → a/src/init.lua, b/src/init.lua)
---@param bufs integer[]
local function names(bufs)
  local out, full = {}, {}
  for _, b in ipairs(bufs) do
    full[b] = vim.api.nvim_buf_get_name(b)
    out[b] = full[b] == "" and "[No Name]" or full[b]:match("[^/]*$")
  end
  local parts = {} -- split lazily: only duplicates pay for it
  for depth = 2, 32 do
    local count = {}
    for _, b in ipairs(bufs) do
      count[out[b]] = (count[out[b]] or 0) + 1
    end
    local grew = false
    for _, b in ipairs(bufs) do
      -- unnamed buffers stay "[No Name]"; paths that are fully shown can't grow
      if count[out[b]] > 1 and full[b] ~= "" then
        parts[b] = parts[b] or vim.split(full[b], "/", { trimempty = true })
        local p = parts[b]
        if #p >= depth then
          out[b] = table.concat(p, "/", #p - depth + 1)
          grew = true
        end
      end
    end
    if not grew then
      break
    end
  end
  return out
end

function M.render()
  local cur = vim.api.nvim_get_current_buf()
  local bufs = listed()
  local label = names(bufs)

  local items, cur_idx = {}, 1
  for i, b in ipairs(bufs) do
    local active = b == cur
    if active then
      cur_idx = i
    end
    local name = vim.api.nvim_buf_get_name(b)
    local icon, ihl = "󰈔", "LumenTab"
    local mi, mh = Lumen.icon("file", name ~= "" and name or "x.txt")
    icon, ihl = mi or icon, mh or ihl
    local base = active and "LumenTabActive" or "LumenTab"
    local tail
    if vim.bo[b].modified then
      tail = "%#" .. (active and "LumenTabActiveModified" or "LumenTabModified") .. "#" .. icons.misc.modified
    elseif active then
      tail = "%" .. b .. "@v:lua.LumenTablineClose@%#LumenTabClose#" .. icons.misc.close .. "%T"
    else
      tail = " "
    end
    local text = table.concat({
      "%" .. b .. "@v:lua.LumenTablineClick@",
      "%#" .. (active and "LumenTabActiveBar" or base) .. "#" .. (active and "▎" or " "),
      "%#" .. icon_hl(ihl, active) .. "# " .. icon .. " ",
      "%#" .. base .. "#" .. esc(label[b]) .. " ",
      "%T",
      tail,
      "%#" .. base .. "# ",
    })
    -- visible width: bar, space, icon, space, name, space, tail, space
    local width = 3 + vim.fn.strdisplaywidth(icon) + vim.fn.strdisplaywidth(label[b]) + 1 + 1 + 1
    items[i] = { text = text, width = width }
  end

  -- tabpages
  local tabs = ""
  local ntabs = vim.fn.tabpagenr("$")
  if ntabs > 1 then
    local curtab = vim.fn.tabpagenr()
    for t = 1, ntabs do
      tabs = tabs .. ("%%%dT%%#%s# %d %%T"):format(t, t == curtab and "LumenTabPageActive" or "LumenTabPage", t)
    end
  end
  local avail = vim.o.columns
  if ntabs > 1 then
    -- " n " per tabpage
    for t = 1, ntabs do
      avail = avail - #tostring(t) - 2
    end
  end

  -- keep the active buffer visible: grow a window around it
  local first, last, used = cur_idx, cur_idx, items[cur_idx] and items[cur_idx].width or 0
  local grew = true
  while grew do
    grew = false
    if items[last + 1] and used + items[last + 1].width <= avail then
      last, used, grew = last + 1, used + items[last + 1].width, true
    end
    if items[first - 1] and used + items[first - 1].width <= avail then
      first, used, grew = first - 1, used + items[first - 1].width, true
    end
  end

  local out = {}
  for i = first, last do
    if items[i] then
      out[#out + 1] = items[i].text
    end
  end
  return table.concat(out) .. "%#TabLineFill#%=" .. tabs
end

---@diagnostic disable-next-line: unused-local
function _G.LumenTablineClick(buf, clicks, button, mods)
  if button == "m" then
    Snacks.bufdelete(buf)
  elseif button == "l" then
    vim.api.nvim_set_current_buf(buf)
  end
end

---@diagnostic disable-next-line: unused-local
function _G.LumenTablineClose(buf, clicks, button, mods)
  if button == "l" then
    Snacks.bufdelete(buf)
  end
end

local function update()
  local n = 0
  for _, b in ipairs(listed()) do
    if vim.api.nvim_buf_get_name(b) ~= "" or vim.bo[b].modified then
      n = n + 1
    end
  end
  -- tabpages are listed on the right: keep them visible even without file buffers
  local want = (n >= 1 or vim.fn.tabpagenr("$") > 1) and 2 or 0
  if vim.o.showtabline ~= want then
    vim.o.showtabline = want
  end
end

function M.setup()
  vim.o.tabline = "%!v:lua.require'lumen.ui.tabline'.render()"
  local group = vim.api.nvim_create_augroup("lumen_tabline", { clear = true })
  vim.api.nvim_create_autocmd({ "BufAdd", "BufDelete", "BufEnter", "BufWipeout", "TabNew", "TabClosed" }, {
    group = group,
    callback = function()
      vim.schedule(update)
    end,
  })
  vim.api.nvim_create_autocmd("ColorScheme", {
    group = group,
    callback = function()
      icon_cache = {}
    end,
  })
  update()
end

return M
