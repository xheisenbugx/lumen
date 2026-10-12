-- Colorscheme: variants, accent, overrides, compat, WCAG contrast (run by tests/smoke.lua)
---@param t lumen.test.Helpers
return function(t)
  local check, wait, child, fake_server, SLOW = t.check, t.wait, t.child, t.fake_server, t.SLOW

  check("colorscheme loads", function()
    assert(vim.g.colors_name == "lumen", "colors_name = " .. tostring(vim.g.colors_name))
    for _, g in ipairs({ "LumenStl", "LumenTabActive", "LumenWinbar", "LumenFoldCount", "MCursor", "SnacksPickerMatch" }) do
      assert(next(vim.api.nvim_get_hl(0, { name = g })), "missing highlight " .. g)
    end
  end)

  check("dawn variant + background toggle", function()
    vim.o.background = "light"
    assert(
      wait(1000 * SLOW, function()
        return vim.api.nvim_get_hl(0, { name = "Normal" }).bg == tonumber("f7f3eb", 16)
      end),
      "dawn not applied"
    )
    vim.o.background = "dark"
    assert(
      wait(1000 * SLOW, function()
        return vim.api.nvim_get_hl(0, { name = "Normal" }).bg == tonumber("10131a", 16)
      end),
      "night not restored"
    )
  end)

  check("accent + on_highlights", function()
    local config = require("lumen.config")
    config.accent = "violet"
    config.on_highlights = function(hl, p)
      hl.LumenTest = { fg = p.teal }
    end
    vim.cmd.colorscheme("lumen")
    local p = require("lumen.colors.palettes").night
    assert(vim.api.nvim_get_hl(0, { name = "CursorLineNr" }).fg == tonumber(p.violet:sub(2), 16), "accent not applied")
    assert(
      vim.api.nvim_get_hl(0, { name = "LumenTest" }).fg == tonumber(p.teal:sub(2), 16),
      "on_highlights not applied"
    )
    config.accent, config.on_highlights = "amber", nil
    vim.cmd.colorscheme("lumen")
  end)

  check("a bad on_highlights group doesn't break the theme or the background toggle", function()
    local config = require("lumen.config")
    config.on_highlights = function(hl)
      hl.LumenBad = { fg = "not-a-color" }
    end
    local ok, err = pcall(vim.cmd.colorscheme, "lumen")
    config.on_highlights = nil
    assert(ok, "colorscheme failed: " .. tostring(err))
    assert(vim.g.colors_name == "lumen", "colors_name = " .. tostring(vim.g.colors_name))
    vim.o.background = "light"
    assert(
      wait(1000 * SLOW, function()
        return vim.api.nvim_get_hl(0, { name = "Normal" }).bg == tonumber("f7f3eb", 16)
      end),
      "background toggle stuck after a failed load"
    )
    vim.o.background = "dark"
    vim.cmd.colorscheme("lumen")
  end)

  check("invalid palette overrides / accent are ignored with a warning", function()
    local config = require("lumen.config")
    -- collect every notification: on a fresh machine Mason's install progress can land in between
    local notify, seen = vim.notify, {}
    local function warning()
      for _, m in ipairs(seen) do
        if m:find("colors.night.bg", 1, true) then
          return m
        end
      end
    end
    vim.notify = function(msg)
      seen[#seen + 1] = tostring(msg)
    end
    config.colors, config.accent = { night = { bg = "black", red = "#ff0000" } }, "pinkish"
    local ok, err = pcall(vim.cmd.colorscheme, "lumen")
    wait(1000 * SLOW, function()
      return warning() ~= nil
    end)
    local warned = warning()
    vim.notify, config.colors, config.accent = notify, {}, "amber"
    local normal, error_fg = vim.api.nvim_get_hl(0, { name = "Normal" }).bg, vim.api.nvim_get_hl(0, { name = "Error" })
    vim.cmd.colorscheme("lumen")
    assert(ok, "colorscheme failed: " .. tostring(err))
    assert(normal == tonumber("10131a", 16), "invalid bg not ignored")
    assert(next(error_fg), "valid override broke a group")
    assert(warned and warned:find("pinkish", 1, true), "no warning among: " .. vim.inspect(seen))
  end)

  check("background toggle under lumen-dawn / lumen-night switches variant", function()
    -- Neovim unloads a scheme that sets 'background' back (colors_name = nil, default colors)
    for _, case in ipairs({ { "lumen-dawn", "dark", "10131a" }, { "lumen-night", "light", "f7f3eb" } }) do
      vim.cmd.colorscheme(case[1])
      vim.o.background = case[2]
      assert(
        wait(1000 * SLOW, function()
          return vim.g.colors_name == "lumen"
            and vim.api.nvim_get_hl(0, { name = "Normal" }).bg == tonumber(case[3], 16)
        end),
        ("%s + background=%s: colors_name=%s"):format(case[1], case[2], tostring(vim.g.colors_name))
      )
    end
    vim.o.background = "dark"
    vim.cmd.colorscheme("lumen")
  end)

  check("catppuccin is selectable and Lumen UI adapts", function()
    local names = vim.tbl_map(function(i)
      return i.text
    end, require("snacks.picker.source.vim").colorschemes())
    for _, want in ipairs({ "catppuccin", "catppuccin-mocha", "catppuccin-latte", "lumen", "lumen-dawn" }) do
      assert(vim.tbl_contains(names, want), want .. " missing from colorscheme picker")
    end
    vim.cmd.colorscheme("catppuccin-mocha")
    local mocha = require("catppuccin.palettes").get_palette("mocha")
    local stl = vim.api.nvim_get_hl(0, { name = "LumenStl", link = false })
    assert(stl.bg == tonumber(mocha.mantle:sub(2), 16), "statusline not adapted to catppuccin")
    local mode = vim.api.nvim_get_hl(0, { name = "LumenStlModeNormal", link = false })
    assert(mode.bg == tonumber(mocha.mauve:sub(2), 16), "accent should be catppuccin mauve")
    -- any other scheme gets derived colors
    vim.cmd.colorscheme("habamax")
    assert(next(vim.api.nvim_get_hl(0, { name = "LumenTabActive" })), "tabline groups missing under habamax")
    vim.cmd.colorscheme("lumen")
    assert(vim.api.nvim_get_hl(0, { name = "Normal" }).bg == tonumber("10131a", 16), "lumen not restored")
  end)

  check("theme contrast (WCAG) in both variants", function()
    local function lum(h)
      local function ch(i)
        local c = tonumber(h:sub(i, i + 1), 16) / 255
        return c <= 0.03928 and c / 12.92 or ((c + 0.055) / 1.055) ^ 2.4
      end
      return 0.2126 * ch(2) + 0.7152 * ch(4) + 0.0722 * ch(6)
    end
    local function ratio(a, b)
      local x, y = lum(a), lum(b)
      return (math.max(x, y) + 0.05) / (math.min(x, y) + 0.05)
    end
    local bad = {}
    for variant, p in pairs(require("lumen.colors.palettes")) do
      for _, k in ipairs({
        "fg",
        "fg_dim",
        "member",
        "param",
        "amber",
        "orange",
        "red",
        "rose",
        "violet",
        "blue",
        "sky",
        "cyan",
        "teal",
        "green",
        "yellow",
      }) do
        if ratio(p[k], p.bg) < 4.5 then
          bad[#bad + 1] = ("%s.%s %.2f"):format(variant, k, ratio(p[k], p.bg))
        end
      end
      for k, min in pairs({ comment = 3.5, gutter = 2.5 }) do
        if ratio(p[k], p.bg) < min then
          bad[#bad + 1] = ("%s.%s %.2f"):format(variant, k, ratio(p[k], p.bg))
        end
      end
    end
    assert(#bad == 0, "below contrast floor: " .. table.concat(bad, ", "))
  end)
end
