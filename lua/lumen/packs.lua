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
--     requires = { "go", { "python3", "python" } }, -- binaries Mason can't provide (any of a list)
--     extends = { "typescript" },                -- packs enabled along with this one
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
---@field requires? (string|string[])[] binaries the pack needs on PATH; a list means "any of these"
---@field extends? string[] packs this one builds on: enabling it enables them too

-- filetypes nvim-ts-autotag handles (its configs + aliases, minus plain typescript, which has
-- no JSX): packs load it on these instead of on every file
M.autotag_ft = {
  "astro",
  "blade",
  "dot",
  "elixir",
  "eruby",
  "glimmer",
  "handlebars",
  "hbs",
  "heex",
  "html",
  "htmlangular",
  "htmldjango",
  "javascript",
  "javascript.glimmer",
  "javascript.jsx",
  "javascriptreact",
  "liquid",
  "markdown",
  "php",
  "rescript",
  "rust",
  "svelte",
  "templ",
  "twig",
  "typescript.glimmer",
  "typescript.tsx",
  "typescriptreact",
  "vento",
  "vue",
  "xml",
}

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

local available ---@type string[]?

---@return string[]
function M.available()
  if available then
    return available
  end
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
  available = vim.fn.uniq(names) --[[@as string[] ]]
  return available
end

--- packs you chose: lua/config/lumen.lua, then :Lumen packs state, plus the project's .lumen.lua
---@return table<string, boolean>
local function chosen()
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
  for _, name in ipairs(require("lumen.project").packs()) do
    set[name] = true
  end
  return set
end

