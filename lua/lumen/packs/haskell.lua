---@type lumen.Pack
return {
  desc = "Haskell (haskell-language-server, ormolu)",
  ft = { "haskell", "lhaskell", "cabal" },
  parsers = { "haskell" },
  -- hls must match your GHC; ghcup's copy is preferred when on $PATH
  servers = { hls = { filetypes = { "haskell", "lhaskell", "cabal" } } },
  tools = { "ormolu" },
  formatters = { haskell = { "ormolu" } },
}
