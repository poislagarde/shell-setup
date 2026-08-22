#!/usr/bin/env bash
# Exercise the installed tmux-resurrect save/restore contract through the
# coordinator. Every mutation is confined to one private -L socket.

set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
PERSISTENCE=$ROOT/tmux/tmux-persistence.sh
TMUX_BIN=${TMUX_BIN:-$(command -v tmux)}
RESURRECT_SAVE=$HOME/.tmux/plugins/tmux-resurrect/scripts/save.sh
RESURRECT_RESTORE=$HOME/.tmux/plugins/tmux-resurrect/scripts/restore.sh
FAKE_ASSISTANT_SAVE=$ROOT/tmux/tests/fake-assistant-save.sh
FAKE_ASSISTANT_RESTORE=$ROOT/tmux/tests/fake-assistant-restore.sh
# Exercise the production/default-socket branch under a private TMUX_TMPDIR.
# Mutating test commands still pass -L explicitly.
SERVER=default
TEST_ROOT=$(mktemp -d /tmp/tmux-resurrect-contract.XXXXXX)
export TMUX_TMPDIR=$TEST_ROOT/socket-root
RESURRECT_DIR=$TEST_ROOT/resurrect
STATE_DIR=$TEST_ROOT/state
SERVER_PROCESS=

cleanup() {
	"$TMUX_BIN" -L "$SERVER" kill-server >/dev/null 2>&1 || true
	if [ -n "$SERVER_PROCESS" ]; then wait "$SERVER_PROCESS" 2>/dev/null || true; fi
	rm -rf -- "$TEST_ROOT"
}
trap cleanup EXIT INT TERM HUP

[ -x "$RESURRECT_SAVE" ] || { printf 'resurrect contract: SKIP (plugin missing)\n'; exit 0; }
[ -x "$RESURRECT_RESTORE" ] || { printf 'resurrect contract: SKIP (plugin missing)\n'; exit 0; }
mkdir -p "$TMUX_TMPDIR" "$RESURRECT_DIR" "$STATE_DIR" \
	"$TEST_ROOT/cwd-a" "$TEST_ROOT/cwd-b" "$TEST_ROOT/cwd-c"
unset TMUX TMUX_PANE

tmux_test() { "$TMUX_BIN" -L "$SERVER" "$@"; }

run_persistence() {
	local expected_pid expected_socket
	expected_pid=$(tmux_test display-message -p '#{pid}')
	expected_socket=$(tmux_test display-message -p '#{socket_path}')
	env -u TMUX -u TMUX_PANE \
		TMUX_TMPDIR="$TMUX_TMPDIR" \
		TMUX_PERSISTENCE_TMUX_BIN="$TMUX_BIN" \
		TMUX_PERSISTENCE_SOCKET_NAME="$SERVER" \
		TMUX_PERSISTENCE_EXPECTED_PID="$expected_pid" \
		TMUX_PERSISTENCE_EXPECTED_SOCKET="$expected_socket" \
		TMUX_PERSISTENCE_RESURRECT_DIR="$RESURRECT_DIR" \
		TMUX_PERSISTENCE_STATE_DIR="$STATE_DIR" \
		TMUX_PERSISTENCE_RESURRECT_SAVE="$RESURRECT_SAVE" \
		TMUX_PERSISTENCE_RESURRECT_RESTORE="$RESURRECT_RESTORE" \
		TMUX_PERSISTENCE_ASSISTANT_SAVE="$FAKE_ASSISTANT_SAVE" \
		TMUX_PERSISTENCE_ASSISTANT_RESTORE="$FAKE_ASSISTANT_RESTORE" \
		"$PERSISTENCE" "$@"
}

configure_server() {
	tmux_test set-option -g @resurrect-dir "$RESURRECT_DIR"
	tmux_test set-option -g @resurrect-capture-pane-contents on
	tmux_test set-option -g @resurrect-processes false
	tmux_test set-option -g @resurrect-hook-post-save-layout "$PERSISTENCE post-save-layout"
	tmux_test set-option -g @resurrect-hook-post-save-all true
	tmux_test set-option -g @resurrect-hook-pre-restore-all "$PERSISTENCE pre-restore"
	tmux_test set-option -g @resurrect-hook-post-restore-all "$PERSISTENCE post-restore"
}

tmux_test -f /dev/null new-session -d -s alpha -c "$TEST_ROOT/cwd-a"
tmux_test new-window -d -t '=alpha:' -c "$TEST_ROOT/cwd-b"
tmux_test split-window -d -t '=alpha:0' -c "$TEST_ROOT/cwd-c"
tmux_test new-session -d -s beta -c "$TEST_ROOT/cwd-b"
tmux_test send-keys -t '=alpha:0.0' "printf 'coordinator-contract-marker\\n'" Enter
sleep 0.2
configure_server
tmux_test set-option -g @shell-setup-persistence-state ready

mkdir -p "$RESURRECT_DIR/save/pane_contents"
printf 'stale-before-save\n' >"$RESURRECT_DIR/save/pane_contents/pane-stale"

expected_sessions=$(tmux_test list-sessions | wc -l | tr -d ' ')
expected_windows=$(tmux_test list-windows -a | wc -l | tr -d ' ')
expected_panes=$(tmux_test list-panes -a | wc -l | tr -d ' ')
run_persistence save --quiet

target=$(readlink "$RESURRECT_DIR/last")
generation=${target#tmux_resurrect_}
generation=${generation%.txt}
[ -f "$RESURRECT_DIR/$target" ]
[ -f "$RESURRECT_DIR/pane_contents_$generation.tar.gz" ]
[ -f "$RESURRECT_DIR/assistant_sessions_$generation.json" ]
if tar tzf "$RESURRECT_DIR/pane_contents_$generation.tar.gz" | grep -q 'pane-stale'; then
	printf 'stale save scratch leaked into the managed pane archive\n' >&2
	exit 1
fi

tmux_test kill-server
unset TMUX TMUX_PANE
"$TMUX_BIN" -L "$SERVER" -f /dev/null -D &
SERVER_PROCESS=$!
for _ in $(seq 1 100); do
	tmux_test display-message -p '#{pid}' >/dev/null 2>&1 && break
	sleep 0.05
done
tmux_test display-message -p '#{pid}' >/dev/null
configure_server
run_persistence startup

state=$(tmux_test show-option -gqv @shell-setup-persistence-state)
[ "$state" = ready ] || {
	printf 'expected verified ready state, got %s\n' "$state" >&2
	[ ! -f "$STATE_DIR/last-restore.diff" ] || cat "$STATE_DIR/last-restore.diff" >&2
	exit 1
}
[ "$(tmux_test list-sessions | wc -l | tr -d ' ')" = "$expected_sessions" ]
[ "$(tmux_test list-windows -a | wc -l | tr -d ' ')" = "$expected_windows" ]
[ "$(tmux_test list-panes -a | wc -l | tr -d ' ')" = "$expected_panes" ]
: >"$TEST_ROOT/all-panes"
while IFS= read -r pane; do
	tmux_test capture-pane -p -t "$pane" >>"$TEST_ROOT/all-panes"
done < <(tmux_test list-panes -a -F '#{pane_id}')
grep -q 'coordinator-contract-marker' "$TEST_ROOT/all-panes"

printf 'resurrect contract: OK\n'
