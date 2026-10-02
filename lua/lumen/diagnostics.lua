-- Diagnostic presentation, with three inline modes you can cycle through:
--   text  → virtual text at the end of the line
--   lines → full messages under the current line only (virtual lines)
--   signs → just signs + underlines, a quiet screen
local config = require("lumen.config")
local icons = require("lumen.icons")

local M = {}

M.modes = { "text", "lines", "signs" }
M.mode = config.diagnostics

local function apply()
  local severity = vim.diagnostic.severity
  vim.diagnostic.config({
    severity_sort = true,
    underline = true,
    update_in_insert = false,
    virtual_text = M.mode == "text" and { spacing = 2, source = "if_many", prefix = "●" } or false,
    virtual_lines = M.mode == "lines" and { current_line = true } or false,
    float = { border = "rounded", source = "if_many", header = "" },
    signs = {
      text = {
        [severity.ERROR] = icons.diagnostics.Error,
        [severity.WARN] = icons.diagnostics.Warn,
        [severity.INFO] = icons.diagnostics.Info,
        [severity.HINT] = icons.diagnostics.Hint,
      },
      numhl = {
        [severity.ERROR] = "DiagnosticError",
        [severity.WARN] = "DiagnosticWarn",
      },
    },
  })
end

function M.setup()
  apply()
end

function M.cycle()
  local idx = 1
  for i, m in ipairs(M.modes) do
    if m == M.mode then
      idx = i
    end
  end
  M.mode = M.modes[idx % #M.modes + 1]
  apply()
  Lumen.notify("Diagnostics: " .. ({ text = "virtual text", lines = "virtual lines", signs = "signs only" })[M.mode])
end

return M
