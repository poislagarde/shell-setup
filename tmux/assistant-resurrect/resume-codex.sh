#!/usr/bin/env bash
# Resume one Codex session. If Codex updates itself before opening the thread,
# retry the same UUID once with the newly installed binary.
set -u

SID="${1:-}"
if [[ ! "$SID" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]]; then
	echo "usage: ${0##*/} <session-id>" >&2
	exit 2
fi

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/lib.sh"

CODEX_BIN=$(command -v codex) || {
	echo "codex: command not found" >&2
	exit 127
}

# Capture this pane's raw output without changing its TTY. Codex's updater exits
# with the same status as a normal quit, and another restored pane can replace
# the shared binary, so both the local success message and a version change are
# required before retrying.
STATE_DIR=$(assistant_state_dir)
mkdir -p -m 0700 "$STATE_DIR"
TOKEN="$$-${RANDOM:-0}"
CAPTURE_FILE="$STATE_DIR/resume-codex-$TOKEN.output"
PIPE_STARTED=0
rm -f "$CAPTURE_FILE"

stop_capture() {
	local _
	[ "$PIPE_STARTED" -eq 1 ] || return 0
	tmux pipe-pane -t "$TMUX_PANE" >/dev/null 2>&1 || true
	PIPE_STARTED=0
	for _ in {1..50}; do
		[ -e "$CAPTURE_FILE" ] && return 0
		sleep 0.01
	done
}

cleanup() {
	stop_capture
	rm -f "$CAPTURE_FILE"
}
trap cleanup EXIT

VERSION_BEFORE=$("$CODEX_BIN" --version 2>/dev/null || true)

if [ -n "${TMUX_PANE:-}" ] &&
	[ "$(tmux display-message -p -t "$TMUX_PANE" '#{pane_pipe}' 2>/dev/null || true)" = 0 ]; then
	printf -v PIPE_COMMAND '%q %q' \
		"$SCRIPT_DIR/detect-codex-update.pl" "$CAPTURE_FILE"
	if tmux pipe-pane -o -t "$TMUX_PANE" "$PIPE_COMMAND" 2>/dev/null; then
		PIPE_STARTED=1
	fi
fi

"$CODEX_BIN" resume "$SID"
STATUS=$?
stop_capture
VERSION_AFTER=$("$CODEX_BIN" --version 2>/dev/null || true)

if [ "$STATUS" -eq 0 ] &&
	[ -n "$VERSION_BEFORE" ] &&
	[ -n "$VERSION_AFTER" ] &&
	[ "$VERSION_BEFORE" != "$VERSION_AFTER" ] &&
	[ -f "$CAPTURE_FILE" ]; then
	printf 'Codex updated (%s -> %s); resuming session %s...\n' \
		"$VERSION_BEFORE" "$VERSION_AFTER" "$SID"
	cleanup
	trap - EXIT
	exec "$CODEX_BIN" resume "$SID"
fi

exit "$STATUS"
