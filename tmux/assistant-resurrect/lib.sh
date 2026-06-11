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
#                 `claude --resume <id>` / `codex resume <id>` into the
#                 restored panes.
#   claude-session-track.sh / claude-session-cleanup.sh — Claude Code
#                 SessionStart/SessionEnd hooks that record which session ID
#                 each running `claude` process (pid) currently has. Codex
#                 needs no hook: its session→cwd mapping is read from Codex's
#                 own state DB at save time.

# Per-boot scratch dir where the Claude SessionStart hook drops one JSON file
# per running Claude process (claude-<pid>.json). Deliberately ephemeral:
# macOS wipes /tmp across reboots, which doubles as a guard against stale
# pid→session mappings after PID reuse. Session IDs survive reboots via the
# sidecar in the resurrect save dir, not via these files — they only need to
# live long enough for the next save. A FIXED path (not $TMPDIR) because the
# writer (Claude hook, claude's env) and the reader (save.sh, tmux server's
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
