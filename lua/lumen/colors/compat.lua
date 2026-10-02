-- Keep Lumen's own UI (statusline, tabline, winbar, folds, dashboard logo) looking native
-- under ANY colorscheme: build a Lumen palette from the active scheme, then apply only
-- Lumen's groups. Catppuccin gets an exact mapping; everything else is derived from
-- standard highlight groups.

local M = {}

local function hex(n)
  return n and ("#%06x"):format(n) or nil
end

---@param names string[]
---@param attr "fg"|"bg"
local function get(names, attr)
  for _, name in ipairs(names) do
    local c = hex(vim.api.nvim_get_hl(0, { name = name, link = false })[attr])
    if c then
      return c
    end
  end
end

local function catppuccin()
  local ok, palettes = pcall(require, "catppuccin.palettes")
  if not ok then
    return
  end
  local c = palettes.get_palette()
  return {
    bg_dark = c.mantle,
    bg = c.base,
    bg_float = c.mantle,
    bg_hl = c.surface0,
    bg_sel = c.surface0,
    bg_visual = c.surface1,
    border = c.surface1,
    gutter = c.surface2,
    comment = c.overlay1,
    fg_dim = c.subtext0,
    fg = c.text,
    fg_bright = c.text,
    amber = c.peach,
    orange = c.peach,
    red = c.red,
    rose = c.pink,
    violet = c.mauve,
    blue = c.blue,
    sky = c.sky,
    cyan = c.sapphire,
    teal = c.teal,
    green = c.green,
    yellow = c.yellow,
    member = c.lavender,
    param = c.maroon,
    native_accent = c.mauve,
  }
end

local function derived()
  local blend = require("lumen.colors").blend
  local light = vim.o.background == "light"
  local bg = get({ "Normal" }, "bg") or (light and "#ffffff" or "#000000")
  local fg = get({ "Normal" }, "fg") or (light and "#000000" or "#ffffff")
  local stl = get({ "StatusLine" }, "bg")
  return {
    bg_dark = (stl and stl ~= bg) and stl or blend("#000000", bg, light and 0.06 or 0.25),
    bg = bg,
    bg_float = get({ "NormalFloat", "Pmenu" }, "bg") or bg,
    bg_hl = get({ "CursorLine" }, "bg") or blend(fg, bg, 0.06),
    bg_sel = get({ "PmenuSel", "Visual" }, "bg") or blend(fg, bg, 0.12),
    bg_visual = get({ "Visual" }, "bg") or blend(fg, bg, 0.18),
    border = get({ "FloatBorder", "WinSeparator" }, "fg") or blend(fg, bg, 0.25),
    gutter = get({ "LineNr" }, "fg") or blend(fg, bg, 0.35),
    comment = get({ "Comment" }, "fg") or blend(fg, bg, 0.5),
    fg_dim = blend(fg, bg, 0.72),
    fg = fg,
    fg_bright = fg,
    amber = get({ "Constant", "Number" }, "fg") or fg,
    orange = get({ "Number", "Constant" }, "fg") or fg,
    red = get({ "DiagnosticError", "ErrorMsg" }, "fg") or fg,
    rose = get({ "PreProc", "Include", "Special" }, "fg") or fg,
    violet = get({ "Statement", "Keyword" }, "fg") or fg,
    blue = get({ "Function" }, "fg") or fg,
    sky = get({ "Directory", "Function" }, "fg") or fg,
    cyan = get({ "Operator", "Special" }, "fg") or fg,
    teal = get({ "DiagnosticHint", "Type" }, "fg") or fg,
    green = get({ "String", "DiagnosticOk" }, "fg") or fg,
    yellow = get({ "DiagnosticWarn", "WarningMsg" }, "fg") or fg,
    member = get({ "@property", "Identifier" }, "fg") or fg,
    param = get({ "@variable.parameter", "Identifier" }, "fg") or fg,
    native_accent = get({ "CursorLineNr", "Title", "Function" }, "fg"),
  }
end

function M.apply()
  local name = vim.g.colors_name or ""
  if name:find("^lumen") then
    return
  end
  local p = (name:find("^catppuccin") and catppuccin()) or derived()

  -- explicit `accent` wins; otherwise use the scheme's own signature color
  local config = require("lumen.config")
  local accent = config.accent
  if accent and accent ~= require("lumen.config").defaults.accent then
    p.accent = p[accent] or (accent:match("^#%x%x%x%x%x%x$") and accent) or p.native_accent
  else
    p.accent = p.native_accent or p.amber
  end

  local groups = require("lumen.colors.theme").groups(p, {
    transparent = config.transparent,
    italics = config.italics ~= false,
    blend = require("lumen.colors").blend,
    light = vim.o.background == "light",
  })
  for group, spec in pairs(groups) do
    if group:find("^Lumen") or group == "MCursor" then
      vim.api.nvim_set_hl(0, group, spec)
    end
  end
end

function M.setup()
  vim.api.nvim_create_autocmd("ColorScheme", {
    group = vim.api.nvim_create_augroup("lumen_colors_compat", { clear = true }),
    callback = function()
      M.apply()
    end,
  })
end

return M
