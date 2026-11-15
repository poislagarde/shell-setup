-- macOS-style text keys in every app, with Super as Cmd and Alt as Option:
-- - Alt + Left/Right jump a word, Alt + Shift + Left/Right select a word at a
--   time, and Alt + Backspace deletes the previous word. GUI apps and shell
--   panels get the Ctrl chords. Terminals get the Alt chord back: Ghostty turns
--   Alt + Left/Right/Backspace into Esc b / Esc f / Ctrl+W and passes
--   Alt + Shift + Left/Right on to zsh and the apps in herdr. This costs
--   browsers their Alt + Left/Right back/forward.
-- - Super + Left/Right go to the start or end of the line, Super + Up/Down to
--   the start or end of the document, and Super + Backspace deletes to the
--   start of the line; with Shift, the arrows select. GUI apps get Home/End,
--   Ctrl + Home/End and Shift + Home, Backspace. Terminals get the Super chord
--   back: Ghostty turns Super + Left/Right/Backspace into Ctrl+A / Ctrl+E /
--   Ctrl+U and passes the rest on. Omarchy's window keys on these chords move
--   to Hyper (omarchy/hyper-keys.lua).
-- - AltGr does the same as Alt with these keys and with Up/Down (in herdr,
--   Alt + Up/Down switch spaces). Apps can't see AltGr as a modifier, so
--   without these binds they get a plain key. AltGr is MOD5; layouts without it
--   never fire its binds.
-- - Alt + Shift + 1..9 reach terminals as Ctrl + Alt + 1..9, which herdr also
--   binds to "jump to space N". Shift + 6 is a dead key (^) on US
--   International, so the terminal would swallow Alt + Shift + 6. Other apps
--   get Alt + Shift + digit unchanged.
-- - A sent key leaves the window thinking no modifiers are held until one is
--   pressed or released, so later keys typed with the same held modifiers
--   arrive bare. Bind every key of a group (all nine digits, all four arrows)
--   so holding the modifiers and stepping through the group keeps working.
--
-- Loaded by the shell-setup managed block in ~/.config/hypr/hyprland.lua
-- (bootstrap §20), after Omarchy's defaults.

local function send_key_once(mods, key)
  hl.dispatch(hl.dsp.send_key_state({ mods = mods, key = key, state = "down" }))
  -- Release before the next key repeat (25 ms at Omarchy's repeat_rate = 40).
  hl.timer(function()
    hl.dispatch(hl.dsp.send_key_state({ mods = mods, key = key, state = "up" }))
  end, { timeout = 10, type = "oneshot" })
end

local function active_window_is_terminal()
  local window = hl.get_active_window()
  for _, tag in ipairs((window and window.tags) or {}) do
    if tag:gsub("%*$", "") == "terminal" then
      return true
    end
  end
  return false
end

-- Terminals get terminal_mods + key; other windows get gui_mods + gui_key.
local function edit(terminal_mods, key, gui_mods, gui_key)
  return function()
    if active_window_is_terminal() then
      send_key_once(terminal_mods, key)
    else
      send_key_once(gui_mods, gui_key)
    end
  end
end

local function as_alt(key)
  return function()
    send_key_once("ALT", key)
  end
end

for _, mod in ipairs({ "ALT", "MOD5" }) do
  o.bind(mod .. " + LEFT", "Word back", edit("ALT", "Left", "CTRL", "Left"), { repeating = true })
  o.bind(mod .. " + RIGHT", "Word forward", edit("ALT", "Right", "CTRL", "Right"), { repeating = true })
  o.bind(mod .. " + SHIFT + LEFT", "Select word back", edit("ALT SHIFT", "Left", "CTRL SHIFT", "Left"), { repeating = true })
  o.bind(mod .. " + SHIFT + RIGHT", "Select word forward", edit("ALT SHIFT", "Right", "CTRL SHIFT", "Right"), { repeating = true })
  o.bind(mod .. " + BACKSPACE", "Delete word back", edit("ALT", "BackSpace", "CTRL", "BackSpace"), { repeating = true })
end

o.bind("MOD5 + UP", "Alt + Up", as_alt("Up"), { repeating = true })
o.bind("MOD5 + DOWN", "Alt + Down", as_alt("Down"), { repeating = true })

for _, arrow in ipairs({
  { bind = "LEFT", key = "Left", name = "line start", gui_mods = "", gui_key = "Home" },
  { bind = "RIGHT", key = "Right", name = "line end", gui_mods = "", gui_key = "End" },
  { bind = "UP", key = "Up", name = "document start", gui_mods = "CTRL", gui_key = "Home" },
  { bind = "DOWN", key = "Down", name = "document end", gui_mods = "CTRL", gui_key = "End" },
}) do
  local gui_select_mods = arrow.gui_mods == "" and "SHIFT" or arrow.gui_mods .. " SHIFT"
  o.bind("SUPER + " .. arrow.bind, "Go to " .. arrow.name,
    edit("SUPER", arrow.key, arrow.gui_mods, arrow.gui_key), { repeating = true })
  o.bind("SUPER + SHIFT + " .. arrow.bind, "Select to " .. arrow.name,
    edit("SUPER SHIFT", arrow.key, gui_select_mods, arrow.gui_key), { repeating = true })
end

-- GUI apps have no delete-to-line-start key, so select to the line start and
-- delete the selection.
o.bind("SUPER + BACKSPACE", "Delete to line start", function()
  if active_window_is_terminal() then
    send_key_once("SUPER", "BackSpace")
  else
    send_key_once("SHIFT", "Home")
    hl.timer(function()
      send_key_once("", "BackSpace")
    end, { timeout = 20, type = "oneshot" })
  end
end)

for digit = 1, 9 do
  local key = tostring(digit)
  o.bind("ALT + SHIFT + code:" .. tostring(digit + 9), "Jump to herdr space " .. key, function()
    if active_window_is_terminal() then
      send_key_once("CTRL ALT", key)
    else
      send_key_once("ALT SHIFT", key)
    end
  end)
end
