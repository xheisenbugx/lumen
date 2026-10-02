-- Language packs: one small declarative file per language.
--
--   return {
--     ft = { "python" },                         -- filetypes (used for suggestions)
--     parsers = { "python" },                    -- treesitter parsers
--     servers = { basedpyright = {}, ruff = {} },-- LSP servers (vim.lsp.config tables)
--     tools = { "debugpy" },                     -- extra Mason packages
--     formatters = { python = { "ruff_format" } },
--     linters = { python = { "mypy" } },
--     plugins = { ... },                         -- extra lazy.nvim specs
--     setup = function() end,                    -- startup hook (filetype rules, …)
--   }
--
-- A pack becomes plain lazy.nvim spec fragments that extend the core plugins,
-- so packs compose, and users can still override anything in their lua/plugins/.

local M = {}

local state_file = vim.fn.stdpath("state") .. "/lumen/packs.json"

---@class lumen.Pack
---@field ft? string[]
---@field desc? string
---@field parsers? string[]
---@field servers? table<string, table|false>
---@field tools? string[]
---@field formatters? table<string, any>
---@field formatter_opts? table<string, any>
---@field linters? table<string, string[]>
---@field plugins? LazySpec[]
---@field setup? fun() runs at startup when the pack is enabled (e.g. filetype detection)

---@return {enabled:string[], disabled:string[], dismissed:string[]}
function M.state()
  local f = io.open(state_file, "r")
  local data = {}
  if f then
    local ok, decoded = pcall(vim.json.decode, f:read("*a"))
    f:close()
    data = ok and type(decoded) == "table" and decoded or {}
  end
  data.enabled = data.enabled or {}
  data.disabled = data.disabled or {}
  data.dismissed = data.dismissed or {}
  return data
end

function M.save(state)
  vim.fn.mkdir(vim.fn.fnamemodify(state_file, ":h"), "p")
  local f = assert(io.open(state_file, "w"))
  f:write(vim.json.encode(state))
  f:close()
end

