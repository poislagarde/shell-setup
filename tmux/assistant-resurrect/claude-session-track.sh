#!/usr/bin/env bash
# Claude Code SessionStart hook: record "this claude process (pid) currently
# runs this session_id" so save.sh can map tmux panes to resumable sessions.
# Registered in ~/.claude/settings.json under hooks.SessionStart; fires on
# startup, --resume, /clear and compaction, so the state file always tracks
# the process's CURRENT session id (a /clear mints a new one). Stdin is JSON:
# {session_id, cwd, transcript_path, source, ...}.
#
# IMPORTANT: SessionStart hook stdout is injected into the conversation as
# context — this script must never print to stdout.
set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/lib.sh"

# Hooks may be spawned through an intermediate shell (`sh -c 'bash hook.sh'`),
# so $PPID isn't necessarily the claude process — walk up the tree until the
# command (or argv[0] basename, for safety) is `claude`. Falls back to $PPID.
find_claude_pid() {
	local pid="$PPID" depth=5 name args first
	while [ "$depth" -gt 0 ] && [ "$pid" -gt 1 ]; do
		name=$(ps -o comm= -p "$pid" 2>/dev/null || true)
		args=$(ps -o args= -p "$pid" 2>/dev/null || true)
		first="${args%% *}"
		if [ "${name##*/}" = "claude" ] || [ "${first##*/}" = "claude" ]; then
			echo "$pid"
			return
		fi
		pid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ' || true)
		[ -n "$pid" ] || break
		depth=$((depth - 1))
	done
	echo "$PPID"
}

INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty')
[ -n "$SESSION_ID" ] || exit 0

STATE_DIR=$(assistant_state_dir)
mkdir -p -m 0700 "$STATE_DIR"

# Keep the full hook payload (cwd, transcript_path, ...) plus the resolved
# pid — save.sh only needs session_id, the rest helps debugging.
CLAUDE_PID=$(find_claude_pid)
echo "$INPUT" | jq --argjson pid "$CLAUDE_PID" '. + {pid: $pid}' \
	>"$STATE_DIR/claude-$CLAUDE_PID.json" 2>/dev/null || true
