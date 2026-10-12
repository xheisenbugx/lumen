---@type lumen.Pack
return {
  desc = "Scala (metals via coursier)",
  ft = { "scala", "sbt" },
  requires = { "java" },
  parsers = { "scala" },
  servers = { metals = { mason = false } },
  formatters = { scala = { "scalafmt" } },
}
