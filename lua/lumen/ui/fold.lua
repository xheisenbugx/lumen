-- Folded lines keep their syntax highlighting and show how much is hidden:
--   function M.setup(opts) ⋯  23 lines

local M = {}

---@param buf integer
---@param lnum integer 0-based
local function highlighted(buf, lnum)
  local line = vim.api.nvim_buf_get_lines(buf, lnum, lnum + 1, false)[1] or ""
  local ok, parser = pcall(vim.treesitter.get_parser, buf)
  if not ok or not parser then
    return { { line, "Folded" } }
  end

  -- column → highlight group (later, more specific captures win)
  local hls = {}
  parser:for_each_tree(function(tree, ltree)
    local query = vim.treesitter.query.get(ltree:lang(), "highlights")
    if not query then
      return
    end
    for id, node in query:iter_captures(tree:root(), buf, lnum, lnum + 1) do
      local sr, sc, er, ec = node:range()
      if sr <= lnum and er >= lnum then
        sc = sr < lnum and 0 or sc
        ec = er > lnum and #line or ec
        local group = "@" .. query.captures[id] .. "." .. ltree:lang()
        for c = sc, ec - 1 do
          hls[c] = group
        end
      end
    end
  end)

  local chunks, text, cur = {}, "", nil
  for c = 0, #line - 1 do
    local hl = hls[c] or "Folded"
    if hl ~= cur and text ~= "" then
      chunks[#chunks + 1] = { text, cur }
      text = ""
    end
    cur = hl
    text = text .. line:sub(c + 1, c + 1)
  end
  if text ~= "" then
    chunks[#chunks + 1] = { text, cur }
  end
  return chunks
end

function M.text()
  local buf = vim.api.nvim_get_current_buf()
  local start, stop = vim.v.foldstart, vim.v.foldend
  local ok, chunks = pcall(highlighted, buf, start - 1)
  if not ok then
    chunks = { { vim.fn.getline(start), "Folded" } }
  end
  -- foldtext can't show tabs: expand them to the next tab stop so the text stays aligned
  local ts, col = vim.bo[buf].tabstop, 0
  for _, c in ipairs(chunks) do
    local parts = vim.split(c[1], "\t", { plain = true })
    for i, part in ipairs(parts) do
      col = col + vim.fn.strdisplaywidth(part)
      if i < #parts then
        local n = ts - col % ts
        parts[i], col = part .. string.rep(" ", n), col + n
      end
    end
    c[1] = table.concat(parts)
  end
  chunks[#chunks + 1] = { " ⋯ ", "LumenFoldDots" }
  chunks[#chunks + 1] = { (" %d lines "):format(stop - start + 1), "LumenFoldCount" }
  return chunks
end

function M.setup()
  vim.o.foldtext = "v:lua.require'lumen.ui.fold'.text()"
end

return M
