#!/usr/bin/env bash
# Three jobs for the status/border chrome, one loop:
#
# 1. Aggregate assistant activity into the @assistant-window window option that
#    tmux.conf's window-status formats color from: "input" (an assistant is
#    blocked on you) beats "busy" (one is working) beats unset (idle/plain).
#    The per-pane truth comes from the @assistant-state options the
#    assistant-activity hooks write; a pane whose assistant reports no state at
#    all falls back to the pane title's spinner glyph, which is all a session
#    predating the hooks — or one whose build stopped emitting glyphs — can
#    offer. Doing the aggregation here keeps the formats a plain three-way
#    color choice instead of a per-pane loop repeated in every color slot.
#
# 2. Animate the breathe by ticking @pulse (working) and @pulse2 (waiting on
#    you, twice as fast). Crucially, *setting an option* forces tmux to
#    re-expand EVERY window label — a plain status redraw does not re-expand
#    non-selected labels, and an unfocused assistant pane pauses its title
#    spinner (focus-events), so the frame itself is frozen for background
#    windows. Driving color from a ticking option instead of the spinner frame
#    sidesteps both problems.
#
#    We only tick — and so only force redraws — while at least one window is
#    working or waiting. While idle we just poll cheaply and force nothing, so
#    the #(continuum_save.sh) on status-right keeps running only at the 15s
#    status-interval. It runs more often only during active agent work, when the
#    machine is busy anyway and the extra ~40ms/s is in the noise.
#
# 3. Feed the pane-border bar's git segments: every GIT_EVERY seconds, sweep
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

# How long a "busy" claim survives without a renewing hook event. Every tool
# call renews it, so only a turn that ended without a Stop hook — you pressed
# escape — or a single call longer than this needs the sweep below.
BUSY_TTL=300

# Fields per pane, '|' separated (no field can contain one, and unlike
# whitespace an empty field between two of them still reads as empty): pane id,
# window id, hook state, when it was written, the assistant's pid, the pane's own
# shell (to find that assistant when the pid is missing), the title glyph
# fallback bit, and what @assistant-window currently holds for the window.
PANE_FIELDS='#{pane_id}|#{window_id}|#{@assistant-state}|#{@assistant-state-at}|#{@assistant-pid}|#{pane_pid}|#{?#{&&:#{!=:#{s/^[✳⠀-⣿◐-◓] //:pane_title},#{pane_title}},#{?#{m:✳ *,#{pane_title}},0,1}},1,0}|#{@assistant-window}'

# One process-table snapshot per sweep, shared by the two questions below and
# taken only when a pane actually needs it. `pgrep -P` is not usable here: it
# reports no children for a pane's shell even where ps shows the parent link.
snapshot() { [ -n "$PS_SNAP" ] || PS_SNAP=$(ps -axo pid=,ppid=,comm= 2>/dev/null); }

