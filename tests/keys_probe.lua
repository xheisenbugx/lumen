-- Presses every mapping Lumen (or a plugin it ships) defines, in normal, visual and insert mode,
-- inside a scratch git project, and reports the ones that raise an error. Runs in a child Neovim
-- (tests/smoke/keys.lua) because it leaves all kinds of state behind.

-- keys that would end the test or reach outside the sandbox
local SKIP = {
  ["n <Space>qq"] = "quits Neovim",
  ["n <Space>qr"] = "restarts Neovim",
  ["n <Space>gB"] = "opens a web browser",
  ["x <Space>gB"] = "opens a web browser",
  ["n <Space>K"] = "runs 'keywordprg' (man) on the word under the cursor",
}

local dir ---@type string the scratch project (set below)

-- per-key preconditions, so a key is tested where it makes sense
local SETUP = {
  ["n <Space>wd"] = function()
    vim.cmd("split") -- closing the last window is E444 by design
  end,
  -- like <C-^>, these need an alternate file
  ["n <Space>bb"] = function()
    vim.cmd.edit(dir .. "/other.lua")
    vim.cmd.edit(dir .. "/main.lua")
  end,
  ["n <Space>`"] = function()
    vim.cmd.edit(dir .. "/other.lua")
    vim.cmd.edit(dir .. "/main.lua")
  end,
  -- from the first item there's no previous one (E553, as with Neovim's own [q)
  ["n [q"] = function()
    vim.cmd("silent! cc 2")
  end,
  -- from the last line, the A-j moves are no-ops: test them where they move something
  ["n <M-j>"] = function()
    vim.api.nvim_win_set_cursor(0, { 2, 0 })
  end,
}

-- errors that come from outside Lumen and that a user never sees
local function benign(msg)
  -- render-markdown.nvim leaves a caught E31 when it first loads (see AGENTS.md)
  return msg == "errmsg: E31: No such mapping"
end

local results = { tested = 0, skipped = {}, failed = {} }

-- ── a scratch project: a real git repo with a commit, a search pattern, a quickfix list ──
dir = vim.fs.normalize(vim.fn.tempname())
vim.fn.mkdir(dir, "p")
local src = vim.fs.normalize(vim.fn.stdpath("config") .. "/init.lua")
vim.fn.writefile(vim.fn.readfile(src), dir .. "/main.lua")
vim.fn.writefile({ "-- TODO: something", "local other = 1", "return other" }, dir .. "/other.lua")
for _, cmd in ipairs({
  { "git", "init", "-q" },
  { "git", "-c", "user.email=t@t", "-c", "user.name=t", "add", "." },
  { "git", "-c", "user.email=t@t", "-c", "user.name=t", "-c", "commit.gpgsign=false", "commit", "-qm", "init" },
}) do
  vim.system(cmd, { cwd = dir }):wait()
end
vim.cmd.cd(dir)

-- prompts would block a headless Neovim
vim.ui.select = function() end
vim.ui.input = function() end

