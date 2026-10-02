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

---@param buf? integer
---@param opts? {deep?: boolean} deep = :Lumen doctor (binaries, Mason, root trace, capabilities, log tail)
function M.report(buf, opts)
  buf = (buf == nil or buf == 0) and vim.api.nvim_get_current_buf() or buf
  local deep = opts and opts.deep
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

  add(
    ("# %s — `%s`"):format(deep and "Doctor" or "Why", name ~= "" and vim.fn.fnamemodify(name, ":~:.") or "[No Name]")
  )
  add()
  if deep then
    add("## Environment")
    for _, line in ipairs(M.environment()) do
      item(INFO, line)
    end
    add()
  end
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
    item(INFO, ft == "" and "no filetype, so no pack" or ("no Lumen pack targets `" .. ft .. "`"))
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
  if ft == "" then
    item(INFO, "no filetype, so no parser")
  elseif active then
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
        local pkg = servers[sname].mason and require("lumen.lsp").package_for(sname)
        -- many lspconfig servers have a function `cmd`: then ask Mason whether the package is there
        local reg_ok, registry = pcall(require, "mason-registry")
        local pkg_missing = not bin and pkg and reg_ok and registry.has_package(pkg) and not registry.is_installed(pkg)
        if (bin and not found) or pkg_missing then
          item(
            NO,
            bin and ("`%s` not installed (`%s` not on $PATH)"):format(sname, bin)
              or ("`%s` not installed (Mason package `%s` missing)"):format(sname, pkg),
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
      if deep then
        for _, line in ipairs(M.server_details(sname, cfg, c, buf)) do
          add("   · " .. line)
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
      ft == "" and "no language server (no filetype)" or ("no language server configured for `" .. ft .. "`"),
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

--- Neovim, Lumen, plugin manager and pack facts (doctor header and bug reports)
---@return string[]
function M.environment()
  local v = vim.version()
  local stats = package.loaded["lazy"] and require("lazy").stats() or { count = 0, loaded = 0 }
  local packs = vim.tbl_keys(require("lumen.packs").enabled())
  table.sort(packs)
  return {
    ("Neovim %d.%d.%d%s · Lumen %s · %s"):format(
      v.major,
      v.minor,
      v.patch,
      v.prerelease and ("-" .. tostring(v.prerelease)) or "",
      require("lumen").version,
      vim.uv.os_uname().sysname
    ),
    ("%d plugins (%d loaded) · update channel `%s`"):format(
      stats.count,
      stats.loaded,
      require("lumen.config").update_channel or "stable"
    ),
    "packs: " .. (#packs > 0 and table.concat(packs, ", ") or "none"),
  }
end

local CAPS = {
  hover = "textDocument/hover",
  definition = "textDocument/definition",
  references = "textDocument/references",
  rename = "textDocument/rename",
  ["code actions"] = "textDocument/codeAction",
  formatting = "textDocument/formatting",
  ["inlay hints"] = "textDocument/inlayHint",
  symbols = "textDocument/documentSymbol",
  folding = "textDocument/foldingRange",
  ["semantic tokens"] = "textDocument/semanticTokens/full",
  ["inline completion"] = "textDocument/inlineCompletion",
}

--- last log lines that mention this server (errors and warnings only)
---@param sname string
---@param max integer
function M.log_tail(sname, max)
  local ok, path = pcall(vim.lsp.log.get_filename)
  if not ok or not path or vim.fn.filereadable(path) == 0 then
    return {}
  end
  local size = vim.fn.getfsize(path)
  local f = io.open(path, "r")
  if not f then
    return {}
  end
  -- the log can be large: only read its last 256 KB
  if size > 262144 then
    f:seek("set", size - 262144)
  end
  local text = f:read("*a") or ""
  f:close()
  local hits = {}
  for line in text:gmatch("[^\n]+") do
    if line:find('"' .. sname .. '"', 1, true) and (line:find("^%[ERROR%]") or line:find("^%[WARN%]")) then
      hits[#hits + 1] = line
    end
  end
  return vim.list_slice(hits, math.max(1, #hits - max + 1), #hits)
end

--- deep facts about one server: binary, Mason, root trace, capabilities, log
---@param sname string
---@param cfg table resolved vim.lsp.config
---@param client? vim.lsp.Client attached client, if any
---@param buf integer
---@return string[]
function M.server_details(sname, cfg, client, buf)
  local out = {}
  if type(cfg.cmd) == "table" and type(cfg.cmd[1]) == "string" then
    local path = vim.fn.exepath(cfg.cmd[1])
    out[#out + 1] = ("command `%s` → %s"):format(
      table.concat(cfg.cmd, " "):sub(1, 80),
      path ~= "" and ("`" .. vim.fn.fnamemodify(path, ":~") .. "`") or "not found on $PATH"
    )
  else
    out[#out + 1] = "command resolved at start by lspconfig (function `cmd`)"
  end
  local servers = package.loaded["lumen.lsp"] and require("lumen.lsp").servers or {}
  local pkg = (servers[sname] or {}).mason and require("lumen.lsp").package_for(sname)
  if pkg then
    local reg_ok, registry = pcall(require, "mason-registry")
    local state = reg_ok
        and registry.has_package(pkg)
        and (registry.is_installed(pkg) and "installed" or "not installed")
      or "unknown"
    out[#out + 1] = ("Mason package `%s`: %s"):format(pkg, state)
  else
    out[#out + 1] = "not managed by Mason (bring your own binary)"
  end
  local markers = cfg.root_markers and vim.iter(cfg.root_markers):flatten():totable()
  if client then
    out[#out + 1] = ("root `%s`"):format(
      client.root_dir and vim.fn.fnamemodify(client.root_dir, ":~") or "none (single file)"
    )
    local caps = {}
    for label, method in pairs(CAPS) do
      if client:supports_method(method, buf) then
        caps[#caps + 1] = label
      end
    end
    table.sort(caps)
    out[#out + 1] = "supports: " .. (#caps > 0 and table.concat(caps, ", ") or "nothing Lumen maps")
  elseif markers then
    local found = vim.fs.root(buf, markers)
    out[#out + 1] = ("root markers %s → %s"):format(
      table.concat(markers, ", "),
      found and ("found `" .. vim.fn.fnamemodify(found, ":~") .. "`") or "none found above this file"
    )
  end
  for _, line in ipairs(M.log_tail(sname, 3)) do
    out[#out + 1] = "log: " .. line:gsub("%s+", " "):sub(1, 180)
  end
  return out
end

--- the doctor report as data, for bug reports and AI assistants
---@param buf? integer
function M.json(buf)
  buf = (buf == nil or buf == 0) and vim.api.nvim_get_current_buf() or buf
  local servers = {}
  for _, c in ipairs(vim.lsp.get_clients({ bufnr = buf })) do
    servers[#servers + 1] = { name = c.name, root = c.root_dir, attached = true }
  end
  return vim.json.encode({
    environment = M.environment(),
    file = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(buf), ":~:."),
    filetype = vim.bo[buf].filetype,
    attached = servers,
    report = M.report(buf, { deep = true }),
  })
end

--- the command a report line points to: the `→` fix on this line or the next one
---@param lines string[]
---@param lnum integer 1-based
---@return string?
function M.fix_at(lines, lnum)
  for i = lnum, math.min(lnum + 1, #lines) do
    local cmd = (lines[i] or ""):match("^%s*→ `(.-)`%s*$")
    if cmd then
      return cmd
    end
    -- the line after a status line is its fix; stop at the next status line
    if i > lnum and not lines[i]:match("^%s*→") then
      break
    end
  end
end

---@param cmd string `:Ex command` or keys like `<leader>uT`
local function run_fix(cmd, origin)
  if origin and vim.api.nvim_win_is_valid(origin) then
    vim.api.nvim_set_current_win(origin)
  end
  if cmd:sub(1, 1) == ":" then
    local ok, err = pcall(vim.cmd, cmd:sub(2))
    if not ok then
      Lumen.error(("`%s` failed: %s"):format(cmd, err))
    else
      Lumen.notify(("ran `%s`"):format(cmd))
    end
  elseif cmd:find("^<") then
    local keys = cmd:gsub("<leader>", vim.g.mapleader or "\\")
    vim.api.nvim_feedkeys(vim.keycode(keys), "m", false)
  else
    Lumen.notify(cmd)
  end
end

---@param opts? {deep?: boolean}
function M.show(opts)
  local deep = opts and opts.deep
  local origin = vim.api.nvim_get_current_win()
  local buf = vim.api.nvim_get_current_buf()
  local lines = M.report(buf, opts)
  table.insert(lines, 2, "_`<CR>` on a line with a → fix runs it · `q` closes_")
  local function on_enter()
    local cmd = M.fix_at(lines, vim.api.nvim_win_get_cursor(0)[1])
    if not cmd then
      return Lumen.notify("no fix on this line")
    end
    vim.cmd.close()
    run_fix(cmd, origin)
  end
  if not _G.Snacks then
    -- snacks.nvim disabled: a plain scratch split
    vim.cmd("botright new")
    vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
    vim.bo.buftype, vim.bo.bufhidden, vim.bo.modifiable = "nofile", "wipe", false
    vim.bo.filetype = "markdown"
    vim.keymap.set("n", "q", "<cmd>close<cr>", { buffer = true, silent = true })
    vim.keymap.set("n", "<cr>", on_enter, { buffer = true, silent = true })
    return
  end
  Snacks.win({
    text = lines,
    ft = "markdown",
    width = deep and 0.75 or 0.6,
    height = math.min(#lines + 2, math.floor(vim.o.lines * 0.8)),
    border = "rounded",
    title = deep and " 󰛨 Lumen doctor " or " 󰛨 Lumen why ",
    title_pos = "center",
    backdrop = false,
    wo = { wrap = true, linebreak = true, conceallevel = 2, spell = false, cursorline = true },
    -- a real markdown filetype so render-markdown draws the report (snacks' `ft` only highlights)
    bo = { filetype = "markdown", modifiable = false },
    keys = { q = "close", ["<esc>"] = "close", ["<cr>"] = on_enter },
  })
end

return M
