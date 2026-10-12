-- Headless smoke test. Run with scripts/test.sh (isolated XDG dirs, never touches your config).
-- The checks live in tests/smoke/<area>.lua. `./scripts/test.sh <text>` only runs the checks whose
-- name contains <text> (case-insensitive), plus "no startup errors".
local failures, passes, skipped = {}, 0, 0
-- shared CI runners are slower and download servers on first use: stretch time limits there
local SLOW = vim.env.CI and 4 or 1
local FILTER = (vim.env.LUMEN_TEST_FILTER or ""):lower()

local function check(name, fn)
  if FILTER ~= "" and not name:lower():find(FILTER, 1, true) and name ~= "no startup errors" then
    skipped = skipped + 1
    return
  end
  local errmsg = vim.v.errmsg
  local ok, err = pcall(fn)
  -- name the first check that leaves an error behind ("no startup errors" fails on it at the end)
  if vim.v.errmsg ~= errmsg and vim.v.errmsg ~= "" and not vim.g.lumen_test_errmsg_by then
    vim.g.lumen_test_errmsg_by = name
  end
  if ok then
    passes = passes + 1
    io.stdout:write("  ✓ " .. name .. "\n")
  else
    failures[#failures + 1] = name
    io.stdout:write("  ✗ " .. name .. "\n      " .. tostring(err):gsub("\n", "\n      ") .. "\n")
  end
end

local function wait(ms, cond)
  return vim.wait(ms, cond, 50)
end

--- Starts an in-process fake language server `name` with `capabilities` for `buf`
---@return integer client_id
local function fake_server(name, capabilities, buf)
  return assert(vim.lsp.start({
    name = name,
    cmd = function()
      return {
        request = function(method, _, callback)
          if method == "initialize" then
            callback(nil, { capabilities = capabilities })
          end
          return true, 1
        end,
        notify = function()
          return true
        end,
        is_closing = function()
          return false
        end,
        terminate = function() end,
      }
    end,
  }, { bufnr = buf }))
end

--- Runs `probe` (Lua source; it must print one JSON object and quit) in a child Neovim using a
--- throwaway copy of the sandbox config with `files` added (e.g. `lua/plugins/x.lua`), so the
--- running suite never sees those specs. Returns the decoded JSON plus the raw result.
---@param probe string
---@param files? table<string, string> path (relative to the config dir) → contents
---@param args? string[] extra arguments for the child
---@param timeout? integer ms (default 60s, stretched on CI)
local function child(probe, files, args, timeout)
  local cfg = vim.fn.stdpath("config")
  local root = vim.fn.tempname()
  local dir = root .. "/" .. vim.fn.fnamemodify(cfg, ":t")
  vim.fn.mkdir(dir, "p")
  vim.fn.system({ "cp", "-R", cfg .. "/.", dir })
  for path, text in pairs(files or {}) do
    vim.fn.mkdir(vim.fn.fnamemodify(dir .. "/" .. path, ":h"), "p")
    vim.fn.writefile(vim.split(text, "\n"), dir .. "/" .. path)
  end
  local cmd = { vim.v.progpath, "--headless", "-c", "lua " .. probe:gsub("\n", " ") }
  vim.list_extend(cmd, args or {})
  local out = vim.system(cmd, { text = true, env = { XDG_CONFIG_HOME = root } }):wait((timeout or 60000) * SLOW)
  vim.fn.delete(root, "rf")
  return vim.json.decode((out.stdout or ""):match("{.*}") or "{}"), out
end

---@class lumen.test.Helpers
local helpers = { check = check, wait = wait, child = child, fake_server = fake_server, SLOW = SLOW }

-- one file per area, in this order: later files can rely on state the earlier ones left (an
-- attached lua_ls, installed parsers)
local files = { "theme", "ui", "packs", "tasks", "why", "startup", "keys", "update" }

local function run()
  io.stdout:write("\nLumen smoke test\n")
  local dir = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h") .. "/smoke/"
  for _, name in ipairs(files) do
    local ok, err = pcall(function()
      dofile(dir .. name .. ".lua")(helpers)
    end)
    if not ok then
      failures[#failures + 1] = name .. ".lua"
      io.stdout:write(("  ✗ %s.lua crashed: %s\n"):format(name, err))
    end
  end

  check("no startup errors", function()
    assert(vim.v.errmsg == "", vim.v.errmsg .. "\n(first left by: " .. tostring(vim.g.lumen_test_errmsg_by) .. ")")
  end)

  io.stdout:write(
    ("\n%d passed, %d failed%s\n"):format(passes, #failures, skipped > 0 and (", %d skipped"):format(skipped) or "")
  )
  vim.cmd(#failures == 0 and "qa!" or "cquit 1")
end

vim.schedule(function()
  local ok, err = pcall(run)
  if not ok then
    io.stdout:write("crashed: " .. tostring(err) .. "\n")
    vim.cmd("cquit 2")
  end
end)
