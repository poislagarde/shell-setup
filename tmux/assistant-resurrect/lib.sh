# Shared helpers for the assistant-resurrect scripts (sourced, not executed).
#
# A minimal, self-contained take on timvw/tmux-assistant-resurrect (MIT),
# trimmed to the two assistants actually in use here: Claude Code and Codex
# CLI. tmux-resurrect restores pane layout and cwd but relaunches no
# processes it doesn't whitelist — so an assistant pane comes back as a bare
# shell and the conversation is lost. These scripts close that gap:
#
#   save.sh     — resurrect post-save hook: map each pane to the assistant
#                 session ID running in it, write a JSON sidecar next to
#                 resurrect's own save files.
#   restore.sh  — resurrect post-restore hook: read the sidecar and type
#                 `claude --resume <id>` / `resume-codex.sh <id>` into the
#                 restored panes. The Codex launcher retries the UUID after a
#                 successful startup update.
#   session-track.sh / session-cleanup.sh <tool> — SessionStart/SessionEnd
#                 hooks (one script, parameterized by claude|codex) that record
#                 which session id each running claude/codex process (pid)
#                 currently has, so save.sh can map a pane to it exactly
#                 (claude method 1 / codex method 1). Claude registers both
#                 hooks; Codex registers only the tracker, so its state file is
#                 superseded by the next SessionStart (and the /tmp wipe at
#                 reboot). Codex can also still be resolved from its own state DB
#                 (codex method 3) when no hook file exists.

# Per-boot scratch dir where the SessionStart hook drops one JSON file per
# running assistant process (<tool>-<pid>.json). Deliberately ephemeral:
# macOS wipes /tmp across reboots, which doubles as a guard against stale
# pid→session mappings after PID reuse. Session IDs survive reboots via the
# sidecar in the resurrect save dir, not via these files — they only need to
# live long enough for the next save. A FIXED path (not $TMPDIR) because the
# writer (the hook, the assistant's env) and the reader (save.sh, tmux server's
# env) run in different environments that aren't guaranteed to agree on
# TMPDIR; the uid suffix keeps multi-user /tmp collision-free.
assistant_state_dir() {
	echo "${TMUX_ASSISTANT_RESURRECT_DIR:-/tmp/tmux-assistant-resurrect-$(id -u)}"
}

# Resolve tmux-resurrect's save directory the same way resurrect itself does
# (scripts/helpers.sh): the @resurrect-dir option, else the legacy
# ~/.tmux/resurrect when that directory exists, else the XDG default. Do NOT
# hardcode a path: creating ~/.tmux/resurrect as a side effect would flip
# resurrect's own dir-exists check and silently migrate its save location.
resurrect_data_dir() {
	local dir
	dir=$(tmux show-option -gqv @resurrect-dir 2>/dev/null || true)
	if [ -z "$dir" ]; then
		if [ -d "$HOME/.tmux/resurrect" ]; then
			dir="$HOME/.tmux/resurrect"
		else
			dir="${XDG_DATA_HOME:-$HOME/.local/share}/tmux/resurrect"
		fi
	fi
	echo "$dir" | sed "s,^~,$HOME,; s,\$HOME,$HOME,g"
}

sidecar_file() { echo "$(resurrect_data_dir)/assistant-sessions.json"; }

log() {
	echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*" >>"$(resurrect_data_dir)/assistant-resurrect.log"
}

# Map a process's command line to a supported assistant, by the basename of
# the first token. Claude Code's process shows as `claude --chrome ...`.
# Codex appears twice in a pane's tree: the npm wrapper (`node …/bin/codex`,
# classified via its second token) and the native child it spawns
# (`…/vendor/aarch64-apple-darwin/codex/codex`, classified via the first) —
# either match works, and both resolve session IDs the same way.
detect_tool() {
	local rest="$1" first base
	first="${rest%% *}"
	base="${first##*/}"
	case "$base" in
	node | bun)
		rest="${rest#* }"
		first="${rest%% *}"
		base="${first##*/}"
		;;
	esac
	case "$base" in
	claude) echo claude ;;
	codex | codex-*) echo codex ;;
	esac
}

# Walk up from $PPID to the assistant process and echo its pid. Hooks may be
# spawned through an intermediate shell (`sh -c '…'`), so $PPID isn't
# necessarily the assistant. Arg: the target tool (claude | codex). Returns the
# OUTERMOST matching ancestor — for codex that's the npm wrapper, not the native
# child it spawns; this is the SAME process save.sh's pane_assistant picks (the
# first match walking the pane tree downward), so the hook's <tool>-<pid>.json
# and save.sh's lookup agree on the pid. Falls back to $PPID if nothing matches.
find_agent_pid() {
	local target="$1" pid="$PPID" depth=8 comm args last=""
	while [ "$depth" -gt 0 ] && [ "$pid" -gt 1 ]; do
		comm=$(ps -o comm= -p "$pid" 2>/dev/null || true)
		args=$(ps -o args= -p "$pid" 2>/dev/null || true)
		if [ "$(detect_tool "$args")" = "$target" ] || [ "${comm##*/}" = "$target" ]; then
			last="$pid"
		elif [ -n "$last" ]; then
			break # walked past the outermost matching ancestor
		fi
		pid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ' || true)
		[ -n "$pid" ] || break
		depth=$((depth - 1))
	done
	echo "${last:-$PPID}"
}
