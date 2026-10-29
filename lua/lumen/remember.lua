-- Remembers what you change from the UI (colorscheme, <leader>u toggles, the diagnostics display)
-- across restarts, in stdpath("state")/lumen/ui.json.
--
-- Each entry keeps the value you picked and the `base` it replaced: the value your config gave at
-- the time. When the config changes that setting later (another colorscheme in lua/config/lumen.lua,
-- `wrap` in options.lua…), the base no longer matches and the config wins again.
local M = {}

M.file = vim.fn.stdpath("state") .. "/lumen/ui.json"

local data ---@type table<string, {value:any, base:any}>?

local function enabled()
  return require("lumen.config").remember ~= false
end

local function load()
  if not data then
    data = {}
    local f = io.open(M.file, "r")
    if f then
      local ok, decoded = pcall(vim.json.decode, f:read("*a"))
      f:close()
      data = ok and type(decoded) == "table" and decoded or {}
    end
  end
  return data
end

local function write()
  vim.fn.mkdir(vim.fs.dirname(M.file), "p")
  local f = io.open(M.file, "w")
  if f then
    f:write(vim.json.encode(data))
    f:close()
  end
end

--- the remembered value for `key`, if it was picked over the same `base` the config gives now
---@param key string
---@param base any
---@return any?
function M.get(key, base)
  if not enabled() then
    return nil
  end
  local entry = load()[key]
  if type(entry) ~= "table" then
    return nil
  end
  if not vim.deep_equal(entry.base, base) then
    -- the config changed this setting since: forget the old pick
    data[key] = nil
    write()
    return nil
  end
  return entry.value
end

---@param key string
---@param value any
---@param base any the value the config gives
function M.set(key, value, base)
  if not enabled() then
    return
  end
  local entry = load()[key]
  if entry and vim.deep_equal(entry.value, value) and vim.deep_equal(entry.base, base) then
    return
  end
  -- back to what the config says: nothing to remember
  data[key] = not vim.deep_equal(value, base) and { value = value, base = base } or nil
  write()
end

--- forget everything (`:Lumen forget`)
function M.reset()
  data = {}
  os.remove(M.file)
end

-- ── colorscheme ──────────────────────────────────────────────

--- the colorscheme (and 'background') to start with
---@return string name, string? background
function M.colorscheme()
  local config = require("lumen.config")
  M.scheme_base = { config.colorscheme, vim.o.background }
  local saved = M.get("colorscheme", M.scheme_base)
  if type(saved) == "table" and type(saved[1]) == "string" then
    return saved[1], saved[2]
  end
  return config.colorscheme
end

--- remember colorscheme / 'background' changes from now on (call after the first colorscheme loads)
function M.watch_colorscheme()
  local pending = false
  local function save()
    -- the picker previews schemes, and `lumen` reloads on a 'background' change: save the end state
    if pending then
      return
    end
    pending = true
    vim.schedule(function()
      pending = false
      if vim.g.colors_name and M.scheme_base then
        M.set("colorscheme", { vim.g.colors_name, vim.o.background }, M.scheme_base)
      end
    end)
  end
  local group = vim.api.nvim_create_augroup("lumen_remember_colorscheme", { clear = true })
  vim.api.nvim_create_autocmd("ColorScheme", { group = group, callback = save })
  vim.api.nvim_create_autocmd("OptionSet", { group = group, pattern = "background", callback = save })
end

-- ── toggles ──────────────────────────────────────────────────

-- window options the Snacks toggles set for the current window only: restored for every window
local window_options = {
  spell = { "spell" },
  wrap = { "wrap" },
  relativenumber = { "relativenumber" },
  conceallevel = { "conceallevel" },
  line_number = { "number", "relativenumber" },
}

---@class lumen.remember.ToggleOpts
---@field base? fun(): boolean the config's state (default: the toggle's state when restored)
---@field apply? fun(state: boolean) make `state` the default (restoring, and on every toggle); restoring
---then skips the toggle's own `set`
---@field plugin? string restore once this plugin has loaded (its toggle would load it)

-- whether the current window's value of these options differs from the global one, i.e. the
-- filetype set it (Lumen's prose autocmd turns on wrap and spell for markdown, text…)
local function local_differs(options)
  for _, option in ipairs(options) do
    if vim.wo[option] ~= vim.go[option] then
      return true
    end
  end
  return false
end

--- restore a Snacks toggle and remember its changes
---@param id string Snacks.toggle id
---@param opts? lumen.remember.ToggleOpts
function M.toggle(id, opts)
  opts = opts or {}
  local t = _G.Snacks and Snacks.toggle.toggles[id]
  if not t or not enabled() then
    return
  end
  local key = "toggle." .. id
  local options = window_options[id]
  -- a single window option the filetype set is remembered for that filetype ("toggle.wrap:markdown"):
  -- turning wrap off in a markdown buffer is about markdown, and the global value is off already
  local per_ft = options and #options == 1
  local function restore()
    local base = opts.base and opts.base() or t:get()
    if options and local_differs(options) then
      base = not base -- the current window has the filetype's value, the global one is the other
    end
    local set = t.opts.set
    t.opts.set = function(state)
      local ft = vim.bo.filetype
      local ft_key = per_ft and ft ~= "" and key .. ":" .. ft
      local entry = ft_key and load()[ft_key]
      local ft_base ---@type boolean?
      if type(entry) == "table" then
        ft_base = entry.base
      elseif ft_key and local_differs(options) then
        ft_base = t:get() -- the filetype's value, before this toggle
      end
      set(state)
      if opts.apply then
        opts.apply(state)
      end
      if ft_key and ft_base ~= nil then
        M.set(ft_key, state, ft_base)
      else
        M.set(key, state, base)
      end
    end
    if per_ft then
      vim.api.nvim_create_autocmd("FileType", {
        group = vim.api.nvim_create_augroup("lumen_remember_" .. id, { clear = true }),
        callback = function(ev)
          local entry = load()[key .. ":" .. ev.match]
          -- like the filetype's own settings: for the window showing the buffer
          if type(entry) ~= "table" or ev.buf ~= vim.api.nvim_get_current_buf() then
            return
          end
          -- only over the value the filetype gave when you picked (a config change wins)
          if t:get() == entry.base and entry.value ~= entry.base then
            set(entry.value)
          end
        end,
      })
    end
    local saved = M.get(key, base)
    if type(saved) ~= "boolean" or saved == base then
      return
    end
    if opts.apply then
      return opts.apply(saved)
    end
    if not options then
      return set(saved)
    end
    -- every window (except where the filetype set its own value) and, from one of them, the global
    -- value, so new windows get it too
    local from
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      vim.api.nvim_win_call(win, function()
        if not local_differs(options) then
          set(saved)
        end
        from = from or (t:get() == saved and win or nil)
      end)
    end
    for _, option in ipairs(from and options or {}) do
      vim.go[option] = vim.wo[from][option]
    end
  end
  if opts.plugin then
    Lumen.on_load(opts.plugin, restore)
  else
    restore()
  end
end

return M