--- enabled packs, including the packs they extend
---@return table<string, boolean> enabled, table<string, string> via dependency → the pack that pulled it in
function M.enabled()
  local set, via = chosen(), {}
  local queue = vim.tbl_keys(set)
  table.sort(queue)
  while #queue > 0 do
    local name = table.remove(queue, 1)
    -- a quiet require, not M.get: a typo in config.packs is reported once, by specs(), and
    -- M.exists() would glob the packs dirs during startup
    local ok, p = pcall(require, "lumen.packs." .. name)
    for _, dep in ipairs(ok and type(p) == "table" and p.extends or {}) do
      if not set[dep] then
        set[dep], via[dep] = true, name
        queue[#queue + 1] = dep
      end
    end
  end
  return set, via
end

--- whether a pack file exists
---@param name string
function M.exists(name)
  return vim.tbl_contains(M.available(), name)
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

--- enabled pack names, every pack after the packs it extends: lazy.nvim merges `opts` in spec
--- order and replaces lists, so a pack's own lists (vue's vtsls `filetypes`) must come last
---@param set table<string, boolean>
---@return string[]
function M.ordered(set)
  local names, out, seen = vim.tbl_keys(set), {}, {}
  table.sort(names)
  local function visit(name)
    if seen[name] then
      return
    end
    seen[name] = true
    for _, dep in ipairs((M.get(name) or {}).extends or {}) do
      if set[dep] then
        visit(dep)
      end
    end
    out[#out + 1] = name
  end
  for _, name in ipairs(names) do
    visit(name)
  end
  return out
end

---@return LazySpec[]
function M.specs()
  local specs = {}
  for _, name in ipairs(M.ordered(M.enabled())) do
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

--- binaries a pack needs that aren't on PATH (alternatives are shown as `a / b`)
---@param pack lumen.Pack
---@return string[]
function M.missing(pack)
  local out = {}
  for _, req in ipairs(pack.requires or {}) do
    local names = type(req) == "table" and req or { req }
    local found = vim.iter(names):any(function(n)
      return vim.fn.executable(n) == 1
    end)
    if not found then
      out[#out + 1] = table.concat(names, " / ")
    end
  end
  return out
end

--- resolved `opts` of a plugin spec (what its config would get), or {}
local function spec_opts(plugin)
  local p = require("lazy.core.config").plugins[plugin]
  return p and require("lazy.core.plugin").values(p, "opts", false) or {}
end

--- load a plugin now, unless it is disabled or missing
local function load(plugin)
  local p = require("lazy.core.config").plugins[plugin]
  if not p then
    return false
  end
  if not p._.loaded then
    require("lazy").load({ plugins = { plugin } })
  end
  return true
end

--- Turn on packs in the running Neovim: servers, parsers, Mason tools, formatters and linters all
--- have runtime APIs. Packs that add plugins can't be applied live (lazy.nvim builds its plugin list
--- once): those are returned, and need a restart.
---@param names string[] packs that just got enabled, with the packs they extend (see M.changed)
---@return string[] restart packs that only take effect after a restart
function M.apply(names)
  local set = {}
  for _, name in ipairs(names) do
    set[name] = true
  end
  local restart = {}
  local servers, parsers, tools, formatters, formatter_opts, linters = {}, {}, {}, {}, {}, {}
  for _, name in ipairs(M.ordered(set)) do
    local p = M.get(name)
    if p and p.plugins and #p.plugins > 0 then
      restart[#restart + 1] = name
    elseif p then
      if p.setup then
        local ok, err = pcall(p.setup)
        if not ok then
          Lumen.error(("pack `%s` setup failed:\n%s"):format(name, err))
        end
      end
      servers = vim.tbl_deep_extend("force", servers, p.servers or {})
      vim.list_extend(parsers, p.parsers or {})
      vim.list_extend(tools, p.tools or {})
      formatters = vim.tbl_extend("force", formatters, p.formatters or {})
      formatter_opts = vim.tbl_deep_extend("force", formatter_opts, p.formatter_opts or {})
      linters = vim.tbl_extend("force", linters, p.linters or {})
    end
  end

  if next(servers) and load("nvim-lspconfig") then
    -- your own server settings (lua/plugins/) win over the pack's, as they do at startup
    local yours = spec_opts("nvim-lspconfig").servers or {}
    for name, server in pairs(servers) do
      if yours[name] ~= nil then
        servers[name] = type(yours[name]) == "table" and vim.tbl_deep_extend("force", server, yours[name])
          or yours[name]
      end
    end
    require("lumen.lsp").add(servers)
  end
  if #tools > 0 then
    require("lumen.lsp").install(tools)
  end
  if #parsers > 0 and load("nvim-treesitter") then
    local ts = require("lumen.treesitter")
    ts.ensure(parsers)
    for _, b in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_loaded(b) and vim.bo[b].filetype ~= "" then
        ts.attach(b)
      end
    end
  end
  -- formatters and linters: only fill filetypes nobody configured yet (yours or another pack's)
  if (next(formatters) or next(formatter_opts)) and load("conform.nvim") then
    local conform = require("conform")
    for ft, list in pairs(formatters) do
      conform.formatters_by_ft[ft] = conform.formatters_by_ft[ft] or list
    end
    for name, opts in pairs(formatter_opts) do
      conform.formatters[name] = conform.formatters[name] or opts
    end
  end
  if next(linters) and load("nvim-lint") then
    local lint = require("lint")
    for ft, list in pairs(linters) do
      lint.linters_by_ft[ft] = lint.linters_by_ft[ft] or list
    end
  end
  -- a pack's setup() may add filetype rules: detect again where detection found nothing
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(b) and vim.bo[b].buftype == "" and vim.bo[b].filetype == "" then
      vim.api.nvim_buf_call(b, function()
        vim.cmd("filetype detect")
      end)
    end
  end
  vim.api.nvim_exec_autocmds("User", { pattern = "LumenPacksChanged", modeline = false })
  return restart
end

--- Enable or disable a pack, applying it right away when that's possible
---@param name string
---@param on boolean
function M.toggle(name, on)
  local before = M.enabled()
  M.set(name, on)
  local after, via = M.enabled()
  -- still on: it comes from the project's .lumen.lua, or another pack extends it
  if not on and after[name] then
    local why = via[name] and ("the `%s` pack extends it"):format(via[name])
      or (vim.tbl_contains(require("lumen.project").packs(), name) and "this project's .lumen.lua enables it")
      or "it is still enabled"
    Lumen.warn(("Pack `%s` stays on: %s"):format(name, why))
  end
  M.changed(before, after)
end

--- tell the user what a change of enabled packs needs: nothing, or a restart
---@param before table<string, boolean>
---@param after table<string, boolean>
function M.changed(before, after)
  local added, removed = {}, {}
  for name in pairs(after) do
    if not before[name] then
      added[#added + 1] = name
    end
  end
  for name in pairs(before) do
    if not after[name] then
      removed[#removed + 1] = name
    end
  end
  table.sort(added)
  table.sort(removed)
  if #added == 0 and #removed == 0 then
    return
  end
  local restart = M.apply(added)
  local live = vim.tbl_filter(function(n)
    return not vim.tbl_contains(restart, n)
  end, added)
  if #live > 0 then
    Lumen.notify(("Enabled %s — ready in this session"):format(M.quote(live)))
  end
  if #restart > 0 or #removed > 0 then
    local parts = {}
    if #restart > 0 then
      parts[#parts + 1] = ("Enabled %s (adds plugins)"):format(M.quote(restart))
    end
    if #removed > 0 then
      parts[#parts + 1] = ("Disabled %s"):format(M.quote(removed))
    end
    M.prompt_restart(table.concat(parts, " · "))
  end
end

---@param names string[]
function M.quote(names)
  return (#names == 1 and "pack " or "packs ") .. "`" .. table.concat(names, "`, `") .. "`"
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

--- the pack that supports `ft` and isn't enabled or dismissed, if any
---@param ft string
---@return string?
function M.suggestion(ft)
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
  return name
end

---@param name string
---@param ft string
function M.suggest_message(name, ft)
  local lines = {
    ("Lumen has a `%s` pack (LSP, formatter, parsers) for %s files"):format(name, ft),
    ("• enable: `:Lumen packs enable %s`"):format(name),
    ("• stop asking: `:Lumen packs dismiss %s`"):format(name),
  }
  local missing = M.missing(M.get(name) or {})
  if #missing > 0 then
    table.insert(lines, 2, ("• needs `%s` on your PATH"):format(table.concat(missing, "`, `")))
  end
  return table.concat(lines, "\n")
end

--- a notification, not a prompt: it must not grab the keyboard while a file opens
---@param ft string
function M.suggest(ft)
  -- headless (tests, scripts): nobody reads it
  if ft == "" or shown[ft] or #vim.api.nvim_list_uis() == 0 then
    return
  end
  shown[ft] = true
  local name = M.suggestion(ft)
  if name then
    Lumen.notify(M.suggest_message(name, ft), nil, { id = "lumen.pack_suggest", timeout = 10000 })
  end
end

---@param name string
function M.dismiss(name)
  local state = M.state()
  if not vim.tbl_contains(state.dismissed, name) then
    table.insert(state.dismissed, name)
    M.save(state)
  end
end

--- interactive pack manager
function M.pick()
  local items = {}
  for _, name in ipairs(M.available()) do
    local p = M.get(name) or {}
    items[#items + 1] = {
      text = name,
      name = name,
      desc = p.desc or table.concat(p.ft or {}, ", "),
      servers = table.concat(vim.tbl_keys(p.servers or {}), ", "),
    }
  end
  -- on/off and "needed by" for every item: toggling one pack can pull in the packs it extends
  local function mark()
    local enabled, via = M.enabled()
    for _, item in ipairs(items) do
      item.on, item.via = enabled[item.name] == true, via[item.name]
    end
  end
  mark()
  local before = M.enabled()
  if not _G.Snacks then
    -- snacks.nvim disabled: toggle one pack per pick
    return vim.ui.select(items, {
      prompt = "Language packs (toggle)",
      format_item = function(item)
        return ("%s %-12s %s"):format(item.on and "●" or "○", item.name, item.desc)
      end,
    }, function(item)
      if item then
        M.toggle(item.name, not item.on)
      end
    end)
  end
  Snacks.picker({
    title = "Language Packs · <cr> toggles",
    items = items,
    layout = { preset = "select" },
    format = function(item)
      return {
        { item.on and "  " or "  ", item.on and "DiagnosticOk" or "Comment" },
        { ("%-12s"):format(item.name), item.on and "Title" or "Normal" },
        { item.desc, "Comment" },
        { item.via and ("  needed by " .. item.via) or "", "DiagnosticInfo" },
        { item.servers ~= "" and ("  󰒋 " .. item.servers) or "", "SnacksPickerDir" },
      }
    end,
    confirm = function(picker, item)
      if not item then
        return
      end
      M.set(item.name, not item.on)
      mark()
      picker:find({ refresh = true })
    end,
    on_close = function()
      vim.schedule(function()
        M.changed(before, M.enabled())
      end)
    end,
  })
end

return M
