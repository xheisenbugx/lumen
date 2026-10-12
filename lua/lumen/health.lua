local M = {}

function M.check()
  local h = vim.health
  h.start("Lumen " .. require("lumen").version)

  if vim.fn.has("nvim-0.12") == 1 then
    h.ok("Neovim " .. tostring(vim.version()))
  elseif vim.fn.has("nvim-0.11") == 1 then
    h.warn("Neovim " .. tostring(vim.version()) .. " works, but 0.12+ unlocks ui2, :restart and more")
  else
    h.error("Neovim >= 0.11 is required")
  end

  h.start("Tools")
  local tools = {
    { "git", true, "plugin management" },
    { "rg", true, "grep / live grep" },
    { "fd", false, "fast file finding (falls back to rg)" },
    { "tree-sitter", true, "building treesitter parsers" },
    { { "cc", "gcc", "clang" }, true, "compiling treesitter parsers (a C compiler)" },
    { "lazygit", false, "<leader>gg" },
    { "node", false, "many LSP servers installed by Mason" },
  }
  for _, t in ipairs(tools) do
    local names, required, why = type(t[1]) == "table" and t[1] or { t[1] }, t[2], t[3]
    local found = vim.iter(names):find(function(n)
      return vim.fn.executable(n) == 1
    end)
    local name = found or table.concat(names, "` / `")
    if found then
      h.ok(("`%s` found"):format(name))
    elseif required then
      h.error(("`%s` not found — needed for %s"):format(name, why))
    else
      h.warn(("`%s` not found — optional, used for %s"):format(name, why))
    end
  end

  h.start("Language packs")
  local packs = require("lumen.packs")
  local enabled, via = packs.enabled()
  for _, name in ipairs(packs.available()) do
    if enabled[name] then
      local missing = packs.missing(packs.get(name) or {})
      local label = name .. (via[name] and (" (needed by " .. via[name] .. ")") or "")
      if #missing == 0 then
        h.ok(label)
      else
        h.warn(
          ("%s: `%s` not found on PATH — its language server or tools can't run"):format(
            label,
            table.concat(missing, "`, `")
          )
        )
      end
    end
  end
  h.info("Manage packs with `:Lumen packs`")

  local project = require("lumen.project")
  if project.path then
    local where = vim.fn.fnamemodify(project.path, ":~")
    if project.trusted then
      h.ok(("project settings from `%s`"):format(where))
    else
      h.warn(
        ("`%s` is not trusted, so it isn't used"):format(where),
        { "Review it with `:Lumen project`, then `:Lumen trust`" }
      )
    end
  end

  h.start("Updates")
  -- :Lumen update writes lazy-lock.json itself and has to refresh lazy.nvim's in-memory copy, which
  -- lives in private fields. If a lazy.nvim release renames them, pins and rollbacks would silently
  -- use stale commits: say so here instead.
  local ok, Lock = pcall(require, "lazy.manage.lock")
  if
    ok
    and type(Lock) == "table"
    and type(Lock.load) == "function"
    and type(Lock.lock) == "table"
    and type(Lock._loaded) == "boolean"
  then
    h.ok("lazy.nvim lockfile internals are where :Lumen update expects them")
  else
    h.error(
      "lazy.nvim's lockfile internals changed: `:Lumen update` pins and `:Lumen rollback` may not apply",
      { "Update Lumen, or use `:Lazy restore` with a known-good lazy-lock.json until it's fixed" }
    )
  end

  h.start("UI")
  if vim.o.cmdheight == 0 then
    h.ok("ui2 enabled (cmdheight=0)")
  else
    h.info("ui2 not active")
  end
  h.info("Icons need a Nerd Font: https://www.nerdfonts.com")
end

return M
