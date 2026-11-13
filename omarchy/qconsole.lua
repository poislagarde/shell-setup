-- Omarchy's Quake console (Super + `), adjusted: it opens the default shell
-- rather than the default agent, spans the full width and 75% of the usable
-- height, and is bound to the physical ` key so dead-key layouts (US
-- International) reach it.
--
-- Loaded by the shell-setup managed block in ~/.config/hypr/hyprland.lua
-- (bootstrap §20), which wraps Omarchy's defaults:
--   qconsole.capture(); require("default.hypr.omarchy"); qconsole.apply()
-- Check after Omarchy updates (expect 1 and true):
--   hyprctl repl 'return qconsole_agent_seeds_removed'
--   hyprctl repl 'return qconsole_resized'

local M = {}

local CONSOLE = "special:qconsole"
local HEIGHT = 0.75 -- fraction of the usable height the console covers

local hl_on, hooks = nil, {}

-- Omarchy's qconsole.lua keeps no handle to its event subscriptions, so record
-- the ones it makes while Omarchy's defaults load.
function M.capture()
  hl_on, hooks = hl.on, {}
  hl.on = function(event, cb)
    local sub = hl_on(event, cb)
    if debug.getinfo(cb, "S").source:find("/qconsole.lua", 1, true) then
      hooks[#hooks + 1] = { event = event, cb = cb, sub = sub }
    end
    return sub
  end
end

local function upvalue_index(fn, name)
  for i = 1, math.huge do
    local n = debug.getupvalue(fn, i)
    if n == nil then return nil end
    if n == name then return i end
  end
end

local function upvalue(fn, name)
  local i = fn and upvalue_index(fn, name)
  return i and select(2, debug.getupvalue(fn, i))
end

-- Seed an empty console with the default shell instead of `omarchy-agent`. Its
-- own app ID makes the terminal start a separate instance, so the window lands
-- on the console rather than being handed to an already-running terminal (as
-- Ghostty's single-instance mode would).
local function seed_shell()
  qconsole_agent_seeds_removed = 0
  for _, hook in ipairs(hooks) do
    if hook.event == "workspace.created" then
      hook.sub:remove()
      qconsole_agent_seeds_removed = qconsole_agent_seeds_removed + 1
    end
  end

  hl.on("workspace.created", function(ws)
    if ws and ws.name == CONSOLE and ws.is_empty then
      hl.exec_cmd(o.launch("xdg-terminal-exec --app-id=org.omarchy.qconsole"), { workspace = CONSOLE .. " silent" })
    end
  end)
end

-- qconsole.lua sizes the console from two locals, `share` (fraction of the
-- height) and `box` (how many times wider than tall a single-window console is
-- boxed). They aren't settings, so set them on the fit function its handlers
-- share, then refit once so the rule changes now; Omarchy's handlers keep
-- refitting it on monitor and window changes.
local function resize()
  local refit
  for _, hook in ipairs(hooks) do
    refit = refit or upvalue(hook.cb, "refit")
  end
  local fit = upvalue(refit, "fit")
  local share_i = fit and upvalue_index(fit, "share")
  local box_i = fit and upvalue_index(fit, "box")

  qconsole_resized = share_i ~= nil and box_i ~= nil
  if qconsole_resized then
    debug.setupvalue(fit, share_i, HEIGHT)
    debug.setupvalue(fit, box_i, math.huge)
    refit()
  end
end

-- US International makes ` a dead key (dead_grave, Shift: dead_tilde), so
-- Omarchy's `grave` binds never fire; code:49 is the key itself, whatever the
-- layout. The grave binds go, so a layout without dead keys doesn't fire both
-- and toggle twice.
local function bind_physical_key()
  hl.unbind("SUPER + grave")
  hl.unbind("SUPER + SHIFT + grave")
  o.bind("SUPER + code:49", "Toggle Quake console", hl.dsp.workspace.toggle_special("qconsole"))
  o.bind("SUPER + SHIFT + code:49", "Move window to Quake console",
    hl.dsp.window.move({ workspace = CONSOLE, follow = false }))
end

function M.apply()
  if hl_on then
    hl.on = hl_on
  end
  seed_shell()
  resize()
  bind_physical_key()
end

return M
