return {
  -- jump anywhere in 2–3 keystrokes
  {
    "folke/flash.nvim",
    event = "VeryLazy",
    opts = { modes = { char = { jump_labels = true } } },
    -- stylua: ignore
    keys = {
      { "s", mode = { "n", "x", "o" }, function() require("flash").jump() end, desc = "Flash" },
      { "S", mode = { "n", "o", "x" }, function() require("flash").treesitter() end, desc = "Flash treesitter" },
      { "r", mode = "o", function() require("flash").remote() end, desc = "Remote flash" },
      { "R", mode = { "o", "x" }, function() require("flash").treesitter_search() end, desc = "Treesitter search" },
      { "<c-s>", mode = { "c" }, function() require("flash").toggle() end, desc = "Toggle flash search" },
    },
  },

  -- git signs, hunks & blame
  {
    "lewis6991/gitsigns.nvim",
    event = "LazyFile",
    opts = {
      signs = {
        add = { text = "▎" },
        change = { text = "▎" },
        delete = { text = "" },
        topdelete = { text = "" },
        changedelete = { text = "▎" },
        untracked = { text = "┆" },
      },
      signs_staged = {
        add = { text = "▎" },
        change = { text = "▎" },
        delete = { text = "" },
        topdelete = { text = "" },
        changedelete = { text = "▎" },
      },
      preview_config = { border = "rounded" },
      on_attach = function(buf)
        local gs = package.loaded.gitsigns
        local function map(mode, l, r, desc)
          vim.keymap.set(mode, l, r, { buffer = buf, desc = desc, silent = true })
        end
        -- stylua: ignore start
        map("n", "]h", function() if vim.wo.diff then vim.cmd.normal({ "]c", bang = true }) else gs.nav_hunk("next") end end, "Next hunk")
        map("n", "[h", function() if vim.wo.diff then vim.cmd.normal({ "[c", bang = true }) else gs.nav_hunk("prev") end end, "Prev hunk")
        map("n", "]H", function() gs.nav_hunk("last") end, "Last hunk")
        map("n", "[H", function() gs.nav_hunk("first") end, "First hunk")
        map({ "n", "x" }, "<leader>ghs", ":Gitsigns stage_hunk<CR>", "Stage hunk")
        map({ "n", "x" }, "<leader>ghr", ":Gitsigns reset_hunk<CR>", "Reset hunk")
        map("n", "<leader>ghS", gs.stage_buffer, "Stage buffer")
        map("n", "<leader>ghR", gs.reset_buffer, "Reset buffer")
        map("n", "<leader>ghp", gs.preview_hunk_inline, "Preview hunk inline")
        map("n", "<leader>ghP", gs.preview_hunk, "Preview hunk")
        map("n", "<leader>ghb", function() gs.blame_line({ full = true }) end, "Blame line")
        map("n", "<leader>ghB", function() gs.blame() end, "Blame buffer")
        map("n", "<leader>ghd", gs.diffthis, "Diff this")
        map({ "o", "x" }, "ih", ":<C-U>Gitsigns select_hunk<CR>", "Hunk")
        -- stylua: ignore end
        if not _G.Snacks then
          return
        end
        Snacks.toggle({
          name = "Git signs",
          get = function()
            return require("gitsigns.config").config.signcolumn
          end,
          set = function(state)
            gs.toggle_signs(state)
          end,
        }):map("<leader>uG")
        Snacks.toggle({
          name = "Inline blame",
          get = function()
            return require("gitsigns.config").config.current_line_blame
          end,
          set = function(state)
            gs.toggle_current_line_blame(state)
          end,
        }):map("<leader>uB")
      end,
    },
  },

  -- pretty diagnostics, references, quickfix
  {
    "folke/trouble.nvim",
    cmd = "Trouble",
    opts = { focus = true, modes = { lsp = { win = { position = "right" } } } },
    keys = {
      { "<leader>xx", "<cmd>Trouble diagnostics toggle<cr>", desc = "Diagnostics" },
      { "<leader>xX", "<cmd>Trouble diagnostics toggle filter.buf=0<cr>", desc = "Buffer diagnostics" },
      { "<leader>cs", "<cmd>Trouble symbols toggle<cr>", desc = "Symbols outline" },
      { "<leader>cS", "<cmd>Trouble lsp toggle<cr>", desc = "LSP references / defs" },
      { "<leader>xL", "<cmd>Trouble loclist toggle<cr>", desc = "Location list" },
      { "<leader>xQ", "<cmd>Trouble qflist toggle<cr>", desc = "Quickfix list" },
    },
  },

  -- TODO / FIXME / HACK highlights & search
  {
    "folke/todo-comments.nvim",
    cmd = { "TodoTrouble" },
    event = "LazyFile",
    opts = { signs = false },
    -- stylua: ignore
    keys = {
      { "]t", function() require("todo-comments").jump_next() end, desc = "Next todo" },
      { "[t", function() require("todo-comments").jump_prev() end, desc = "Prev todo" },
      { "<leader>st", function() Snacks.picker.todo_comments() end, desc = "Todos" },
      { "<leader>xt", "<cmd>Trouble todo toggle<cr>", desc = "Todos (Trouble)" },
    },
  },

  -- project-wide search & replace
  {
    "MagicDuck/grug-far.nvim",
    cmd = { "GrugFar", "GrugFarWithin" },
    opts = { headerMaxWidth = 80 },
    keys = {
      {
        "<leader>sr",
        function()
          local ext = vim.bo.buftype == "" and vim.fn.expand("%:e")
          require("grug-far").open({
            transient = true,
            prefills = { filesFilter = ext and ext ~= "" and "*." .. ext or nil },
          })
        end,
        mode = { "n", "x" },
        desc = "Search & replace",
      },
    },
  },

  -- edit the filesystem like a buffer
  {
    "stevearc/oil.nvim",
    cmd = "Oil",
    opts = {
      default_file_explorer = false,
      view_options = { show_hidden = true },
      float = { padding = 4, max_width = 100, border = "rounded" },
      keymaps = { ["q"] = "actions.close" },
    },
    keys = { { "-", "<cmd>Oil --float<cr>", desc = "Open parent dir (oil)" } },
  },

  -- sessions
  {
    "folke/persistence.nvim",
    event = "BufReadPre",
    opts = {},
    -- stylua: ignore
    keys = {
      { "<leader>qs", function() require("persistence").load() end, desc = "Restore session" },
      { "<leader>qS", function() require("persistence").select() end, desc = "Select session" },
      { "<leader>ql", function() require("persistence").load({ last = true }) end, desc = "Last session" },
      { "<leader>qd", function() require("persistence").stop() end, desc = "Don't save session" },
    },
  },
}