-- Neovim's own mappings (as in `nvim --clean`): not Lumen's to test
local defaults = {}
do
  local out = vim
    .system({
      vim.v.progpath,
      "--clean",
      "--headless",
      "-c",
      [[lua local t = {} for _, m in ipairs({ "n", "x", "i" }) do for _, k in ipairs(vim.api.nvim_get_keymap(m)) do t[#t + 1] = m .. " " .. vim.fn.keytrans(k.lhsraw or k.lhs) .. " " .. (k.desc or k.rhs or "") end end io.stdout:write(vim.json.encode(t))]],
      "-c",
      "qa!",
    }, { text = true })
    :wait()
  for _, id in ipairs(vim.json.decode((out.stdout or ""):match("%[.*%]") or "[]")) do
    defaults[id] = true
  end
end

local function reset(file)
  pcall(function()
    for _, p in ipairs(Snacks.picker.get()) do
      p:close()
    end
  end)
  pcall(function()
    for _, t in ipairs(Snacks.terminal.list()) do
      t:close()
    end
  end)
  pcall(vim.cmd, "stopinsert")
  pcall(vim.api.nvim_feedkeys, vim.keycode("<Esc><Esc>"), "nx", false)
  for _, w in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_config(w).relative ~= "" then
      pcall(vim.api.nvim_win_close, w, true)
    end
  end
  pcall(vim.cmd, "silent! only!")
  if not (vim.api.nvim_buf_is_valid(file) and vim.api.nvim_buf_is_loaded(file)) then
    vim.cmd.edit(dir .. "/main.lua")
    file = vim.api.nvim_get_current_buf()
  end
  pcall(vim.api.nvim_set_current_buf, file)
  pcall(vim.api.nvim_win_set_cursor, 0, { 1, 0 })
  vim.fn.setreg("/", "local")
  vim.fn.setqflist({}, "r", {
    items = {
      { filename = dir .. "/main.lua", lnum = 1, text = "one" },
      { filename = dir .. "/other.lua", lnum = 2, text = "two" },
    },
  })
  return file
end

local function run()
  vim.cmd.edit(dir .. "/main.lua")
  local file = vim.api.nvim_get_current_buf()
  vim.wait(20000, function()
    return #vim.lsp.get_clients({ bufnr = file }) > 0
  end, 100)

  local keys, seen = {}, {}
  for _, mode in ipairs({ "n", "x", "i" }) do
    for _, list in ipairs({ vim.api.nvim_get_keymap(mode), vim.api.nvim_buf_get_keymap(file, mode) }) do
      for _, m in ipairs(list) do
        local lhs = vim.fn.keytrans(m.lhsraw or m.lhs)
        local id = mode .. " " .. lhs
        local default = defaults[id .. " " .. (m.desc or m.rhs or "")]
        if not seen[id] and not default and not lhs:find("^<Plug>") and not lhs:find("^<SNR>") then
          seen[id] = true
          keys[#keys + 1] = { id = id, mode = mode, lhs = lhs }
        end
      end
    end
  end
  table.sort(keys, function(a, b)
    return a.id < b.id
  end)

  for _, k in ipairs(keys) do
    if SKIP[k.id] then
      results.skipped[#results.skipped + 1] = k.id
    else
      file = reset(file)
      if SETUP[k.id] then
        SETUP[k.id]()
      end
      results.tested = results.tested + 1
      vim.v.errmsg = ""
      local errs, notify = {}, vim.notify
      vim.notify = function(msg, level, o)
        if level == vim.log.levels.ERROR then
          errs[#errs + 1] = tostring(msg)
        end
        return notify(msg, level, o)
      end
      -- anything left waiting for a key (which-key's popup, flash's label) gets an <Esc>
      local watchdog = vim.defer_fn(function()
        vim.api.nvim_input("<Esc><Esc>")
      end, 400)
      local prefix = ({ x = "V", i = "A" })[k.mode] or ""
      local suffix = k.mode == "i" and "<Esc>" or ""
      local ok, err = pcall(vim.api.nvim_feedkeys, vim.keycode(prefix .. k.lhs .. suffix), "mx", false)
      vim.wait(150)
      watchdog:stop()
      vim.notify = notify
      if not ok then
        errs[#errs + 1] = tostring(err)
      end
      if vim.v.errmsg ~= "" then
        errs[#errs + 1] = "errmsg: " .. vim.v.errmsg
      end
      errs = vim.tbl_filter(function(e)
        return not benign(e)
      end, errs)
      if #errs > 0 then
        results.failed[#results.failed + 1] = k.id .. " → " .. table.concat(errs, " | "):gsub("%s+", " "):sub(1, 300)
      end
    end
  end
  reset(file)
  -- clean up modified buffers so `qa!` doesn't matter and the project dir can go
  io.stdout:write(vim.json.encode(results) .. "\n")
  vim.fn.delete(dir, "rf")
  vim.cmd("qa!")
end

vim.defer_fn(run, 500)
