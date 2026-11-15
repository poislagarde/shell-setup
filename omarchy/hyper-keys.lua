-- Omarchy's window keys on Super + arrows and Super + Backspace move to Hyper
-- (Caps Lock, bootstrap §21) with the same extra modifiers: Hyper + arrows
-- focus, Hyper + Shift + arrows swap, and so on. Super + arrows and
-- Super + Backspace are then free for macOS-style text keys
-- (omarchy/text-keys.lua). Hyper is Mod3, Hyprland's MOD3.
--
-- Loaded by the shell-setup managed block in ~/.config/hypr/hyprland.lua
-- (bootstrap §20), which wraps Omarchy's defaults:
--   hyper_keys.capture(); require("default.hypr.omarchy"); hyper_keys.apply()
-- Check after Omarchy updates (expect a number above 0):
--   hyprctl repl 'return hyper_keys_moved'

local M = {}

local MOVED_KEYS = { LEFT = true, RIGHT = true, UP = true, DOWN = true, BACKSPACE = true }

-- "SUPER + SHIFT + LEFT" -> "MOD3 + SHIFT + LEFT"; other chords pass unchanged.
local function to_hyper(keys)
  if type(keys) ~= "string" then
    return keys
  end
  local parts = {}
  for part in keys:gmatch("[^+]+") do
    parts[#parts + 1] = part:match("^%s*(.-)%s*$")
  end
  if not MOVED_KEYS[(parts[#parts] or ""):upper()] then
    return keys
  end
  local moved = false
  for i = 1, #parts - 1 do
    if parts[i]:upper() == "SUPER" then
      parts[i] = "MOD3"
      moved = true
    end
  end
  return moved and table.concat(parts, " + ") or keys
end

local hl_bind, hl_unbind

function M.capture()
  hyper_keys_moved = 0
  hl_bind, hl_unbind = hl.bind, hl.unbind
  hl.bind = function(keys, ...)
    local hyper = to_hyper(keys)
    if hyper ~= keys then
      hyper_keys_moved = hyper_keys_moved + 1
    end
    return hl_bind(hyper, ...)
  end
  hl.unbind = function(keys, ...)
    return hl_unbind(to_hyper(keys), ...)
  end
end

function M.apply()
  hl.bind, hl.unbind = hl_bind, hl_unbind
end

return M
