-- macOS-style Alt keys in every app:
-- - Alt + Left/Right jump a word and Alt + Backspace deletes the previous one.
--   GUI apps and shell panels get the Ctrl chords. Terminals get the Alt chord
--   back, which Ghostty turns into Esc b / Esc f / Ctrl+W. This costs browsers
--   their Alt + Left/Right back/forward.
-- - AltGr does the same as Alt with these keys and with Up/Down (in herdr,
--   Alt + Up/Down switch spaces). Apps can't see AltGr as a modifier, so
--   without these binds they get a plain key. AltGr is MOD5 (Right Alt on US
--   International); layouts without it never fire its binds.
-- - Alt + Shift + 6 reaches terminals as Ctrl + Alt + 6, which herdr also binds
--   to "jump to space 6". Shift + 6 is a dead key (^) on US International, so
--   the terminal would swallow it. Other apps get Alt + Shift + 6 unchanged.
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

local function word_edit(key)
  return function()
    send_key_once(active_window_is_terminal() and "ALT" or "CTRL", key)
  end
end

local function as_alt(key)
  return function()
    send_key_once("ALT", key)
  end
end

for _, mod in ipairs({ "ALT", "MOD5" }) do
  o.bind(mod .. " + LEFT", "Word back", word_edit("Left"), { repeating = true })
  o.bind(mod .. " + RIGHT", "Word forward", word_edit("Right"), { repeating = true })
  o.bind(mod .. " + BACKSPACE", "Delete word back", word_edit("BackSpace"), { repeating = true })
end

o.bind("MOD5 + UP", "Alt + Up", as_alt("Up"), { repeating = true })
o.bind("MOD5 + DOWN", "Alt + Down", as_alt("Down"), { repeating = true })

o.bind("ALT + SHIFT + code:15", "Jump to herdr space 6", function()
  if active_window_is_terminal() then
    send_key_once("CTRL ALT", "6")
  else
    send_key_once("ALT SHIFT", "6")
  end
end)
