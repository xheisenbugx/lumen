---@type lumen.Pack
return {
  desc = "YAML with SchemaStore schemas",
  ft = { "yaml" },
  parsers = { "yaml" },
  servers = {
    yamlls = {
      before_init = function(_, cfg)
        cfg.settings = cfg.settings or {}
        cfg.settings.yaml = cfg.settings.yaml or {}
        cfg.settings.yaml.schemas =
          vim.tbl_deep_extend("force", cfg.settings.yaml.schemas or {}, require("schemastore").yaml.schemas())
      end,
      settings = {
        redhat = { telemetry = { enabled = false } },
        yaml = {
          keyOrdering = false,
          format = { enable = true },
          validate = true,
          schemaStore = { enable = false, url = "" },
        },
      },
    },
  },
  plugins = { { "b0o/SchemaStore.nvim", lazy = true, version = false } },
}
