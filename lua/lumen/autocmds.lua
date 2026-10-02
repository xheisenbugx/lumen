local function augroup(name)
  return vim.api.nvim_create_augroup("lumen_" .. name, { clear = true })
end
local autocmd = vim.api.nvim_create_autocmd

-- reload files changed outside of nvim
autocmd({ "FocusGained", "TermClose", "TermLeave" }, {
  group = augroup("checktime"),
  callback = function()
    if vim.o.buftype ~= "nofile" then
      vim.cmd.checktime()
    end
  end,
})

-- briefly glow the yanked text
autocmd("TextYankPost", {
  group = augroup("yank"),
  callback = function()
    local hl = vim.hl or vim.highlight
    -- 0.13 renamed on_yank → hl_op (on_yank now warns as deprecated)
    local fn = hl.hl_op or hl.on_yank
    fn({ higroup = "IncSearch", timeout = 180 })
  end,
})

-- keep splits balanced when the terminal resizes
autocmd("VimResized", {
  group = augroup("resize"),
  callback = function()
    local tab = vim.fn.tabpagenr()
    vim.cmd("tabdo wincmd =")
    vim.cmd.tabnext(tab)
  end,
})

-- safety net: if anything swallowed filetype detection while a file was being opened
-- (a plugin firing FileType mid-BufReadPost makes `:setf` a no-op), detect it again
autocmd("BufReadPost", {
  group = augroup("ensure_filetype"),
  callback = function(ev)
    vim.schedule(function()
      if vim.api.nvim_buf_is_valid(ev.buf) and vim.bo[ev.buf].buftype == "" and vim.bo[ev.buf].filetype == "" then
        vim.api.nvim_buf_call(ev.buf, function()
          vim.cmd("filetype detect")
        end)
      end
    end)
  end,
})

-- reopen files where you left off
autocmd("BufReadPost", {
  group = augroup("last_loc"),
  callback = function(ev)
    local exclude = { gitcommit = true, gitrebase = true }
    if exclude[vim.bo[ev.buf].filetype] or vim.b[ev.buf].lumen_last_loc then
      return
    end
    vim.b[ev.buf].lumen_last_loc = true
    local mark = vim.api.nvim_buf_get_mark(ev.buf, '"')
    if mark[1] > 0 and mark[1] <= vim.api.nvim_buf_line_count(ev.buf) then
      pcall(vim.api.nvim_win_set_cursor, 0, mark)
    end
  end,
})

-- `q` closes utility windows
autocmd("FileType", {
  group = augroup("close_with_q"),
  pattern = {
    "checkhealth",
    "dbout",
    "gitsigns-blame",
    "grug-far",
    "help",
    "lspinfo",
    "man",
    "neotest-output",
    "neotest-summary",
    "notify",
    "qf",
    "query",
    "startuptime",
    "nvim-pack",
  },
  callback = function(ev)
    vim.bo[ev.buf].buflisted = false
    vim.schedule(function()
      vim.keymap.set("n", "q", function()
        vim.cmd.close()
        pcall(vim.api.nvim_buf_delete, ev.buf, { force = true })
      end, { buffer = ev.buf, silent = true, desc = "Quit buffer" })
    end)
  end,
})

-- prose-friendly settings
autocmd("FileType", {
  group = augroup("prose"),
  pattern = { "text", "plaintex", "typst", "gitcommit", "markdown" },
  callback = function()
    vim.opt_local.wrap = true
    vim.opt_local.spell = true
  end,
})

autocmd("FileType", {
  group = augroup("json_conceal"),
  pattern = { "json", "jsonc", "json5" },
  callback = function()
    vim.opt_local.conceallevel = 0
  end,
})

-- create missing parent directories on save
autocmd("BufWritePre", {
  group = augroup("auto_create_dir"),
  callback = function(ev)
    if ev.match:match("^%w%w+:[\\/][\\/]") then
      return
    end
    local file = vim.uv.fs_realpath(ev.match) or ev.match
    vim.fn.mkdir(vim.fn.fnamemodify(file, ":p:h"), "p")
  end,
})

-- only the focused window gets a cursorline: makes the active split obvious
autocmd({ "WinEnter", "BufWinEnter", "InsertLeave" }, {
  group = augroup("cursorline"),
  callback = function()
    if vim.w.lumen_cul ~= nil then
      vim.wo.cursorline = vim.w.lumen_cul
      vim.w.lumen_cul = nil
    end
  end,
})
autocmd({ "WinLeave", "InsertEnter" }, {
  group = augroup("cursorline_off"),
  callback = function(ev)
    if ev.event == "InsertEnter" or vim.bo.filetype == "snacks_picker_list" then
      return
    end
    if vim.wo.cursorline then
      vim.w.lumen_cul = true
      vim.wo.cursorline = false
    end
  end,
})

-- terminal buffers: clean look
autocmd("TermOpen", {
  group = augroup("term"),
  callback = function()
    vim.opt_local.number = false
    vim.opt_local.relativenumber = false
    vim.opt_local.signcolumn = "no"
  end,
})

-- language pack suggestions
if require("lumen.config").suggest_packs then
  autocmd("FileType", {
    group = augroup("pack_suggest"),
    callback = function(ev)
      vim.schedule(function()
        require("lumen.packs").suggest(ev.match)
      end)
    end,
  })
end
