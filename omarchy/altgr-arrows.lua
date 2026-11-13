-- AltGr + Up/Down act as Alt + Up/Down in every app (in herdr: previous / next
-- space). Apps can't see AltGr as a modifier, so without these binds they get a
-- plain arrow. AltGr is MOD5 (Right Alt on US International); layouts without
-- it never fire these binds.
--
-- Loaded by the shell-setup managed block in ~/.config/hypr/hyprland.lua
-- (bootstrap §20), after Omarchy's defaults.

local function send_alt(key)
  return function()
    hl.dispatch(hl.dsp.send_key_state({ mods = "ALT", key = key, state = "down" }))
    -- Release before the next key repeat (25 ms at Omarchy's repeat_rate = 40).
    hl.timer(function()
      hl.dispatch(hl.dsp.send_key_state({ mods = "ALT", key = key, state = "up" }))
    end, { timeout = 10, type = "oneshot" })
  end
end

o.bind("MOD5 + UP", "Alt + Up", send_alt("Up"), { repeating = true })
o.bind("MOD5 + DOWN", "Alt + Down", send_alt("Down"), { repeating = true })
