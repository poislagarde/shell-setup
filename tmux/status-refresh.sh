#!/usr/bin/env bash
# Two jobs for the status/border chrome, one loop:
#
# 1. Animate the "working" breathe on tmux window labels by ticking the @pulse
#    option. tmux.conf's window-status formats map @pulse (0..3) to a luminance
#    level, so advancing it makes working windows breathe. Crucially, *setting
#    an option* forces tmux to re-expand EVERY window label — a plain status
#    redraw does not re-expand non-selected labels, and Claude pauses its title
#    spinner while its pane is unfocused (focus-events), so the frame itself is
#    frozen for background windows. Driving the color from @pulse (time)
#    instead of the spinner frame sidesteps both problems.
#
#    We only tick — and so only force ~2x/s redraws — while at least one window
#    is actually working. While idle we just poll cheaply and force nothing, so
#    the #(continuum_save.sh) on status-right keeps running only at the 15s
#    status-interval. It runs ~1x/s only during active agent work, when the
#    machine is busy anyway and the extra ~40ms/s is in the noise.
#
# 2. Feed the pane-border bar's git segments: every GIT_EVERY seconds, sweep
#    all panes and store each pane's branch name and dirty flag in the @branch
#    / @dirty pane options that pane-border-format.conf reads. This sweep is
#    the FALLBACK path: zshrc's _tmux_git_segments_refresh precmd hook pushes
#    the same values instantly at every prompt — keep the two in sync. The options are
#    set ONLY on change, so a sweep over an unchanged tree forces no redraws.
#    The border format must NOT compute these with #(git …) jobs itself: tmux
#    caches format jobs per client+pane, expands to "" on a cold cache (fresh
#    attach, or a window unviewed for >1h) and force-redraws when the job
#    completes — flashing the bar's layout and colors on window switches.
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

# Any pane "working"? pane_title has a leading glyph that is NOT the ✳ idle
# marker (i.e. a braille spinner frame). Same per-pane test as the window-status
# format's #{P:} loop, kept in sync by copying it verbatim. list-panes -a checks
# every pane, matching the format's any-pane-in-the-window semantics.
any_working() {
	tmux list-panes -a -F \
'#{?#{&&:#{!=:#{s/^[✳⠀-⣿] //:pane_title},#{pane_title}},#{?#{m:✳ *,#{pane_title}},0,1}},1,}' \
		2>/dev/null | grep -q 1
}

# Recompute @branch/@dirty for every pane; set only what changed. Branch is
# the symbolic ref, the short SHA when detached, empty outside a repo; dirty
# is "1" on any staged/unstaged change vs HEAD (untracked-only files don't
# count — swap in `git status --porcelain` if you want them to). Tab-separated
# read: git refnames can't contain whitespace, paths realistically no tabs.
# Panes can vanish mid-sweep; the set -p just fails quietly.
GIT_EVERY=5
refresh_git() {
	tmux list-panes -a -F \
		'#{pane_id}	#{pane_current_path}	#{@branch}	#{@dirty}' \
		2>/dev/null |
	while IFS=$'\t' read -r id path cur_b cur_d; do
		b=$(git -C "$path" symbolic-ref --short HEAD 2>/dev/null ||
			git -C "$path" rev-parse --short HEAD 2>/dev/null) || b=""
		d=""
		if [ -n "$b" ]; then
			git -C "$path" diff --quiet HEAD 2>/dev/null
			[ $? -eq 1 ] && d=1
		fi
		[ "$b" = "$cur_b" ] || tmux set -p -t "$id" @branch "$b" 2>/dev/null
		[ "$d" = "$cur_d" ] || tmux set -p -t "$id" @dirty "$d" 2>/dev/null
	done
}

# Triangle over luminance levels 0..3 → a smooth breathe (~3s per cycle at 0.5s).
# Liveness = the server PID, NOT a `tmux has-session` client round-trip: one
# transient client failure (e.g. under memory pressure) would read as "server
# gone" and kill the loop permanently.
levels=(0 1 2 3 2 1); n=${#levels[@]}; i=0
last_git=-$GIT_EVERY                     # sweep immediately on loop start
while kill -0 "$pid" 2>/dev/null; do
	if [ $((SECONDS - last_git)) -ge "$GIT_EVERY" ]; then
		refresh_git
		last_git=$SECONDS
	fi
	if any_working; then
		tmux set -g @pulse "${levels[$i]}" 2>/dev/null
		i=$(( (i + 1) % n ))
		sleep 0.5
	else
		i=0
		sleep 2
	fi
done
