#!/usr/bin/env bash
# The window-label activity aggregation, on a private tmux server: a "waiting on
# you" mark loses to a turning title spinner (the assistant is working, and only
# the title says so), and holds when the title is not spinning.

set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
REFRESH=$ROOT/tmux/status-refresh.sh
TMUX_BIN=${TMUX_BIN:-$(command -v tmux)}
TEST_ROOT=$(mktemp -d /tmp/status-refresh-test.XXXXXX)
export TMUX_TMPDIR=$TEST_ROOT/socket-root
REFRESH_PID=

cleanup() {
	[ -z "$REFRESH_PID" ] || kill "$REFRESH_PID" 2>/dev/null || true
	"$TMUX_BIN" -L default kill-server >/dev/null 2>&1 || true
	rm -rf -- "$TEST_ROOT"
}
trap cleanup EXIT INT TERM HUP

mkdir -p "$TMUX_TMPDIR"
unset TMUX TMUX_PANE

t() { "$TMUX_BIN" -L default "$@"; }

# `sleep` panes: a login shell would overwrite the titles below with its own.
t -f /dev/null new-session -d -s activity -n spinning sleep 300
t new-window -d -t '=activity:' -n asking sleep 300

mark() { # pane, title
	t select-pane -t "$1" -T "$2"
	t set -p -t "$1" @assistant-state input
	t set -p -t "$1" @assistant-state-at "$(date +%s)"
	t set -p -t "$1" @assistant-pid "$$"
	t set -p -t "$1" @assistant-pending input
}
spinning=$(t list-panes -t '=activity:spinning' -F '#{pane_id}')
asking=$(t list-panes -t '=activity:asking' -F '#{pane_id}')
mark "$spinning" '⠹ working'
mark "$asking" '[ ! ] Action Required | project'

"$REFRESH" &
REFRESH_PID=$!
sleep 3

check() { # what, expected, actual
	[ "$2" = "$3" ] || { printf '%s: expected %s, got %s\n' "$1" "${2:-<unset>}" "${3:-<unset>}" >&2; exit 1; }
}
check 'spinning window' busy "$(t display-message -p -t '=activity:spinning' '#{@assistant-window}')"
check 'spinning pane state' busy "$(t show-options -pqv -t "$spinning" @assistant-state)"
check 'spinning pane mark' '' "$(t show-options -pqv -t "$spinning" @assistant-pending)"
check 'asking window' input "$(t display-message -p -t '=activity:asking' '#{@assistant-window}')"
check 'asking pane state' input "$(t show-options -pqv -t "$asking" @assistant-state)"
check 'asking pane mark' input "$(t show-options -pqv -t "$asking" @assistant-pending)"

printf 'status refresh: OK\n'
