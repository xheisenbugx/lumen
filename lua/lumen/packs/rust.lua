---@type lumen.Pack
return {
  desc = "Rust (rust-analyzer, crates.nvim)",
  ft = { "rust" },
  parsers = { "rust", "ron", "toml" },
  servers = {
    rust_analyzer = {
      settings = {
        ["rust-analyzer"] = {
          cargo = { allFeatures = true, buildScripts = { enable = true } },
          check = { command = "clippy" },
          procMacro = { enable = true },
          inlayHints = { closureReturnTypeHints = { enable = "with_block" } },
        },
      },
    },
  },
  plugins = {
    {
      "saecki/crates.nvim",
      event = { "BufRead Cargo.toml" },
      opts = {
        completion = { crates = { enabled = true } },
        lsp = { enabled = true, actions = true, completion = true, hover = true },
      },
    },
  },
}
