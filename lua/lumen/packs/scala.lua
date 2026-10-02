---@type lumen.Pack
return {
  desc = "Scala (metals via coursier)",
  ft = { "scala", "sbt" },
  parsers = { "scala" },
  servers = { metals = { mason = false } },
  formatters = { scala = { "scalafmt" } },
}
