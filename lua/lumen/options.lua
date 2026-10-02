local config = require("lumen.config")

vim.g.mapleader = config.leader
vim.g.maplocalleader = config.localleader
vim.g.lumen_autoformat = config.format_on_save

local o = vim.opt

-- ── ui ────────────────────────────────────────────────────────
o.termguicolors = true
o.number = true
o.relativenumber = true
o.cursorline = true
o.cursorlineopt = "both"
o.signcolumn = "yes"
o.laststatus = 3
o.showmode = false
o.ruler = false
o.showcmd = false
o.pumheight = 12
o.pumblend = 0
o.winminwidth = 5
o.list = true
o.listchars = { tab = "» ", trail = "·", nbsp = "␣" }
o.fillchars = {
  foldopen = "",
  foldclose = "",
  fold = " ",
  foldsep = " ",
  diff = "╱",
  eob = " ",
}
o.conceallevel = 2
o.shortmess:append({ W = true, I = true, c = true, C = true, s = true })
o.splitbelow = true
o.splitright = true
o.splitkeep = "screen"
o.scrolloff = 6
o.sidescrolloff = 8
o.smoothscroll = true
o.wrap = false
o.linebreak = true
o.breakindent = true
if vim.fn.exists("+winborder") == 1 then
  o.winborder = "rounded"
end

-- ── editing ──────────────────────────────────────────────────
o.expandtab = true
o.shiftwidth = 2
o.tabstop = 2
o.shiftround = true
o.smartindent = true
o.virtualedit = "block"
o.formatoptions = "jcroqlnt"
o.ignorecase = true
o.smartcase = true
o.inccommand = "split"
o.completeopt = "menu,menuone,noselect"
o.wildmode = "longest:full,full"
o.jumpoptions = "view"
o.confirm = true
o.undofile = true
o.undolevels = 10000
o.updatetime = 200
o.timeoutlen = vim.g.vscode and 1000 or 300
o.mouse = "a"
o.spelllang = { "en" }
o.grepprg = "rg --vimgrep"
o.grepformat = "%f:%l:%c:%m"
o.sessionoptions = { "buffers", "curdir", "tabpages", "winsize", "help", "globals", "skiprtp", "folds" }

-- the system clipboard is slow to probe; set it after startup
vim.schedule(function()
  o.clipboard = vim.env.SSH_TTY and "" or "unnamedplus"
end)

-- ── folds (treesitter-powered, all open by default) ─────────
o.foldlevel = 99
o.foldmethod = "expr"
o.foldexpr = "v:lua.vim.treesitter.foldexpr()"

-- ── Neovim's new UI (0.12+) ──────────────────────────────────
if config.ui2 then
  local ok = pcall(function()
    require("vim._core.ui2").enable({})
  end) or pcall(function()
    require("vim._extui").enable({})
  end)
  if ok then
    o.cmdheight = 0
  end
end

vim.g.markdown_recommended_style = 0
