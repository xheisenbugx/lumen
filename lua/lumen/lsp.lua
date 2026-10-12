-- Native LSP (vim.lsp.config / vim.lsp.enable) + automatic Mason installs.
local config = require("lumen.config")

local M = {}

---@type table<string, table> per-server extra keymaps: { { lhs, rhs, desc = "" } }
local server_keys = {}

---@type table<string, {mason:boolean}> servers Lumen enabled (used by :Lumen why)
M.servers = {}

-- buffers longer than this keep treesitter folds instead of LSP folds (see on_attach)
M.lsp_fold_max_lines = 10000

---@param client vim.lsp.Client
---@param buf integer
local function on_attach(client, buf)
  local function map(lhs, rhs, desc, mode, method)
    if method and not client:supports_method(method, buf) then
      return
    end
    vim.keymap.set(mode or "n", lhs, rhs, { buffer = buf, desc = desc, silent = true, nowait = true })
  end

  -- Snacks' pickers when available, the built-in lists otherwise
  local function pick(source, fallback)
    return function()
      if _G.Snacks then
        return Snacks.picker[source]()
      end
      fallback()
    end
  end
  local lb = vim.lsp.buf

  -- stylua: ignore start
  map("gd", pick("lsp_definitions", lb.definition), "Goto definition", nil, "textDocument/definition")
  map("gD", pick("lsp_declarations", lb.declaration), "Goto declaration", nil, "textDocument/declaration")
  map("gr", pick("lsp_references", lb.references), "References", nil, "textDocument/references")
  map("gI", pick("lsp_implementations", lb.implementation), "Goto implementation", nil, "textDocument/implementation")
  map("gy", pick("lsp_type_definitions", lb.type_definition), "Goto type definition", nil, "textDocument/typeDefinition")
  map("gai", pick("lsp_incoming_calls", lb.incoming_calls), "Incoming calls", nil, "callHierarchy/incomingCalls")
  map("gao", pick("lsp_outgoing_calls", lb.outgoing_calls), "Outgoing calls", nil, "callHierarchy/outgoingCalls")
  map("K", function() vim.lsp.buf.hover() end, "Hover", nil, "textDocument/hover")
  map("gK", function() vim.lsp.buf.signature_help() end, "Signature help", nil, "textDocument/signatureHelp")
  map("<c-k>", function() vim.lsp.buf.signature_help() end, "Signature help", "i", "textDocument/signatureHelp")
  map("<leader>ca", vim.lsp.buf.code_action, "Code action", { "n", "x" }, "textDocument/codeAction")
  map("<leader>cr", vim.lsp.buf.rename, "Rename symbol", nil, "textDocument/rename")
  map("<leader>cc", vim.lsp.codelens.run, "Run codelens", { "n", "x" }, "textDocument/codeLens")
  map("<leader>cl", pick("lsp_config", function() vim.cmd("checkhealth vim.lsp") end), "LSP info")
  map("<leader>cA", function()
    vim.lsp.buf.code_action({ apply = true, context = { only = { "source" }, diagnostics = {} } })
  end, "Source action", nil, "textDocument/codeAction")
  -- stylua: ignore end

  for _, k in ipairs(server_keys[client.name] or {}) do
    map(k[1], k[2], k.desc, k.mode)
  end

  if config.inlay_hints and client:supports_method("textDocument/inlayHint", buf) and vim.bo[buf].buftype == "" then
    vim.lsp.inlay_hint.enable(true, { bufnr = buf })
  end

  -- prefer LSP folding when the server provides it, except in very large buffers: each
  -- foldingRange response re-evaluates the folds of the whole buffer (~60-100ms at 40k lines,
  -- after every edit); treesitter folds there (the default foldexpr) update incrementally
  if
    client:supports_method("textDocument/foldingRange", buf)
    and vim.api.nvim_buf_line_count(buf) <= M.lsp_fold_max_lines
  then
    local win = vim.fn.bufwinid(buf)
    if win ~= -1 then
      vim.wo[win][0].foldexpr = "v:lua.vim.lsp.foldexpr()"
    end
  end
