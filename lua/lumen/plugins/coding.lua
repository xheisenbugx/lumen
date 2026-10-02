return {
  -- completion: fast (Rust fuzzy matcher), with signature help & ghost text
  {
    "saghen/blink.cmp",
    version = "1.*",
    event = { "InsertEnter", "CmdlineEnter" },
    dependencies = { "rafamadriz/friendly-snippets" },
    opts_extend = { "sources.default" },
    opts = {
      keymap = {
        preset = "enter",
        ["<C-y>"] = { "select_and_accept" },
        ["<Tab>"] = { "snippet_forward", "fallback" },
        ["<S-Tab>"] = { "snippet_backward", "fallback" },
      },
      appearance = { nerd_font_variant = "mono" },
      completion = {
        accept = { auto_brackets = { enabled = true } },
        list = { selection = { preselect = true, auto_insert = false } },
        menu = {
          border = "rounded",
          scrollbar = false,
          draw = {
            treesitter = { "lsp" },
            padding = { 1, 1 },
            columns = { { "kind_icon" }, { "label", "label_description", gap = 1 }, { "kind" } },
            components = {
              kind_icon = {
                text = function(ctx)
                  local ok, icons = pcall(require, "mini.icons")
                  if ok then
                    local icon = icons.get("lsp", ctx.kind)
                    return icon .. " "
                  end
                  return ctx.kind_icon .. ctx.icon_gap
                end,
                highlight = function(ctx)
                  local ok, icons = pcall(require, "mini.icons")
                  if ok then
                    local _, hl = icons.get("lsp", ctx.kind)
                    return hl
                  end
                  return ctx.kind_hl
                end,
              },
              kind = { highlight = "BlinkCmpSource" },
            },
          },
        },
        documentation = { auto_show = true, auto_show_delay_ms = 180, window = { border = "rounded" } },
        ghost_text = { enabled = true },
      },
      signature = { enabled = true, window = { border = "rounded", show_documentation = false } },
      sources = { default = { "lsp", "path", "snippets", "buffer" } },
      cmdline = {
        enabled = true,
        keymap = { preset = "cmdline", ["<Right>"] = false, ["<Left>"] = false },
        completion = {
          list = { selection = { preselect = false } },
          menu = {
            auto_show = function()
              return vim.fn.getcmdtype() == ":"
            end,
          },
          ghost_text = { enabled = true },
        },
      },
      fuzzy = { implementation = "prefer_rust_with_warning" },
    },
  },

  -- better text objects: a/i + f(unction) c(lass) a(rg) q(uote) b(racket) t(ag) …
  {
    "nvim-mini/mini.ai",
    event = "VeryLazy",
    opts = function()
      local ai = require("mini.ai")
      return {
        n_lines = 500,
        custom_textobjects = {
          o = ai.gen_spec.treesitter({
            a = { "@block.outer", "@conditional.outer", "@loop.outer" },
            i = { "@block.inner", "@conditional.inner", "@loop.inner" },
          }),
          f = ai.gen_spec.treesitter({ a = "@function.outer", i = "@function.inner" }),
          c = ai.gen_spec.treesitter({ a = "@class.outer", i = "@class.inner" }),
          t = { "<([%p%w]-)%f[^<%w][^<>]->.-</%1>", "^<.->().*()</[^/]->$" },
          d = { "%f[%d]%d+" },
          e = {
            { "%u[%l%d]+%f[^%l%d]", "%f[%S][%l%d]+%f[^%l%d]", "%f[%P][%l%d]+%f[^%l%d]", "^[%l%d]+%f[^%l%d]" },
            "^().*()$",
          },
          g = function()
            local from = { line = 1, col = 1 }
            local to = { line = vim.fn.line("$"), col = math.max(vim.fn.getline("$"):len(), 1) }
            return { from = from, to = to }
          end,
          u = ai.gen_spec.function_call(),
          U = ai.gen_spec.function_call({ name_pattern = "[%w_]" }),
        },
      }
    end,
  },

  {
    "nvim-mini/mini.surround",
    keys = {
      { "gsa", desc = "Add surrounding", mode = { "n", "x" } },
      { "gsd", desc = "Delete surrounding" },
      { "gsf", desc = "Find right surrounding" },
      { "gsF", desc = "Find left surrounding" },
      { "gsh", desc = "Highlight surrounding" },
      { "gsr", desc = "Replace surrounding" },
    },
    opts = {
      mappings = {
        add = "gsa",
        delete = "gsd",
        find = "gsf",
        find_left = "gsF",
        highlight = "gsh",
        replace = "gsr",
        update_n_lines = "",
      },
    },
  },

  {
    "nvim-mini/mini.pairs",
    event = "InsertEnter",
    opts = {
      modes = { insert = true, command = false, terminal = false },
    },
    config = function(_, opts)
      require("mini.pairs").setup(opts)
      Snacks.toggle({
        name = "Auto pairs",
        get = function()
          return not vim.g.minipairs_disable
        end,
        set = function(state)
          vim.g.minipairs_disable = not state
        end,
      }):map("<leader>up")
    end,
  },

  -- inline color swatches for #rrggbb
  {
    "nvim-mini/mini.hipatterns",
    event = "LazyFile",
    opts = function()
      local hi = require("mini.hipatterns")
      return { highlighters = { hex_color = hi.gen_highlighter.hex_color() } }
    end,
  },

  -- correct comment strings in embedded languages (tsx, vue, …)
  { "folke/ts-comments.nvim", event = "VeryLazy", opts = {} },
}