---@return string[]
function M.available()
  local names = {}
  -- Lumen's own packs (found next to this file: while lazy.nvim reads specs, Lumen is not on
  -- the runtimepath yet), plus custom packs in your config: lua/lumen/packs/<name>.lua
  local here = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h") .. "/packs"
  local files = vim.fn.glob(here .. "/*.lua", false, true)
  vim.list_extend(files, vim.fn.glob(vim.fn.stdpath("config") .. "/lua/lumen/packs/*.lua", false, true))
  for _, file in ipairs(files) do
    names[#names + 1] = vim.fn.fnamemodify(file, ":t:r")
  end
  table.sort(names)
  return vim.fn.uniq(names) --[[@as string[] ]]
end

---@return table<string, boolean>
function M.enabled()
  local state = M.state()
  local set = {}
  for _, name in ipairs(require("lumen.config").packs or {}) do
    set[name] = true
  end
  for _, name in ipairs(state.enabled) do
    set[name] = true
  end
  for _, name in ipairs(state.disabled) do
    set[name] = nil
  end
  return set
end

---@param name string
---@return lumen.Pack?
function M.get(name)
  local ok, pack = pcall(require, "lumen.packs." .. name)
  if not ok then
    vim.schedule(function()
      Lumen.error(("pack `%s` failed to load:\n%s"):format(name, pack))
    end)
    return
  end
  return pack
end

---@return LazySpec[]
function M.specs()
  local specs = {}
  local names = vim.tbl_keys(M.enabled())
  table.sort(names)
  for _, name in ipairs(names) do
    local p = M.get(name)
    if p then
      if p.setup then
        local ok, err = pcall(p.setup)
        if not ok then
          vim.schedule(function()
            Lumen.error(("pack `%s` setup failed:\n%s"):format(name, err))
          end)
        end
      end
      if p.parsers then
        specs[#specs + 1] = { "nvim-treesitter/nvim-treesitter", opts = { ensure_installed = p.parsers } }
      end
      if p.servers then
        specs[#specs + 1] = { "neovim/nvim-lspconfig", opts = { servers = p.servers } }
      end
      if p.tools then
        specs[#specs + 1] = { "mason-org/mason.nvim", opts = { ensure_installed = p.tools } }
      end
      if p.formatters or p.formatter_opts then
        specs[#specs + 1] = {
          "stevearc/conform.nvim",
          opts = { formatters_by_ft = p.formatters, formatters = p.formatter_opts },
        }
      end
      if p.linters then
        specs[#specs + 1] = { "mfussenegger/nvim-lint", opts = { linters_by_ft = p.linters } }
      end
      vim.list_extend(specs, p.plugins or {})
    end
  end
  return specs
end

---@param name string
---@param on boolean
function M.set(name, on)
  local state = M.state()
  local function remove(list)
    return vim.tbl_filter(function(n)
      return n ~= name
    end, list)
  end
  state.enabled = remove(state.enabled)
  state.disabled = remove(state.disabled)
  local in_config = vim.tbl_contains(require("lumen.config").packs or {}, name)
  if on and not in_config then
    table.insert(state.enabled, name)
  elseif not on and in_config then
    table.insert(state.disabled, name)
  end
  M.save(state)
end

function M.prompt_restart(msg)
  if vim.fn.exists(":restart") == 2 then
    vim.ui.select({ "Restart now", "Later" }, { prompt = msg .. " — restart to apply" }, function(choice)
      if choice == "Restart now" then
        vim.cmd("restart")
      end
    end)
  else
    Lumen.notify(msg .. "\nRestart Neovim to apply.")
  end
end

-- filetype → pack, built lazily on first use
local ft_index
local shown = {}

---@param ft string
function M.suggest(ft)
  -- headless (tests, scripts): nobody can answer a prompt, and a blocking one would hang
  if ft == "" or shown[ft] or #vim.api.nvim_list_uis() == 0 then
    return
  end
  shown[ft] = true
  if not ft_index then
    ft_index = {}
    for _, name in ipairs(M.available()) do
      local ok, p = pcall(require, "lumen.packs." .. name)
      for _, f in ipairs(ok and p.ft or {}) do
        ft_index[f] = ft_index[f] or name
      end
    end
  end
  local name = ft_index[ft]
  if not name or M.enabled()[name] or vim.tbl_contains(M.state().dismissed, name) then
    return
  end
  vim.ui.select({ "Enable", "Not now", "Never for this pack" }, {
    prompt = ("󰛨 Lumen has a `%s` pack (LSP, formatter, parsers) for %s files"):format(name, ft),
  }, function(choice)
    if choice == "Enable" then
      M.set(name, true)
      M.prompt_restart(("Enabled pack `%s`"):format(name))
    elseif choice == "Never for this pack" then
      local state = M.state()
      table.insert(state.dismissed, name)
      M.save(state)
    end
  end)
end

--- interactive pack manager
function M.pick()
  local enabled = M.enabled()
  local items = {}
  for _, name in ipairs(M.available()) do
    local p = M.get(name) or {}
    items[#items + 1] = {
      text = name,
      name = name,
      on = enabled[name] == true,
      desc = p.desc or table.concat(p.ft or {}, ", "),
      servers = table.concat(vim.tbl_keys(p.servers or {}), ", "),
    }
  end
  local function snapshot()
    local names = vim.tbl_keys(M.enabled())
    table.sort(names)
    return table.concat(names, ",")
  end
  local before = snapshot()
  Snacks.picker({
    title = "Language Packs",
    items = items,
    layout = { preset = "select" },
    format = function(item)
      return {
        { item.on and "  " or "  ", item.on and "DiagnosticOk" or "Comment" },
        { ("%-12s"):format(item.name), item.on and "Title" or "Normal" },
        { item.desc, "Comment" },
        { item.servers ~= "" and ("  󰒋 " .. item.servers) or "", "SnacksPickerDir" },
      }
    end,
    confirm = function(picker, item)
      if not item then
        return
      end
      item.on = not item.on
      M.set(item.name, item.on)
      picker:find({ refresh = true })
    end,
    on_close = function()
      if snapshot() ~= before then
        vim.schedule(function()
          M.prompt_restart("Language packs updated")
        end)
      end
    end,
  })
end

return M
