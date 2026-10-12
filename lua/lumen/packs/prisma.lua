---@type lumen.Pack
return {
  desc = "Prisma schema",
  ft = { "prisma" },
  requires = { "node", "npm" },
  parsers = { "prisma" },
  servers = { prismals = {} },
}
