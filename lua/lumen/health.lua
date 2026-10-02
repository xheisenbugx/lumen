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
  local enabled = require("lumen.packs").enabled()
  for _, name in ipairs(require("lumen.packs").available()) do
    if enabled[name] then
      h.ok(name)
    end
  end
  h.info("Manage packs with `:Lumen packs`")

  h.start("UI")
  if vim.o.cmdheight == 0 then
    h.ok("ui2 enabled (cmdheight=0)")
  else
    h.info("ui2 not active")
  end
  h.info("Icons need a Nerd Font: https://www.nerdfonts.com")
end

return M
