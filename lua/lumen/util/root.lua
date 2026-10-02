-- Project root detection: LSP workspace → root markers → cwd.
-- Results are cached per buffer and invalidated when anything relevant changes.

local M = {}

M.markers = { ".git", "package.json", "Cargo.toml", "go.mod", "pyproject.toml", "Makefile", "lua", ".root" }

---@type table<integer, string>
local cache = {}
---@type table<integer, string> how each cached root was found
local source = {}

local function realpath(path)
  if not path or path == "" then
    return nil
  end
  return vim.fs.normalize(vim.uv.fs_realpath(path) or path)
end

---@param buf integer
local function from_lsp(buf)
  local file = realpath(vim.api.nvim_buf_get_name(buf))
  if not file then
    return
  end
  local best
  for _, client in ipairs(vim.lsp.get_clients({ bufnr = buf })) do
    local dirs = {}
    for _, ws in ipairs(client.workspace_folders or {}) do
      dirs[#dirs + 1] = vim.uri_to_fname(ws.uri)
    end
    dirs[#dirs + 1] = client.root_dir
    for _, dir in ipairs(dirs) do
      dir = realpath(dir)
      if dir and (file == dir or file:sub(1, #dir + 1) == dir .. "/") and (not best or #dir > #best) then
        best = dir
      end
    end
  end
  return best
end

---@param buf? integer
---@return string
function M.get(buf)
  buf = (buf == nil or buf == 0) and vim.api.nvim_get_current_buf() or buf
  if cache[buf] then
    return cache[buf]
  end
  local root, how = from_lsp(buf), "lsp workspace"
  if not root and vim.bo[buf].buftype == "" then
    root, how = vim.fs.root(buf, M.markers), "root marker"
  end
  if not root then
    root, how = vim.uv.cwd() or ".", "cwd (no LSP root or marker found)"
  end
  cache[buf], source[buf] = root, how
  return root
end

--- root plus how it was detected
---@param buf? integer
---@return string root, string source
function M.info(buf)
  buf = (buf == nil or buf == 0) and vim.api.nvim_get_current_buf() or buf
  local root = M.get(buf)
  return root, source[buf] or "?"
end

--- git root of the current buffer (falls back to project root)
function M.git()
  local root = M.get()
  local git = vim.fs.root(root, ".git")
  return git or root
end

vim.api.nvim_create_autocmd({ "LspAttach", "BufWritePost", "DirChanged", "BufEnter" }, {
  group = vim.api.nvim_create_augroup("lumen_root_cache", { clear = true }),
  callback = function(ev)
    if ev.event == "DirChanged" or ev.event == "LspAttach" then
      cache = {}
    else
      cache[ev.buf] = nil
    end
  end,
})

return setmetatable(M, {
  __call = function(_, buf)
    return M.get(buf)
  end,
})
