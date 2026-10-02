-- Windowed sign lookup for Snacks.statuscolumn.
--
-- Snacks drops its sign cache every 50ms and then, on the next redraw, fetches every sign
-- extmark of the whole buffer with details (Snacks.statuscolumn.buf_signs). With thousands of
-- diagnostics that is ~4ms per redraw, i.e. on nearly every cursor move. This returns the same
-- line → signs table, but filled lazily, one block of lines at a time, as the statuscolumn asks
-- for the lines it draws: a range query per block instead of the whole mark tree.

local M = {}

local BLOCK = 128

---@param sc table snacks.statuscolumn
local function windowed(sc, full)
  ---@param buf integer
  ---@param wanted snacks.statuscolumn.Wanted
  return function(buf, wanted)
    if not (wanted.git or wanted.sign) then
      return full(buf, wanted)
    end
    -- marks are few: take them from the original implementation, by line
    local marks = wanted.mark and full(buf, { mark = true }) or {}
    local done = {} ---@type table<integer, boolean>
    return setmetatable({}, {
      __index = function(t, lnum)
        if type(lnum) ~= "number" then
          return
        end
        local block = math.floor((lnum - 1) / BLOCK)
        if done[block] then
          return
        end
        done[block] = true
        local first = block * BLOCK -- 0-based
        local ok, extmarks = pcall(
          vim.api.nvim_buf_get_extmarks,
          buf,
          -1,
          { first, 0 },
          { first + BLOCK - 1, -1 },
          { details = true, type = "sign" }
        )
        for _, extmark in ipairs(ok and extmarks or {}) do
          local d = extmark[4]
          local name = d.sign_hl_group or d.sign_name or ""
          local sign = {
            name = name,
            type = sc.is_git_sign(name) and "git" or "sign",
            text = d.sign_text,
            texthl = d.sign_hl_group,
            priority = d.priority,
          }
          if wanted[sign.type] then
            local l = extmark[2] + 1
            local list = rawget(t, l) or {}
            list[#list + 1] = sign
            rawset(t, l, list)
          end
        end
        for l = first + 1, first + BLOCK do
          if marks[l] then
            local list = rawget(t, l) or {}
            vim.list_extend(list, marks[l])
            rawset(t, l, list)
          end
        end
        return rawget(t, lnum)
      end,
    })
  end
end

function M.setup()
  local ok, sc = pcall(require, "snacks.statuscolumn")
  -- only patch the implementation this was written against
  if not ok or sc._lumen_windowed or type(sc.buf_signs) ~= "function" or type(sc.is_git_sign) ~= "function" then
    return
  end
  sc._lumen_windowed = true
  M.original = sc.buf_signs -- kept for tests
  sc.buf_signs = windowed(sc, sc.buf_signs)
end

return M
