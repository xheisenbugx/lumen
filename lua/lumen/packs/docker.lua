---@type lumen.Pack
return {
  desc = "Dockerfile & compose",
  ft = { "dockerfile", "yaml.docker-compose" },
  parsers = { "dockerfile" },
  servers = { dockerls = {}, docker_compose_language_service = {} },
  tools = { "hadolint" },
  linters = { dockerfile = { "hadolint" } },
  -- Neovim calls compose files plain "yaml"; the compose server only attaches to yaml.docker-compose
  setup = function()
    vim.filetype.add({
      filename = {
        ["docker-compose.yml"] = "yaml.docker-compose",
        ["docker-compose.yaml"] = "yaml.docker-compose",
        ["compose.yml"] = "yaml.docker-compose",
        ["compose.yaml"] = "yaml.docker-compose",
      },
      pattern = {
        ["docker%-compose%..*%.ya?ml"] = "yaml.docker-compose",
        ["compose%..*%.ya?ml"] = "yaml.docker-compose",
      },
    })
    vim.treesitter.language.register("yaml", "yaml.docker-compose")
  end,
}
