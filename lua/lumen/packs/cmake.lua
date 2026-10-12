---@type lumen.Pack
return {
  desc = "CMake (neocmakelsp, cmake-format)",
  ft = { "cmake" },
  requires = { { "python3", "python" } },
  parsers = { "cmake" },
  servers = { neocmake = {} },
  tools = { "cmakelang" },
  formatters = { cmake = { "cmake_format" } },
}
