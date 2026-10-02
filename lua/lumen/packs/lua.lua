---@type lumen.Pack
return {
  desc = "Lua & Neovim plugin development",
  ft = { "lua" },
  parsers = { "lua", "luadoc", "luap" },
  servers = {
    lua_ls = {
      settings = {
        Lua = {
          workspace = { checkThirdParty = false },
          codeLens = { enable = true },
          completion = { callSnippet = "Replace" },
          doc = { privateName = { "^_" } },
          hint = {
            enable = true,
            setType = false,
            paramType = true,
            paramName = "Disable",
            semicolon = "Disable",
            arrayIndex = "Disable",
          },
        },
      },
    },
  },
  tools = { "stylua" },
  formatters = { lua = { "stylua" } },
  plugins = {
    {
      "folke/lazydev.nvim",
      ft = "lua",
      cmd = "LazyDev",
      opts = {
        library = {
          { path = "${3rd}/luv/library", words = { "vim%.uv" } },
          { path = "snacks.nvim", words = { "Snacks" } },
          { path = "lazy.nvim", words = { "LazySpec" } },
        },
      },
    },
    {
      "saghen/blink.cmp",
      opts = {
        sources = {
          per_filetype = { lua = { inherit_defaults = true, "lazydev" } },
          providers = {
            lazydev = { name = "LazyDev", module = "lazydev.integrations.blink", score_offset = 100 },
          },
        },
      },
    },
  },
}
