---@type lumen.Pack
return {
  desc = "JSON with SchemaStore schemas",
  ft = { "json", "jsonc", "json5" },
  parsers = { "json", "json5" },
  servers = {
    jsonls = {
      before_init = function(_, cfg)
        cfg.settings = cfg.settings or {}
        cfg.settings.json = cfg.settings.json or {}
        cfg.settings.json.schemas =
          vim.list_extend(cfg.settings.json.schemas or {}, require("schemastore").json.schemas())
      end,
      settings = { json = { format = { enable = true }, validate = { enable = true } } },
    },
  },
  plugins = { { "b0o/SchemaStore.nvim", lazy = true, version = false } },
}
