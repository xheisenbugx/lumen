local config = require("lumen.config")

local logo = {
  "██╗     ██╗   ██╗███╗   ███╗███████╗███╗   ██╗",
  "██║     ██║   ██║████╗ ████║██╔════╝████╗  ██║",
  "██║     ██║   ██║██╔████╔██║█████╗  ██╔██╗ ██║",
  "██║     ██║   ██║██║╚██╔╝██║██╔══╝  ██║╚██╗██║",
  "███████╗╚██████╔╝██║ ╚═╝ ██║███████╗██║ ╚████║",
  "╚══════╝ ╚═════╝ ╚═╝     ╚═╝╚══════╝╚═╝  ╚═══╝",
}

local function dashboard_sections()
  local sections = { { padding = 1 } }
  for i, line in ipairs(logo) do
    sections[#sections + 1] = { text = { { line, hl = "LumenLogo" .. i } }, align = "center" }
  end
  sections[#sections + 1] = {
    text = { { "light, fast & beautiful", hl = "LumenTagline" } },
    align = "center",
    padding = 2,
  }
  vim.list_extend(sections, {
    { section = "keys", gap = vim.o.lines < 44 and 0 or 1, padding = 2 },
    { icon = " ", title = "Recent", section = "recent_files", cwd = true, limit = 5, indent = 2, padding = 2 },
    { section = "startup" },
  })
  return sections
end

return {
  -- icons, also served to plugins expecting nvim-web-devicons
  {
    "nvim-mini/mini.icons",
    lazy = true,
    opts = {},
    init = function()
      package.preload["nvim-web-devicons"] = function()
        require("mini.icons").mock_nvim_web_devicons()
        return package.loaded["nvim-web-devicons"]
      end
    end,
  },

  {
    "folke/snacks.nvim",
    priority = 1000,
    lazy = false,
    ---@type snacks.Config
    opts = {
      bigfile = { enabled = true },
      quickfile = { enabled = true },
      input = { enabled = true },
      notifier = { enabled = true, timeout = 2500, style = "compact", top_down = false },
      scope = { enabled = true },
      words = { enabled = true, debounce = 120 },
      scroll = { enabled = config.smooth_scroll, animate = { duration = { step = 10, total = 160 } } },
      statuscolumn = { enabled = true, folds = { open = false, git_hl = true } },
      indent = {
        enabled = true,
        indent = { char = "▏" },
        scope = { char = "▏", hl = "SnacksIndentScope" },
        animate = { enabled = false },
        filter = function(buf)
          return vim.bo[buf].buftype == "" and vim.g.snacks_indent ~= false and vim.b[buf].snacks_indent ~= false
        end,
      },
      explorer = { enabled = true, replace_netrw = true },
      picker = {
        enabled = true,
        ui_select = true,
        prompt = " ",
        layout = { cycle = true },
        matcher = { frecency = true },
        formatters = { file = { filename_first = true } },
        win = {
          input = {
            keys = {
              ["<a-c>"] = { "toggle_cwd", mode = { "n", "i" } },
            },
          },
        },
        actions = {
          toggle_cwd = function(p)
            local root = Lumen.root()
            local cwd = vim.fs.normalize(vim.uv.cwd() or ".")
            local current = p:cwd()
            p:set_cwd(current == root and cwd or root)
            p:find()
          end,
        },
        sources = {
          explorer = { layout = { layout = { position = "left", width = 34 } } },
        },
      },
      dashboard = {
        enabled = true,
        width = 56,
        preset = {
          keys = {
            { icon = " ", key = "f", desc = "Find file", action = ":lua Snacks.dashboard.pick('files')" },
            { icon = " ", key = "g", desc = "Find text", action = ":lua Snacks.dashboard.pick('live_grep')" },
            { icon = " ", key = "r", desc = "Recent files", action = ":lua Snacks.dashboard.pick('oldfiles')" },
            { icon = " ", key = "p", desc = "Projects", action = ":lua Snacks.picker.projects()" },
            { icon = " ", key = "n", desc = "New file", action = ":ene | startinsert" },
            { icon = " ", key = "s", desc = "Restore session", section = "session" },
            { icon = "󰗊 ", key = "P", desc = "Language packs", action = ":Lumen packs" },
            { icon = " ", key = "c", desc = "Config", action = ":Lumen config" },
            { icon = "󰒲 ", key = "l", desc = "Plugins", action = ":Lazy" },
            { icon = " ", key = "q", desc = "Quit", action = ":qa" },
          },
        },
        sections = dashboard_sections(),
      },
      styles = {
        notification = { wo = { wrap = true } },
        input = { relative = "cursor", row = -3, col = 0, width = 50 },
        lazygit = { width = 0.92, height = 0.9 },
        terminal = { wo = { winbar = "" } },
      },
    },
    -- stylua: ignore
    keys = {
      -- top level
      { "<leader><space>", function() Snacks.picker.smart({ cwd = Lumen.root() }) end, desc = "Find files (smart)" },
      { "<leader>/", function() Snacks.picker.grep({ cwd = Lumen.root() }) end, desc = "Grep (root)" },
      { "<leader>,", function() Snacks.picker.buffers() end, desc = "Buffers" },
      { "<leader>:", function() Snacks.picker.command_history() end, desc = "Command history" },
      { "<leader>e", function() Snacks.explorer({ cwd = Lumen.root() }) end, desc = "Explorer (root)" },
      { "<leader>E", function() Snacks.explorer() end, desc = "Explorer (cwd)" },
      { "<leader>n", function() Snacks.notifier.show_history() end, desc = "Notification history" },
      { "<leader>.", function() Snacks.scratch() end, desc = "Scratch buffer" },
      { "<leader>S", function() Snacks.scratch.select() end, desc = "Select scratch" },
      -- find
      { "<leader>ff", function() Snacks.picker.files({ cwd = Lumen.root() }) end, desc = "Files (root)" },
      { "<leader>fF", function() Snacks.picker.files() end, desc = "Files (cwd)" },
      { "<leader>fg", function() Snacks.picker.git_files() end, desc = "Git files" },
      { "<leader>fr", function() Snacks.picker.recent() end, desc = "Recent" },
      { "<leader>fR", function() Snacks.picker.recent({ filter = { cwd = true } }) end, desc = "Recent (cwd)" },
      { "<leader>fb", function() Snacks.picker.buffers() end, desc = "Buffers" },
      { "<leader>fc", function() Snacks.picker.files({ cwd = vim.fn.stdpath("config") }) end, desc = "Config files" },
      { "<leader>fp", function() Snacks.picker.projects() end, desc = "Projects" },
      -- search
      { "<leader>sg", function() Snacks.picker.grep({ cwd = Lumen.root() }) end, desc = "Grep (root)" },
      { "<leader>sG", function() Snacks.picker.grep() end, desc = "Grep (cwd)" },
      { "<leader>sw", function() Snacks.picker.grep_word({ cwd = Lumen.root() }) end, desc = "Word / selection", mode = { "n", "x" } },
      { "<leader>sb", function() Snacks.picker.lines() end, desc = "Buffer lines" },
      { "<leader>sB", function() Snacks.picker.grep_buffers() end, desc = "Grep open buffers" },
      { "<leader>s\"", function() Snacks.picker.registers() end, desc = "Registers" },
      { "<leader>s/", function() Snacks.picker.search_history() end, desc = "Search history" },
      { "<leader>sa", function() Snacks.picker.autocmds() end, desc = "Autocmds" },
      { "<leader>sc", function() Snacks.picker.command_history() end, desc = "Command history" },
      { "<leader>sC", function() Snacks.picker.commands() end, desc = "Commands" },
      { "<leader>sd", function() Snacks.picker.diagnostics() end, desc = "Diagnostics" },
      { "<leader>sD", function() Snacks.picker.diagnostics_buffer() end, desc = "Buffer diagnostics" },
      { "<leader>sh", function() Snacks.picker.help() end, desc = "Help pages" },
      { "<leader>sH", function() Snacks.picker.highlights() end, desc = "Highlights" },
      { "<leader>si", function() Snacks.picker.icons() end, desc = "Icons" },
      { "<leader>sj", function() Snacks.picker.jumps() end, desc = "Jumps" },
      { "<leader>sk", function() Snacks.picker.keymaps() end, desc = "Keymaps" },
      { "<leader>sl", function() Snacks.picker.loclist() end, desc = "Location list" },
      { "<leader>sm", function() Snacks.picker.marks() end, desc = "Marks" },
      { "<leader>sM", function() Snacks.picker.man() end, desc = "Man pages" },
      { "<leader>sp", function() Snacks.picker.lazy() end, desc = "Plugin specs" },
      { "<leader>sq", function() Snacks.picker.qflist() end, desc = "Quickfix list" },
      { "<leader>sR", function() Snacks.picker.resume() end, desc = "Resume last picker" },
      { "<leader>su", function() Snacks.picker.undo() end, desc = "Undo history" },
      -- git
      { "<leader>gg", function() Snacks.lazygit({ cwd = Lumen.root.git() }) end, desc = "Lazygit" },
      { "<leader>gs", function() Snacks.picker.git_status() end, desc = "Status" },
      { "<leader>gS", function() Snacks.picker.git_stash() end, desc = "Stash" },
      { "<leader>gl", function() Snacks.picker.git_log({ cwd = Lumen.root.git() }) end, desc = "Log" },
      { "<leader>gf", function() Snacks.picker.git_log_file() end, desc = "File history" },
      { "<leader>gL", function() Snacks.picker.git_log_line() end, desc = "Line history" },
      { "<leader>gd", function() Snacks.picker.git_diff() end, desc = "Diff (hunks)" },
      { "<leader>gb", function() Snacks.picker.git_branches() end, desc = "Branches" },
      { "<leader>gB", function() Snacks.gitbrowse() end, desc = "Open in browser", mode = { "n", "x" } },
      -- lsp-ish
      { "<leader>ss", function() Snacks.picker.lsp_symbols() end, desc = "Symbols" },
      { "<leader>sS", function() Snacks.picker.lsp_workspace_symbols() end, desc = "Workspace symbols" },
      { "<leader>cR", function() Snacks.rename.rename_file() end, desc = "Rename file" },
      { "]]", function() Snacks.words.jump(vim.v.count1) end, desc = "Next reference", mode = { "n", "t" } },
      { "[[", function() Snacks.words.jump(-vim.v.count1) end, desc = "Prev reference", mode = { "n", "t" } },
      { "<leader>un", function() Snacks.notifier.hide() end, desc = "Dismiss notifications" },
    },
  },

  {
    "folke/which-key.nvim",
    event = "VeryLazy",
    opts_extend = { "spec" },
    opts = {
      preset = "helix",
      delay = 250,
      win = { border = "rounded", padding = { 1, 2 }, title = true, title_pos = "center" },
      icons = { rules = false, separator = "" },
      spec = {
        {
          mode = { "n", "x" },
          { "<leader><tab>", group = "tabs", icon = "󰓩 " },
          {
            "<leader>b",
            group = "buffer",
            icon = "󰈔 ",
            expand = function()
              return require("which-key.extras").expand.buf()
            end,
          },
          { "<leader>c", group = "code", icon = " " },
          { "<leader>d", group = "debug", icon = " " },
          { "<leader>f", group = "find", icon = " " },
          { "<leader>g", group = "git", icon = " " },
          { "<leader>gh", group = "hunks", icon = " " },
          { "<leader>m", group = "multicursor", icon = "󰭊 " },
          { "<leader>q", group = "quit / session", icon = "󰗼 " },
          { "<leader>r", group = "run / tasks", icon = " " },
          { "<leader>s", group = "search", icon = " " },
          { "<leader>u", group = "toggle", icon = " " },
          {
            "<leader>w",
            group = "windows",
            proxy = "<c-w>",
            expand = function()
              return require("which-key.extras").expand.win()
            end,
          },
          { "<leader>x", group = "diagnostics", icon = "󱖫 " },
          { "[", group = "prev" },
          { "]", group = "next" },
          { "g", group = "goto" },
          { "gs", group = "surround" },
          { "z", group = "fold" },
        },
        {
          cond = vim.api.nvim_mcursor ~= nil,
          { "Q", desc = "Toggle multicursor", mode = { "n", "x" } },
          { "gQ", desc = "Restore multicursors" },
          { "q=", desc = "Multicursor follow mode" },
          { "]C", desc = "Next cursor" },
          { "[C", desc = "Prev cursor" },
        },
      },
    },
    keys = {
      {
        "<leader>?",
        function()
          require("which-key").show({ global = false })
        end,
        desc = "Buffer keymaps",
      },
    },
  },
}
