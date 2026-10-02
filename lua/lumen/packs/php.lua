---@type lumen.Pack
return {
  desc = "PHP (intelephense, php-cs-fixer)",
  ft = { "php", "blade" },
  parsers = { "php", "phpdoc", "blade" },
  servers = { intelephense = {} },
  tools = { "php-cs-fixer" },
  formatters = { php = { "php_cs_fixer" } },
}
