#!/usr/bin/env bash
# Claude Code SessionEnd hook: drop the state file written by
# claude-session-track.sh when a claude process exits. Prevents a later
# process that happens to reuse the pid from being mapped to a dead session
# (the $TMPDIR wipe on reboot covers the cross-boot case; this covers
# within-boot reuse). Registered under hooks.SessionEnd.
set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/lib.sh"

# Same ancestry walk as the track hook so both resolve the same pid.
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

rm -f "$(assistant_state_dir)/claude-$(find_claude_pid).json"
