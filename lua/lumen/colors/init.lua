local M = {}

local loading = false

---@param hex string
local function rgb(hex)
  return tonumber(hex:sub(2, 3), 16), tonumber(hex:sub(4, 5), 16), tonumber(hex:sub(6, 7), 16)
end

--- mix `fg` over `bg` with opacity `a`
---@param fg string
---@param bg string
---@param a number 0..1
function M.blend(fg, bg, a)
  local r1, g1, b1 = rgb(fg)
  local r2, g2, b2 = rgb(bg)
  local function c(x, y)
    return math.floor(x * a + y * (1 - a) + 0.5)
  end
  return ("#%02x%02x%02x"):format(c(r1, r2), c(g1, g2), c(b1, b2))
end

---@param variant? "night"|"dawn"
---@return lumen.Palette, "night"|"dawn"
function M.palette(variant)
  variant = variant or (vim.o.background == "light" and "dawn" or "night")
  local config = require("lumen.config")
  local p = vim.deepcopy(require("lumen.colors.palettes")[variant])
  -- user palette overrides: colors = { night = { bg = "#000000" }, dawn = { ... } }
  p = vim.tbl_extend("force", p, (config.colors or {})[variant] or {})
  -- the "glow" used for focus across the UI; any palette key or a hex color
  local accent = type(config.accent) == "string" and config.accent or "amber"
  p.accent = p[accent] or (accent:match("^#%x%x%x%x%x%x$") and accent) or p.amber
  return p, variant
end

---@param variant? "night"|"dawn"
local function load(variant)
  local p, v = M.palette(variant)
  local config = require("lumen.config")

  if vim.g.colors_name then
    vim.cmd("hi clear")
  end
  vim.o.background = v == "dawn" and "light" or "dark"
  vim.o.termguicolors = true

  local groups = require("lumen.colors.theme").groups(p, {
    transparent = config.transparent,
    italics = config.italics ~= false,
    blend = M.blend,
    light = v == "dawn",
  })
  local errors = {}
  if type(config.on_highlights) == "function" then
    local ok, err = pcall(config.on_highlights, groups, p)
    if not ok then
      errors[#errors + 1] = "on_highlights failed\n" .. err
    end
  end
  -- one bad group (e.g. an invalid color from on_highlights) must not abort the whole theme
  for name, spec in pairs(groups) do
    local ok, err = pcall(vim.api.nvim_set_hl, 0, name, spec)
    if not ok then
      errors[#errors + 1] = ("highlight `%s`: %s"):format(name, err)
    end
  end
  if #errors > 0 then
    vim.schedule(function()
      vim.notify("Lumen: " .. table.concat(errors, "\n"), vim.log.levels.ERROR)
    end)
  end

  local term = {
    p.bg_sel,
    p.red,
    p.green,
    p.yellow,
    p.blue,
    p.violet,
    p.cyan,
    p.fg_dim,
    p.gutter,
    p.red,
    p.green,
    p.amber,
    p.sky,
    p.rose,
    p.teal,
    p.fg_bright,
  }
  for i, c in ipairs(term) do
    vim.g["terminal_color_" .. (i - 1)] = c
  end

  vim.g.colors_name = variant and ("lumen-" .. variant) or "lumen"
end

---@param variant? "night"|"dawn" nil follows 'background'
function M.load(variant)
  loading = true
  -- always reset the guard: a stuck `loading` would silently disable the background toggle
  local ok, err = pcall(load, variant)
  loading = false
  if not ok then
    error(err, 0)
  end
end

-- whether a Lumen variant is the active colorscheme
local active = false

local group = vim.api.nvim_create_augroup("lumen_colors", { clear = true })
vim.api.nvim_create_autocmd("ColorScheme", {
  group = group,
  callback = function()
    active = (vim.g.colors_name or ""):find("^lumen") ~= nil
  end,
})

-- `lumen` follows 'background': toggling it swaps night/dawn live.
-- Under `lumen-night`/`lumen-dawn` Neovim reloads the scheme on a 'background' change, sees it
-- set 'background' back, and unloads it (colors_name = nil, default colors): switch to `lumen`.
vim.api.nvim_create_autocmd("OptionSet", {
  group = group,
  pattern = "background",
  callback = function()
    if not loading and (active or (vim.g.colors_name or ""):find("^lumen")) then
      vim.schedule(function()
        vim.cmd.colorscheme("lumen")
      end)
    end
  end,
})

return M
