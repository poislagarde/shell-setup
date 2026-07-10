#!/usr/bin/env bash
# Animate the "working" breathe on tmux window labels by ticking the @pulse
# option. tmux.conf's window-status formats map @pulse (0..3) to a luminance
# level, so advancing it makes working windows breathe. Crucially, *setting an
# option* forces tmux to re-expand EVERY window label — a plain status redraw
# does not re-expand non-selected labels, and Claude pauses its title spinner
# while its pane is unfocused (focus-events), so the frame itself is frozen for
# background windows. Driving the color from @pulse (time) instead of the
# spinner frame sidesteps both problems.
#
# We only tick — and so only force ~2x/s redraws — while at least one window is
# actually working. While idle we just poll cheaply and force nothing, so the
# #(continuum_save.sh) on status-right keeps running only at the 15s
# status-interval. It runs ~1x/s only during active agent work, when the
# machine is busy anyway and the extra ~40ms/s is in the noise.
#
# Launched backgrounded from tmux.conf. A per-server-PID mkdir lock (flock is
# unavailable on macOS) stops a config reload from stacking duplicate loops; the
# loop exits when the server — and thus its PID — goes away. The running loop
# survives reloads, so edits here take effect only after the tmux server restarts
# (or you remove the lock dir and relaunch).

pid="$(tmux display-message -p '#{pid}' 2>/dev/null)" || exit 0
[ -n "$pid" ] || exit 0
lock="${TMPDIR:-/tmp}/tmux-status-refresh-${pid}"
mkdir "$lock" 2>/dev/null || exit 0
trap 'rmdir "$lock" 2>/dev/null' EXIT   # cleanup on any exit
trap 'exit 0' INT TERM                  # signals -> exit -> runs the EXIT trap

# Any window "working"? pane_title has a leading glyph that is NOT the ✳ idle
# marker (i.e. a braille spinner frame). Same test as the window-status format,
# kept in sync by copying it verbatim.
any_working() {
	tmux list-windows -a -F \
'#{?#{&&:#{!=:#{s/^[✳⠀-⣿] //:pane_title},#{pane_title}},#{?#{m:✳ *,#{pane_title}},0,1}},1,}' \
		2>/dev/null | grep -q 1
}

# Triangle over luminance levels 0..3 → a smooth breathe (~3s per cycle at 0.5s).
levels=(0 1 2 3 2 1); n=${#levels[@]}; i=0
while tmux has-session 2>/dev/null; do
	if any_working; then
		tmux set -g @pulse "${levels[$i]}" 2>/dev/null
		i=$(( (i + 1) % n ))
		sleep 0.5
	else
		i=0
		sleep 2
	fi
done