end

-- mason packages for lspconfig names
function M.package_for(server)
  local ok, mlsp = pcall(require, "mason-lspconfig")
  if not ok then
    return
  end
  local map = mlsp.get_mappings().lspconfig_to_package
  return map[server]
end

---@param pkgs string[]
---@param on_done? fun(pkg:string)
function M.install(pkgs, on_done)
  if #pkgs == 0 then
    return
  end
  -- never block startup: the registry refresh alone costs ~10ms
  vim.defer_fn(function()
    M._install(pkgs, on_done)
  end, 300)
end

function M._install(pkgs, on_done)
  if #pkgs == 0 then
    return
  end
  local registry = require("mason-registry")
  registry.refresh(function()
    local todo = {} ---@type table[]
    for _, name in ipairs(pkgs) do
      local ok, pkg = pcall(registry.get_package, name)
      if not ok then
        Lumen.warn("Mason: unknown package `" .. name .. "`")
      elseif not pkg:is_installed() and not pkg:is_installing() then
        todo[#todo + 1] = pkg
      end
    end
    if #todo == 0 then
      return
    end
    -- one notification for the whole batch, updated in place, instead of two toasts per package
    local names = vim.tbl_map(function(pkg)
      return pkg.name
    end, todo)
    local id = "lumen.mason." .. table.concat(names, ",")
    local left, failed = #todo, {}
    local function progress()
      Lumen.notify(
        ("Installing %s… (%d/%d)"):format(table.concat(names, ", "), #todo - left, #todo),
        nil,
        { id = id, timeout = false }
      )
    end
    progress()
    for _, pkg in ipairs(todo) do
      pkg:install({}, function(success)
        vim.schedule(function()
          left = left - 1
          if success then
            -- for caches of what's on PATH (nvim-lint's runnable linters)
            vim.api.nvim_exec_autocmds("User", { pattern = "LumenToolInstalled", data = pkg.name, modeline = false })
            if on_done then
              on_done(pkg.name)
            end
          else
            failed[#failed + 1] = pkg.name
          end
          if left > 0 then
            return progress()
          elseif #failed == 0 then
            Lumen.notify("Installed " .. table.concat(names, ", "), nil, { id = id, timeout = 2500 })
          else
            Lumen.error(("Failed to install %s — see :MasonLog"):format(table.concat(failed, ", ")), { id = id })
          end
        end)
      end)
    end
  end)
end

--- Put Mason's bin dir on PATH (what mason.setup() does), so servers it installed can start
--- without loading mason.nvim while a file is being opened. Returns true once it is on PATH.
---@param mopts? table mason.nvim opts (resolved from its spec when omitted)
function M.mason_path(mopts)
  if not mopts then
    local plugin = require("lazy.core.config").plugins["mason.nvim"]
    mopts = plugin and require("lazy.core.plugin").values(plugin, "opts", false) or {}
  end
  if mopts.PATH == "skip" then
    return false
  end
  local sep = vim.fn.has("win32") == 1 and ";" or ":"
  local bin = M.mason_root(mopts) .. "/bin"
  local path = vim.env.PATH or ""
  if not (sep .. path .. sep):find(sep .. bin .. sep, 1, true) then
    vim.env.PATH = mopts.PATH == "append" and (path .. sep .. bin) or (bin .. sep .. path)
  end
  return true
end

--- Mason's install root (the `install_root_dir` from its spec, or the default)
---@param mopts? table mason.nvim opts (resolved from its spec when omitted)
function M.mason_root(mopts)
  if not mopts then
    local plugin = require("lazy.core.config").plugins["mason.nvim"]
    mopts = plugin and require("lazy.core.plugin").values(plugin, "opts", false) or {}
  end
  return vim.fs.normalize(mopts.install_root_dir or (vim.fn.stdpath("data") .. "/mason"))
end

--- Server tables are data, written before Mason's install root is known (packs are read while
--- lazy.nvim builds specs): strings starting with `$MASON/` resolve against it here.
---@param value any
---@param root string
function M.expand_mason(value, root)
  if type(value) == "string" then
    return value:find("^%$MASON/") and (root .. value:sub(7)) or value
  elseif type(value) == "table" then
    local out = {}
    for k, v in pairs(value) do
      out[k] = M.expand_mason(v, root)
    end
    return setmetatable(out, getmetatable(value))
  end
  return value
end

--- whether `name`'s binary is available: on PATH for a plain `cmd`, or installed by Mason for a
--- function `cmd` (lspconfig resolves those when the server starts, so there's no binary to probe)
---@param name string
---@param pkg string mason package
local function server_installed(name, pkg)
  local cmd = (vim.lsp.config[name] or {}).cmd
  if type(cmd) == "table" and type(cmd[1]) == "string" then
    return vim.fn.executable(cmd[1]) == 1
  end
  local ok, registry = pcall(require, "mason-registry")
  return ok and registry.is_installed(pkg)
end

local did_setup = false

--- Configure and enable servers. Called with the merged nvim-lspconfig opts at startup, and again
--- by packs enabled while Neovim runs (`:Lumen packs enable …`).
---@param servers table<string, table|false>
function M.add(servers)
  local mason_servers, enable = {}, {}
  local root = M.mason_root()
  for name, server in pairs(servers or {}) do
    if server and server.enabled ~= false then
      server = M.expand_mason(vim.deepcopy(server), root)
      if server.mason ~= false then
        mason_servers[#mason_servers + 1] = name
      end
      M.servers[name] = { mason = server.mason ~= false }
      server_keys[name] = server.keys
      server.mason, server.enabled, server.keys = nil, nil, nil
      if next(server) then
        vim.lsp.config(name, server)
      end
      enable[#enable + 1] = name
    end
  end
  if #enable == 0 then
    return
  end

  -- After startup, vim.lsp.enable() fires FileType for open buffers. We usually get here from
  -- the BufReadPost (LazyFile) that is opening a file, *before* Neovim's filetype detection runs;
  -- an extra FileType in that chain makes `:setf` a no-op and the new buffer ends up with no
  -- filetype at all. So enable on the next tick, once detection has run.
  if vim.v.vim_did_enter == 1 then
    vim.schedule(function()
      vim.lsp.enable(enable)
    end)
  else
    vim.lsp.enable(enable)
  end

  -- resolve missing servers → mason packages after startup
  vim.defer_fn(function()
    -- load mason now (its config installs missing tools)
    pcall(require, "mason")
    local to_install, pkg_to_server = {}, {}
    for _, name in ipairs(mason_servers) do
      local pkg = M.package_for(name)
      if pkg and not server_installed(name, pkg) then
        to_install[#to_install + 1] = pkg
        pkg_to_server[pkg] = name
      end
    end
    M._install(to_install, function(pkg)
      -- enabling again re-runs vim.lsp's FileType handler on every open buffer, so the server
      -- attaches to the files that were waiting for it
      pcall(vim.lsp.enable, pkg_to_server[pkg])
    end)
  end, 300)
end

function M.setup(opts)
  if not did_setup then
    did_setup = true
    require("lumen.diagnostics").setup()
    M.mason_path()
    vim.api.nvim_create_autocmd("LspAttach", {
      group = vim.api.nvim_create_augroup("lumen_lsp_attach", { clear = true }),
      callback = function(ev)
        local client = vim.lsp.get_client_by_id(ev.data.client_id)
        if client then
          on_attach(client, ev.buf)
        end
      end,
    })
  end
  M.add(opts.servers)
end

return M
