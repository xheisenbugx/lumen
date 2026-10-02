-- Lumen palettes. Ink-dark surfaces with a single warm "glow" (amber)
-- used sparingly for focus: cursor line number, active tab, titles, matches.

---@class lumen.Palette
---@field bg_dark string
---@field bg string
---@field bg_float string
---@field bg_hl string
---@field bg_sel string
---@field bg_visual string
---@field border string
---@field gutter string
---@field comment string
---@field fg_dim string
---@field fg string
---@field fg_bright string
---@field member string
---@field param string
---@field amber string
---@field orange string
---@field red string
---@field rose string
---@field violet string
---@field blue string
---@field sky string
---@field cyan string
---@field teal string
---@field green string
---@field yellow string
---@field accent string

local M = {}

M.night = {
  bg_dark = "#0a0c11",
  bg = "#10131a",
  bg_float = "#141821",
  bg_hl = "#181d28",
  bg_sel = "#222a3a",
  bg_visual = "#2a3348",
  border = "#2a3244",
  gutter = "#525f7c",
  comment = "#697592",
  fg_dim = "#8d97b0",
  fg = "#d5dbea",
  fg_bright = "#f2f4fb",

  amber = "#f5b85c",
  orange = "#f49b6c",
  red = "#f2727f",
  rose = "#eb8fc5",
  violet = "#b59df7",
  blue = "#7eaaf8",
  sky = "#93cdf5",
  cyan = "#6dd3e0",
  teal = "#5fd4b2",
  green = "#a7db8d",
  yellow = "#ecd38a",

  member = "#b4c6ee",
  param = "#f0cfa0",
}

M.dawn = {
  bg_dark = "#ebe5d9",
  bg = "#f7f3eb",
  bg_float = "#f0ebe1",
  bg_hl = "#eee8dc",
  bg_sel = "#e2d9c9",
  bg_visual = "#d8cdb9",
  border = "#d0c5b1",
  gutter = "#9c8e75",
  comment = "#837866",
  fg_dim = "#696356",
  fg = "#2d313d",
  fg_bright = "#171a22",

  amber = "#9c6010",
  orange = "#af5325",
  red = "#c33c4c",
  rose = "#b0407f",
  violet = "#7248c4",
  blue = "#2e66c9",
  sky = "#2874a1",
  cyan = "#15788b",
  teal = "#167c62",
  green = "#477a23",
  yellow = "#876a0b",

  member = "#40558a",
  param = "#8c5a14",
}

return M
