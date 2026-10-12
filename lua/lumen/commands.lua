local packs = require("lumen.packs")

local actions = {
  packs = {
    desc = "Manage language packs",
    run = function(args)
      local sub, name = args[1], args[2]
      if (sub == "enable" or sub == "disable" or sub == "dismiss") and name then
        if not packs.exists(name) then
          return Lumen.error("unknown pack: " .. name)
        end
        if sub == "dismiss" then
          packs.dismiss(name)
          return Lumen.notify(("Lumen won't suggest the `%s` pack again"):format(name))
        end
        return packs.toggle(name, sub == "enable")
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
  doctor = {
    desc = "Deep report: binaries, Mason, root trace, LSP log · `doctor json` copies it for bug reports",
    run = function(args)
      if args[1] == "json" then
        local json = require("lumen.why").json(0)
        local path = vim.fn.stdpath("state") .. "/lumen/doctor.json"
        vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
        vim.fn.writefile({ json }, path)
        pcall(vim.fn.setreg, "+", json)
        vim.fn.setreg('"', json)
        return Lumen.notify("Doctor report copied to the clipboard and saved to " .. vim.fn.fnamemodify(path, ":~"))
      end
      require("lumen.why").show({ deep = true })
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
      if _G.Snacks then
        return Snacks.picker.files({ cwd = vim.fn.stdpath("config") })
      end
      vim.cmd.edit(vim.fn.stdpath("config") .. "/lua/config/lumen.lua")
    end,
  },
  project = {
    desc = "Edit this project's .lumen.lua (per-project packs, tasks, settings)",
    run = function()
      require("lumen.project").edit()
    end,
  },
  trust = {
    desc = "Trust this project's .lumen.lua and apply it",
    run = function()
      require("lumen.project").trust()
    end,
  },
  news = {
    desc = "What's new in Lumen",
    run = function()
      require("lumen.update").news()
    end,
  },
  keys = {
    desc = "Search all keymaps",
    run = function()
      if _G.Snacks then
        return Snacks.picker.keymaps()
      end
      vim.cmd("map")
    end,
  },
}

-- menu order: everyday things first, maintenance last
local names = {
  "packs",
  "why",
  "doctor",
  "tasks",
  "keys",
  "config",
  "project",
  "trust",
  "theme",
  "health",
  "update",
  "rollback",
  "news",
  "profile",
}
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
    elseif #parts == 3 and parts[2] == "doctor" then
      return { "json" }
    elseif #parts == 3 and parts[2] == "packs" then
      return { "enable", "disable", "dismiss" }
    elseif #parts == 4 and parts[2] == "packs" then
      return packs.available()
    end
    return {}
  end,
})
