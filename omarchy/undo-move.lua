-- Super + Shift + Z undoes the last move of a window to another workspace: the
-- window goes back to the workspace it left, and when that was a special
-- workspace (the Quake console, the scratchpad) the view first returns to the
-- workspace that was showing under it. It catches a slip from
-- Super + Shift + ` onto Super + Shift + 1..0, which pulls the console's window
-- out onto a workspace.
--
-- One level: a second press does nothing until another window moves.
--
-- Loaded by the shell-setup managed block in ~/.config/hypr/hyprland.lua
-- (bootstrap §20), after Omarchy's defaults.

-- window.move_to_workspace fires with the window already on its new workspace,
-- so each window's workspace is kept here to know where a move came from.
local placed = {}
local last = nil
local undoing = false

local function remember(window, workspace)
  if window and workspace then
    placed[window.address] = { id = workspace.id, name = workspace.name, special = workspace.special }
  end
end

for _, window in ipairs(hl.get_windows()) do
  remember(window, window.workspace)
end

hl.on("window.open", function(window)
  remember(window, window and window.workspace)
end)

-- window.destroy no longer knows the window's address; window.close does.
hl.on("window.close", function(window)
  if window and window.address then
    placed[window.address] = nil
  end
end)

-- A dispatcher move fires this before following the window, so the active
-- monitor still shows the workspace the move started from.
hl.on("window.move_to_workspace", function(window, workspace)
  if not (window and workspace) then
    return
  end

  local from = placed[window.address]
  remember(window, workspace)
  if undoing or not from or from.id == workspace.id then
    return
  end

  local monitor = hl.get_active_monitor()
  local view = monitor and monitor.active_workspace
  last = { address = window.address, from = from, to = workspace.id, view = view and view.id }
end)

local function undo()
  local move = last
  last = nil
  if not move then
    return
  end

  local window = hl.get_window("address:" .. move.address)
  if not (window and window.workspace and window.workspace.id == move.to) then
    return
  end

  undoing = true
  pcall(function()
    if move.from.special and move.view then
      local monitor = hl.get_active_monitor()
      local view = monitor and monitor.active_workspace
      if not view or view.id ~= move.view then
        hl.dispatch(hl.dsp.focus({ workspace = tostring(move.view) }))
      end
    end
    hl.dispatch(hl.dsp.window.move({
      workspace = move.from.special and move.from.name or tostring(move.from.id),
      follow = true,
      window = "address:" .. move.address,
    }))
  end)
  undoing = false
end

o.bind("SUPER + SHIFT + Z", "Undo window move", undo)
