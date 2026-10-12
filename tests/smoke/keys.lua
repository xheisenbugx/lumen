-- Every keymap: pressed once in a child Neovim (tests/keys_probe.lua), none may error
---@param t lumen.test.Helpers
return function(t)
  local check, child = t.check, t.child

  check("every keymap Lumen defines runs without an error", function()
    local probe = table.concat(vim.fn.readfile(vim.fn.getcwd() .. "/tests/keys_probe.lua"), "\n")
    local res, out = child(
      [[vim.defer_fn(function() require("lumen_keys_probe") end, 100)]],
      { ["lua/lumen_keys_probe.lua"] = probe },
      nil,
      180000
    )
    assert(res.tested, "the probe didn't report:\n" .. (out.stdout or "") .. (out.stderr or ""))
    io.stdout:write(("      %d keys pressed, %d skipped\n"):format(res.tested, #res.skipped))
    assert(res.tested > 150, ("only %d keys found: is the probe filtering too much?"):format(res.tested))
    assert(#res.failed == 0, "keys that raised errors:\n  " .. table.concat(res.failed, "\n  "))
  end)
end
