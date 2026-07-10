#!/usr/bin/env bash
# Assistant SessionStart hook: record "this <tool> process (pid) currently runs
# this session_id" so save.sh can map a tmux pane to a resumable session. One
# script for both assistants — the only per-agent differences are which process
# to find and the state filename — so the tool is passed as $1:
#   ~/.claude/settings.json  SessionStart -> session-track.sh claude
#   ~/.codex/hooks.json       SessionStart -> session-track.sh codex
# Both deliver the same JSON payload on stdin ({session_id, cwd, ...}); Codex's
# hook format mirrors Claude's and its session_id is the UUID `codex resume`
# takes (= threads.id). Fires on startup/resume/clear/compaction, so the state
# file always tracks the process's CURRENT session id.
#
# IMPORTANT: SessionStart hook stdout may be injected into the conversation as
# context — this script must never print to stdout.
set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/lib.sh"

TOOL="${1:-}"
case "$TOOL" in claude | codex) ;; *) exit 0 ;; esac

INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty')
[ -n "$SESSION_ID" ] || exit 0

STATE_DIR=$(assistant_state_dir)
mkdir -p -m 0700 "$STATE_DIR"

# Keep the full hook payload (cwd, ...) plus the resolved pid — save.sh only
# needs session_id, the rest helps debugging.
PID=$(find_agent_pid "$TOOL")
echo "$INPUT" | jq --argjson pid "$PID" '. + {pid: $pid}' \
	>"$STATE_DIR/$TOOL-$PID.json" 2>/dev/null || true