# Is a tool call still running under this assistant? A tool that shells out is a
# direct shell child of the assistant process (claude → /bin/zsh), and MCP
# servers are not shells, so a shell child means work is genuinely in flight —
# what keeps a long silent build from expiring the TTL above. Its own output is
# unobservable: the tool's stdout is a pipe into the assistant, and macOS has no
# per-process I/O counters. An MCP server started through a shell wrapper would
# read as a tool that never ends, which only delays the downgrade after an
# interrupted call — a case with no hook event either way.
tool_running() {
	[ -n "$1" ] || return 1
	snapshot
	awk -v parent="$1" '
		$2 == parent {
			base = $3; sub(/.*\//, "", base)
			if (base == "sh" || base == "bash" || base == "zsh" ||
			    base == "dash" || base == "ksh") { found = 1; exit }
		}
		END { exit(found ? 0 : 1) }
	' <<<"$PS_SNAP"
}

# The assistant running in a pane, searched downward from the pane's own shell.
# set-state.sh records the pid at SessionStart, so this only covers panes whose
# SessionStart predates these hooks — but without it those panes never get tool
# detection, and a long silent build there would expire the TTL while working.
find_assistant() {
	snapshot
	awk -v root="$1" '
		{ pid[NR] = $1; ppid[NR] = $2; name[NR] = $3; rows = NR }
		END {
			gen[root] = 1
			for (depth = 0; depth < 3; depth++) {
				for (i = 1; i <= rows; i++) {
					if (!(ppid[i] in gen)) continue
					base = name[i]; sub(/.*\//, "", base)
					if (base == "claude" || base == "codex") { print pid[i]; exit 0 }
					found[pid[i]] = 1
				}
				for (k in found) gen[k] = 1
				delete found
			}
			exit 1
		}
	' <<<"$PS_SNAP"
}

clear_pane() {
	tmux set -up -t "$1" @assistant-state \; \
		set -up -t "$1" @assistant-state-at \; \
		set -up -t "$1" @assistant-pid \; \
		set -up -t "$1" @assistant-pending 2>/dev/null
}

# Resolve every pane to a level (2 waiting, 1 working, 0 neither), reduce to the
# maximum per window, and store it — only on change, so an unchanged sweep
# forces no redraw. Sets $activity to the maximum across all windows, which
# picks the tick rate below.
#
# Every window must reach the apply loop, including the ones that resolve to 0:
# those are exactly the windows whose stale flag needs clearing. Two awk details
# are load-bearing there. Guard the max with `in` rather than a bare `>`, since a
# window whose only level is 0 would otherwise leave the element uninitialized;
# and print `max[w] + 0`, because an empty level field collapses under the read
# below and shifts the window's current value into $level, where it reads as "no
# change wanted" and the flag survives forever.
scan() {
	local id win state at apid ppid glyph cur level now="" buf="" want
	local PS_SNAP=""
	activity=0
	while IFS='|' read -r id win state at apid ppid glyph cur; do
		[ -n "$id" ] || continue
		case "$state" in
		busy | input)
			if [ -z "$apid" ]; then
				snapshot # before the subshell below, so it is taken once
				apid=$(find_assistant "$ppid") || apid=""
				[ -n "$apid" ] &&
					tmux set -p -t "$id" @assistant-pid "$apid" 2>/dev/null
			fi
			# An assistant that died without a SessionEnd (crash, SIGKILL)
			# leaves state behind: its pid going away is what clears it, and
			# what keeps "input" — which deliberately never expires, since an
			# unanswered prompt stays unanswered — from pulsing forever.
			if [ -n "$apid" ] && ! kill -0 "$apid" 2>/dev/null; then
				clear_pane "$id"
				level=0
			elif [ "$state" = input ]; then
				level=2
			else
				[ -n "$now" ] || now=$(date +%s)
				if [ $((now - ${at:-0})) -ge "$BUSY_TTL" ] && ! tool_running "$apid"; then
					tmux set -p -t "$id" @assistant-state idle \; \
						set -p -t "$id" @assistant-state-at "$now" 2>/dev/null
					level=0
				else
					level=1
				fi
			fi
			;;
		"")
			level=$glyph # no hook state at all -> trust the title glyph
			;;
		*)
			level=0 # idle
			;;
		esac
		[ "$level" -gt "$activity" ] && activity=$level
		buf+="$win $level $cur"$'\n'
	done <<<"$(tmux list-panes -a -F "$PANE_FIELDS" 2>/dev/null)"

	while read -r win level cur; do
		[ -n "$win" ] || continue
		case "$level" in
		2) want=input ;;
		1) want=busy ;;
		*) want="" ;;
		esac
		[ "$want" = "$cur" ] && continue
		if [ -n "$want" ]; then
			tmux set -w -t "$win" @assistant-window "$want" 2>/dev/null
		else
			tmux set -uw -t "$win" @assistant-window 2>/dev/null
		fi
	done <<<"$(awk '{
	                  lvl = $2 + 0
	                  if (!($1 in max) || lvl > max[$1]) max[$1] = lvl
	                  cur[$1] = $3
	                }
	                END { for (w in max) print w, max[w] + 0, cur[w] }' <<<"$buf")"
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

# Triangle over luminance levels 0..3 → a smooth breathe. @pulse gets one step
# per 0.5s (~3s per cycle) whether we tick at 0.5s or, when something is waiting
# on you, at 0.25s — where @pulse2 takes a step every tick, breathing twice as
# fast so the state that needs you reads as more urgent. Both are set in ONE
# tmux invocation: each `set` forces a full re-expansion of every label.
# Liveness = the server PID, NOT a `tmux has-session` client round-trip: one
# transient client failure (e.g. under memory pressure) would read as "server
# gone" and kill the loop permanently.
levels=(0 1 2 3 2 1); n=${#levels[@]}; i=0; j=0; tick=0
last_git=-$GIT_EVERY                     # sweep immediately on loop start
while kill -0 "$pid" 2>/dev/null; do
	if [ $((SECONDS - last_git)) -ge "$GIT_EVERY" ]; then
		refresh_git
		last_git=$SECONDS
	fi
	scan
	case "$activity" in
	2)
		tmux set -g @pulse2 "${levels[$j]}" \; set -g @pulse "${levels[$i]}" 2>/dev/null
		j=$(( (j + 1) % n ))
		tick=$(( tick + 1 ))
		[ $((tick % 2)) -eq 0 ] && i=$(( (i + 1) % n ))
		sleep 0.25
		;;
	1)
		tmux set -g @pulse "${levels[$i]}" 2>/dev/null
		i=$(( (i + 1) % n ))
		j=0; tick=0
		sleep 0.5
		;;
	*)
		i=0; j=0; tick=0
		sleep 2
		;;
	esac
done
