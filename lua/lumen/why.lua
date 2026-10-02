-- :Lumen why — explain everything Lumen does (and doesn't do) for the current buffer:
-- language pack, treesitter, language servers, formatting, linting, project root.
-- Every problem comes with the command that fixes it.

local M = {}

local OK, NO, WARN, INFO = "✓", "✗", "!", "·"

---@param ft string
local function pack_for(ft)
  local packs = require("lumen.packs")
  local enabled = packs.enabled()
  for _, name in ipairs(packs.available()) do
    local p = packs.get(name)
    if p and vim.tbl_contains(p.ft or {}, ft) then
      return name, enabled[name] == true
    end
  end
end

--- Mason package for a conform formatter / nvim-lint linter name: names often differ
--- (`ruff_format` → ruff, `biome-check` → biome), and some tools aren't in Mason at all
---@param name string
---@return string?
function M.mason_pkg(name)
  local ok, registry = pcall(require, "mason-registry")
  if not ok then
    return
  end
  for _, pkg in ipairs({ name, name:match("^(.-)[_-]") }) do
    if registry.has_package(pkg) then
      return pkg
    end
  end
end

local function mason_fix(name)
  local pkg = M.mason_pkg(name)
  return pkg and (":MasonInstall " .. pkg) or nil
end

local function exe(cmd)
  if type(cmd) == "table" and type(cmd[1]) == "string" then
    return cmd[1], vim.fn.executable(cmd[1]) == 1
  end
end

---@param buf integer
function M.report(buf)
  buf = (buf == nil or buf == 0) and vim.api.nvim_get_current_buf() or buf
  local ft = vim.bo[buf].filetype
  local name = vim.api.nvim_buf_get_name(buf)
  local lines = {}
  local function add(s)
    lines[#lines + 1] = s or ""
  end
  local function item(mark, text, fix)
    add(("%s %s"):format(mark, text))
    if fix then
      add(("   → `%s`"):format(fix))
    end
  end

  add(("# Why — `%s`"):format(name ~= "" and vim.fn.fnamemodify(name, ":~:.") or "[No Name]"))
  add()
  add(
    ("filetype **%s** · buftype **%s**"):format(
      ft ~= "" and ft or "none",
      vim.bo[buf].buftype ~= "" and vim.bo[buf].buftype or "file"
    )
  )
  add()

  -- terminals, quickfix, scratch buffers…: no pack, parser or server can apply, so say that
  -- instead of reporting "no `` parser installed"
  if ft == "" then
    item(INFO, "this buffer has no filetype, so no language pack, parser, server, formatter or linter applies")
    if name ~= "" and vim.bo[buf].buftype == "" then
      item(INFO, "set one with `:setfiletype <name>` if detection missed it")
    end
    return lines
  end

  -- ── pack ──
  add("## Language pack")
  local pack, on = pack_for(ft)
  if not pack then
    item(INFO, "no Lumen pack targets `" .. ft .. "`", nil)
  elseif on then
    item(OK, ("`%s` enabled"):format(pack))
  else
    item(NO, ("`%s` exists but is disabled"):format(pack), ":Lumen packs enable " .. pack)
  end
  add()

  -- ── treesitter ──
  add("## Treesitter")
  local lang = vim.treesitter.language.get_lang(ft) or ft
  local has_parser = pcall(vim.treesitter.language.add, lang) and vim.treesitter.language.add(lang)
  local active = vim.treesitter.highlighter.active[buf] ~= nil
  if active then
    item(OK, ("highlighting with the `%s` parser"):format(lang))
  elseif has_parser then
    item(WARN, ("parser `%s` installed but highlighting is off"):format(lang), "<leader>uT")
  else
    local known = Lumen.is_loaded("nvim-treesitter") and require("nvim-treesitter.parsers")[lang]
    if known or not Lumen.is_loaded("nvim-treesitter") then
      item(NO, ("no `%s` parser installed"):format(lang), known and (":TSInstall " .. lang) or nil)
    else
      -- e.g. org (org.nvim highlights it itself): nothing to install, so nothing is wrong
      item(INFO, ("no treesitter parser exists for `%s` (regular syntax highlighting)"):format(lang))
    end
  end
  add()

  -- ── lsp ──
  add("## Language servers")
  local attached = {}
  for _, c in ipairs(vim.lsp.get_clients({ bufnr = buf })) do
    attached[c.name] = c
  end
  local seen = 0
  local servers = package.loaded["lumen.lsp"] and require("lumen.lsp").servers or {}
  local names = vim.tbl_keys(servers)
  table.sort(names)
  for _, sname in ipairs(names) do
    local cfg = vim.lsp.config[sname] or {}
    if cfg.filetypes and vim.tbl_contains(cfg.filetypes, ft) then
      seen = seen + 1
      local c = attached[sname]
      if c then
        item(
          OK,
          ("`%s` attached — root `%s`"):format(
            sname,
            c.root_dir and vim.fn.fnamemodify(c.root_dir, ":~") or "single file"
          )
        )
        attached[sname] = nil
      else
        local bin, found = exe(cfg.cmd)
        if bin and not found then
          local pkg = servers[sname].mason and require("lumen.lsp").package_for(sname)
          item(
            NO,
            ("`%s` not installed (`%s` not on $PATH)"):format(sname, bin),
            pkg and (":MasonInstall " .. pkg) or nil
          )
        else
          local markers = cfg.root_markers and table.concat(vim.iter(cfg.root_markers):flatten():totable(), ", ")
          item(
            WARN,
            ("`%s` installed but not attached%s"):format(
              sname,
              markers and (" — needs a project root with one of: " .. markers) or ""
            ),
            ":LspInfo"
          )
        end
      end
    end
  end
  for cname in pairs(attached) do
    item(OK, ("`%s` attached (not managed by Lumen)"):format(cname))
    seen = seen + 1
  end
  if seen == 0 then
    item(
      INFO,
      "no language server configured for `" .. ft .. "`",
      pack and not on and (":Lumen packs enable " .. pack) or nil
    )
  end
  add()

  -- ── formatting ──
  add("## Formatting")
  local fos = vim.b[buf].lumen_autoformat
  local scope = fos == nil and "global" or "buffer"
  if fos == nil then
    fos = vim.g.lumen_autoformat ~= false
  end
  item(
    fos and OK or INFO,
    ("format on save is **%s** (%s setting)"):format(fos and "on" or "off", scope),
    (not fos) and "<leader>uf" or nil
  )
  if Lumen.is_loaded("conform.nvim") or Lumen.has("conform.nvim") then
    local conform = require("conform")
    local configured = conform.list_formatters_for_buffer(buf)
    for _, f in ipairs(configured) do
      local fname = type(f) == "table" and f[1] or f
      if type(fname) == "string" then
        local info = conform.get_formatter_info(fname, buf)
        if info.available then
          item(OK, ("`%s` available"):format(fname))
        else
          item(NO, ("`%s` unavailable — %s"):format(fname, info.available_msg or "?"), mason_fix(fname))
        end
      end
    end
    local run, lsp = conform.list_formatters_to_run(buf)
    local run_names = vim.tbl_map(function(f)
      return f.name
    end, run)
    if #run_names > 0 then
      item(INFO, "will run: " .. table.concat(run_names, " → ") .. (lsp and " + LSP" or ""))
    elseif lsp then
      local fmt = vim.tbl_map(function(c)
        return c.name
      end, vim.lsp.get_clients({ bufnr = buf, method = "textDocument/formatting" }))
      item(INFO, "will format with LSP: " .. table.concat(fmt, ", "))
    else
      item(WARN, "nothing will format this file", pack and not on and (":Lumen packs enable " .. pack) or nil)
    end
  end
  add()

  -- ── linting ──
  add("## Linting")
  local lint_ok, lint = pcall(require, "lint")
  local linters = lint_ok and (lint.linters_by_ft[ft] or {}) or {}
  if #linters == 0 then
    item(INFO, "no extra linters (diagnostics come from language servers)")
  end
  for _, l in ipairs(linters) do
    local def = lint.linters[l]
    def = type(def) == "function" and def() or def
    local cmd = def and def.cmd
    cmd = type(cmd) == "function" and cmd() or cmd
    if cmd and vim.fn.executable(cmd) == 1 then
      item(OK, ("`%s` runs on save / read / insert-leave"):format(l))
    else
      item(NO, ("`%s` not installed"):format(l), mason_fix(l))
    end
  end
  local counts = vim.diagnostic.count(buf)
  local sev = vim.diagnostic.severity
  item(
    INFO,
    ("diagnostics now: %d errors · %d warnings · %d info · %d hints — display mode **%s** (<leader>uv)"):format(
      counts[sev.ERROR] or 0,
      counts[sev.WARN] or 0,
      counts[sev.INFO] or 0,
      counts[sev.HINT] or 0,
      require("lumen.diagnostics").mode
    )
  )
  add()

  -- ── root ──
  add("## Project root")
  local root, how = Lumen.root.info(buf)
  item(INFO, ("`%s` — from %s"):format(vim.fn.fnamemodify(root, ":~"), how))
  add()

  -- ── markdown ──
  if ft == "markdown" then
    add("## Markdown rendering")
    if package.loaded["render-markdown"] then
      local on_md = require("render-markdown").get()
      item(
        on_md and OK or WARN,
        "render-markdown " .. (on_md and "enabled" or "disabled"),
        not on_md and "<leader>um" or nil
      )
    else
      item(NO, "render-markdown not loaded", "enable the `markdown` pack")
    end
    add()
  end

  return lines
end

function M.show()
  local buf = vim.api.nvim_get_current_buf()
  local lines = M.report(buf)
  if not _G.Snacks then
    -- snacks.nvim disabled: a plain scratch split
    vim.cmd("botright new")
    vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
    vim.bo.buftype, vim.bo.bufhidden, vim.bo.modifiable = "nofile", "wipe", false
    vim.bo.filetype = "markdown"
    vim.keymap.set("n", "q", "<cmd>close<cr>", { buffer = true, silent = true })
    return
  end
  Snacks.win({
    text = lines,
    ft = "markdown",
    width = 0.6,
    height = math.min(#lines + 2, math.floor(vim.o.lines * 0.8)),
    border = "rounded",
    title = " 󰛨 Lumen why ",
    title_pos = "center",
    backdrop = false,
    wo = { wrap = true, linebreak = true, conceallevel = 2, spell = false, cursorline = false },
    -- a real markdown filetype so render-markdown draws the report (snacks' `ft` only highlights)
    bo = { filetype = "markdown", modifiable = false },
    keys = { q = "close", ["<esc>"] = "close" },
  })
end

return M
