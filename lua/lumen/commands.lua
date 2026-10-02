local packs = require("lumen.packs")

local actions = {
  packs = {
    desc = "Manage language packs",
    run = function(args)
      local sub, name = args[1], args[2]
      if (sub == "enable" or sub == "disable") and name then
        if not vim.tbl_contains(packs.available(), name) then
          return Lumen.error("unknown pack: " .. name)
        end
        packs.set(name, sub == "enable")
        return packs.prompt_restart(("%s pack `%s`"):format(sub == "enable" and "Enabled" or "Disabled", name))
      end
      packs.pick()
    end,
  },
  health = {
    desc = "Run :checkhealth lumen",
    run = function()
      vim.cmd("checkhealth lumen")
    end,
  },
  profile = {
    desc = "Startup profile",
    run = function()
      vim.cmd("Lazy profile")
    end,
  },
  update = {
    desc = "Snapshot → update → verify (rollback if broken)",
    run = function()
      require("lumen.update").update()
    end,
  },
  rollback = {
    desc = "Restore plugins from an update snapshot",
    run = function()
      require("lumen.update").pick_rollback()
    end,
  },
  why = {
    desc = "Explain LSP / format / lint / parser setup for this buffer",
    run = function()
      require("lumen.why").show()
    end,
  },
  tasks = {
    desc = "Run a project task",
    run = function()
      require("lumen.tasks").pick()
    end,
  },
  theme = {
    desc = "Toggle night / dawn",
    run = function()
      vim.o.background = vim.o.background == "dark" and "light" or "dark"
    end,
  },
  config = {
    desc = "Edit your config",
    run = function()
      Snacks.picker.files({ cwd = vim.fn.stdpath("config") })
    end,
  },
  keys = {
    desc = "Search all keymaps",
    run = function()
      Snacks.picker.keymaps()
    end,
  },
}

-- menu order: everyday things first, maintenance last
local names = { "packs", "why", "tasks", "keys", "config", "theme", "health", "update", "rollback", "profile" }
local rest = vim.tbl_filter(function(n)
  return not vim.tbl_contains(names, n)
end, vim.tbl_keys(actions))
table.sort(rest)
names = vim.list_extend(
  vim.tbl_filter(function(n)
    return actions[n] ~= nil
  end, names),
  rest
)

vim.api.nvim_create_user_command("Lumen", function(cmd)
  local args = cmd.fargs
  if #args == 0 then
    local items = vim.tbl_map(function(n)
      return { name = n, desc = actions[n].desc }
    end, names)
    return vim.ui.select(items, {
      prompt = "󰛨 Lumen",
      format_item = function(item)
        return ("%-8s  %s"):format(item.name, item.desc)
      end,
    }, function(item)
      if item then
        actions[item.name].run({})
      end
    end)
  end
  local action = actions[args[1]]
  if not action then
    return Lumen.error("unknown command: " .. args[1])
  end
  action.run(vim.list_slice(args, 2))
end, {
  nargs = "*",
  desc = "Lumen",
  complete = function(_, line)
    local parts = vim.split(line, "%s+", { trimempty = false })
    if #parts == 2 then
      return names
    elseif #parts == 3 and parts[2] == "packs" then
      return { "enable", "disable" }
    elseif #parts == 4 and parts[2] == "packs" then
      return packs.available()
    end
    return {}
  end,
})
