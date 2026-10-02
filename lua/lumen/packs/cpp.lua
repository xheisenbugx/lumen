---@type lumen.Pack
return {
  desc = "C / C++ (clangd)",
  ft = { "c", "cpp", "objc", "objcpp", "cuda" },
  parsers = { "c", "cpp" },
  servers = {
    clangd = {
      cmd = { "clangd", "--background-index", "--clang-tidy", "--header-insertion=iwyu", "--completion-style=detailed" },
      keys = { { "<leader>ch", "<cmd>LspClangdSwitchSourceHeader<cr>", desc = "Switch source/header" } },
    },
  },
}
