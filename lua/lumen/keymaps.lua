-- Core keymaps. Plugin keymaps live with their plugin spec (lua/lumen/plugins/*).
-- Press <leader> and wait: every mapping is discoverable via which-key.

local map = Lumen.map
local config = require("lumen.config")

-- ── movement ─────────────────────────────────────────────────
-- j/k move over wrapped lines unless a count is given
map({ "n", "x" }, "j", "v:count == 0 ? 'gj' : 'j'", { expr = true, desc = "Down" })
map({ "n", "x" }, "k", "v:count == 0 ? 'gk' : 'k'", { expr = true, desc = "Up" })

-- consistent n/N direction, centered
map("n", "n", "'Nn'[v:searchforward].'zzzv'", { expr = true, desc = "Next result" })
map("n", "N", "'nN'[v:searchforward].'zzzv'", { expr = true, desc = "Prev result" })
map({ "x", "o" }, "n", "'Nn'[v:searchforward]", { expr = true, desc = "Next result" })
map({ "x", "o" }, "N", "'nN'[v:searchforward]", { expr = true, desc = "Prev result" })

-- ── windows (tmux-aware) ─────────────────────────────────────
local tmux_dir = { h = "L", j = "D", k = "U", l = "R" }
for key, dir in pairs(tmux_dir) do
  map("n", "<C-" .. key .. ">", function()
    local win = vim.api.nvim_get_current_win()
    vim.cmd.wincmd(key)
    if config.tmux_navigation and win == vim.api.nvim_get_current_win() and Lumen.in_tmux() then
      vim.system({ "tmux", "select-pane", "-" .. dir })
    end
  end, { desc = "Go to " .. ({ h = "left", j = "lower", k = "upper", l = "right" })[key] .. " window" })
end

map("n", "<C-Up>", "<cmd>resize +2<cr>", { desc = "Increase height" })
map("n", "<C-Down>", "<cmd>resize -2<cr>", { desc = "Decrease height" })
map("n", "<C-Left>", "<cmd>vertical resize -2<cr>", { desc = "Decrease width" })
map("n", "<C-Right>", "<cmd>vertical resize +2<cr>", { desc = "Increase width" })

map("n", "<leader>-", "<C-W>s", { desc = "Split below", remap = true })
map("n", "<leader>|", "<C-W>v", { desc = "Split right", remap = true })
map("n", "<leader>wd", "<C-W>c", { desc = "Close window", remap = true })

-- ── buffers ──────────────────────────────────────────────────
map("n", "<S-h>", "<cmd>bprevious<cr>", { desc = "Prev buffer" })
map("n", "<S-l>", "<cmd>bnext<cr>", { desc = "Next buffer" })
map("n", "[b", "<cmd>bprevious<cr>", { desc = "Prev buffer" })
map("n", "]b", "<cmd>bnext<cr>", { desc = "Next buffer" })
map("n", "<leader>bb", "<cmd>e #<cr>", { desc = "Alternate buffer" })
map("n", "<leader>`", "<cmd>e #<cr>", { desc = "Alternate buffer" })
map("n", "<leader>bd", function()
  if _G.Snacks then
    return Snacks.bufdelete()
  end
  vim.cmd.bdelete()
end, { desc = "Delete buffer" })
map("n", "<leader>bo", function()
  if _G.Snacks then
    return Snacks.bufdelete.other()
  end
  local cur = vim.api.nvim_get_current_buf()
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if b ~= cur and vim.bo[b].buflisted then
      pcall(vim.cmd.bdelete, b)
    end
  end
end, { desc = "Delete other buffers" })
map("n", "<leader>bD", "<cmd>:bd<cr>", { desc = "Delete buffer & window" })

-- ── editing ──────────────────────────────────────────────────
map({ "i", "x", "n", "s" }, "<C-s>", "<cmd>w<cr><esc>", { desc = "Save file" })
map({ "i", "n", "s" }, "<esc>", function()
  vim.cmd.nohlsearch()
  if package.loaded["lumen.ui.scrollbar"] then
    vim.schedule(require("lumen.ui.scrollbar").refresh)
  end
  if vim.snippet and vim.snippet.active() then
    vim.snippet.stop()
  end
  return "<esc>"
end, { expr = true, desc = "Escape & clear search" })

map("n", "<A-j>", "<cmd>execute 'move .+' . v:count1<cr>==", { desc = "Move line down" })
map("n", "<A-k>", "<cmd>execute 'move .-' . (v:count1 + 1)<cr>==", { desc = "Move line up" })
map("i", "<A-j>", "<esc><cmd>m .+1<cr>==gi", { desc = "Move line down" })
map("i", "<A-k>", "<esc><cmd>m .-2<cr>==gi", { desc = "Move line up" })
map("x", "<A-j>", ":<C-u>execute \"'<,'>move '>+\" . v:count1<cr>gv=gv", { desc = "Move lines down" })
map("x", "<A-k>", ":<C-u>execute \"'<,'>move '<-\" . (v:count1 + 1)<cr>gv=gv", { desc = "Move lines up" })

-- stay in visual mode while indenting
map("x", "<", "<gv")
map("x", ">", ">gv")

-- undo break-points while typing
for _, c in ipairs({ ",", ".", ";" }) do
  map("i", c, c .. "<c-g>u")
end

map("n", "gco", "o<esc>Vcx<esc><cmd>normal gcc<cr>fxa<bs>", { desc = "Add comment below" })
map("n", "gcO", "O<esc>Vcx<esc><cmd>normal gcc<cr>fxa<bs>", { desc = "Add comment above" })

map("n", "<leader>fn", "<cmd>enew<cr>", { desc = "New file" })

-- ── lists & diagnostics ──────────────────────────────────────
map("n", "[q", vim.cmd.cprev, { desc = "Prev quickfix" })
map("n", "]q", vim.cmd.cnext, { desc = "Next quickfix" })

local function diag_jump(count, severity)
  return function()
    vim.diagnostic.jump({ count = count, float = true, severity = severity and vim.diagnostic.severity[severity] })
  end
end
map("n", "]d", diag_jump(1), { desc = "Next diagnostic" })
map("n", "[d", diag_jump(-1), { desc = "Prev diagnostic" })
map("n", "]e", diag_jump(1, "ERROR"), { desc = "Next error" })
map("n", "[e", diag_jump(-1, "ERROR"), { desc = "Prev error" })
map("n", "]w", diag_jump(1, "WARN"), { desc = "Next warning" })
map("n", "[w", diag_jump(-1, "WARN"), { desc = "Prev warning" })
map("n", "<leader>cd", vim.diagnostic.open_float, { desc = "Line diagnostics" })
map("n", "<leader>cw", function()
  require("lumen.why").show()
end, { desc = "Why? (buffer setup report)" })
map("n", "<leader>cD", function()
  require("lumen.why").show({ deep = true })
end, { desc = "Doctor (deep report with fixes)" })

-- ── tasks (<leader>r) ────────────────────────────────────────
map("n", "<leader>rt", function()
  require("lumen.tasks").pick()
end, { desc = "Run task…" })
map("n", "<leader>rr", function()
  require("lumen.tasks").rerun()
end, { desc = "Re-run last task" })
map("n", "<leader>rq", function()
  local last = require("lumen.tasks").last()
  if last then
    require("lumen.tasks").run_background(last)
  else
    require("lumen.tasks").pick()
  end
end, { desc = "Re-run last task → quickfix" })
map("n", "<leader>uv", function()
  require("lumen.diagnostics").cycle()
end, { desc = "Cycle diagnostics display" })

-- ── toggles (<leader>u) ──────────────────────────────────────
-- (snacks.nvim provides them; Lumen still starts if you disable it)
if _G.Snacks then
  Snacks.toggle.option("spell", { name = "Spelling" }):map("<leader>us")
  Snacks.toggle.option("wrap", { name = "Wrap" }):map("<leader>uw")
  Snacks.toggle.option("relativenumber", { name = "Relative number" }):map("<leader>uL")
  Snacks.toggle.line_number():map("<leader>ul")
  Snacks.toggle.diagnostics():map("<leader>ud")
  Snacks.toggle
    .option("conceallevel", { off = 0, on = vim.o.conceallevel > 0 and vim.o.conceallevel or 2, name = "Conceal" })
    :map("<leader>uc")
  Snacks.toggle.option("background", { off = "light", on = "dark", name = "Dark background" }):map("<leader>ub")
  Snacks.toggle.treesitter():map("<leader>uT")
  Snacks.toggle.inlay_hints():map("<leader>uh")
  Snacks.toggle.indent():map("<leader>ug")
  Snacks.toggle.dim():map("<leader>uD")
  Snacks.toggle.zen():map("<leader>uz")
  Snacks.toggle.zoom():map("<leader>uZ")
  Snacks.toggle.scroll():map("<leader>uS")
  Snacks.toggle({
    name = "Format on save (global)",
    get = function()
      return vim.g.lumen_autoformat ~= false
    end,
    set = function(state)
      vim.g.lumen_autoformat = state
      vim.b.lumen_autoformat = nil
    end,
  }):map("<leader>uf")
  Snacks.toggle({
    name = "Format on save (buffer)",
    get = function()
      local b = vim.b.lumen_autoformat
      if b == nil then
        return vim.g.lumen_autoformat ~= false
      end
      return b
    end,
    set = function(state)
      vim.b.lumen_autoformat = state
    end,
  }):map("<leader>uF")
end
map("n", "<leader>uC", function()
  if _G.Snacks then
    return Snacks.picker.colorschemes()
  end
  vim.ui.select(vim.fn.getcompletion("", "color"), { prompt = "Colorscheme" }, function(name)
    if name then
      vim.cmd.colorscheme(name)
    end
  end)
end, { desc = "Colorschemes" })
map("n", "<leader>ui", vim.show_pos, { desc = "Inspect position" })
map("n", "<leader>uI", function()
  vim.treesitter.inspect_tree()
  vim.api.nvim_input("I")
end, { desc = "Inspect tree" })

-- ── terminal ─────────────────────────────────────────────────
---@param cwd? string
local function terminal(cwd)
  if _G.Snacks then
    return Snacks.terminal(nil, { cwd = cwd })
  end
  vim.cmd("botright new")
  vim.fn.jobstart(vim.o.shell, { term = true, cwd = cwd })
  vim.cmd.startinsert()
end
map({ "n", "t" }, "<C-/>", function()
  terminal(Lumen.root())
end, { desc = "Terminal (root)" })
map({ "n", "t" }, "<C-_>", function()
  terminal(Lumen.root())
end, { desc = "which_key_ignore" })
map("n", "<leader>ft", function()
  terminal(Lumen.root())
end, { desc = "Terminal (root)" })
map("n", "<leader>fT", function()
  terminal()
end, { desc = "Terminal (cwd)" })

-- ── quit / misc ──────────────────────────────────────────────
map("n", "<leader>qq", "<cmd>qa<cr>", { desc = "Quit all" })
map("n", "<leader>l", "<cmd>Lazy<cr>", { desc = "Lazy (plugins)" })
map("n", "<leader>L", "<cmd>Lumen<cr>", { desc = "Lumen menu" })
map("n", "<leader>K", "<cmd>norm! K<cr>", { desc = "Keywordprg" })
if vim.fn.exists(":restart") == 2 then
  map("n", "<leader>qr", "<cmd>restart<cr>", { desc = "Restart Neovim" })
end

-- tabs
map("n", "<leader><tab><tab>", "<cmd>tabnew<cr>", { desc = "New tab" })
map("n", "<leader><tab>d", "<cmd>tabclose<cr>", { desc = "Close tab" })
map("n", "<leader><tab>]", "<cmd>tabnext<cr>", { desc = "Next tab" })
map("n", "<leader><tab>[", "<cmd>tabprevious<cr>", { desc = "Prev tab" })
map("n", "<leader><tab>o", "<cmd>tabonly<cr>", { desc = "Close other tabs" })

-- ── native multicursor (Neovim 0.13+: Q toggles a cursor) ────
if vim.api.nvim_mcursor then
  local ns = vim.api.nvim_create_namespace("nvim.multicursor")
  map({ "n", "x" }, "<leader>mw", function()
    local word
    if vim.fn.mode():find("[vV]") then
      local lines = vim.fn.getregion(vim.fn.getpos("v"), vim.fn.getpos("."))
      word = "\\C\\V" .. vim.fn.escape(table.concat(lines, "\n"), "\\")
      vim.api.nvim_feedkeys(vim.keycode("<esc>"), "nx", false)
    else
      word = "\\C\\<" .. vim.fn.escape(vim.fn.expand("<cword>"), "\\") .. "\\>"
    end
    local cur = vim.api.nvim_win_get_cursor(0)
    local n = 0
    for _, m in ipairs(vim.fn.matchbufline("%", word, 1, "$")) do
      if not (m.lnum == cur[1] and m.byteidx <= cur[2] and cur[2] < m.byteidx + #m.text) then
        vim.api.nvim_mcursor(0, { m.lnum, m.byteidx })
        n = n + 1
      end
    end
    Lumen.notify(("%d extra cursors — edit away, <C-l> to clear"):format(n))
  end, { desc = "Cursors on every match" })
  map("n", "<leader>mc", function()
    vim.api.nvim_buf_clear_namespace(0, ns, 0, -1)
  end, { desc = "Clear cursors" })
  map("n", "<leader>mr", "gQ", { desc = "Restore cursors", remap = true })
  map("n", "<leader>mf", "q=", { desc = "Toggle follow mode", remap = true })
  map("n", "<leader>ma", "Q", { desc = "Toggle cursor here", remap = true })
end
