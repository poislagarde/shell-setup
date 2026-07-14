#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ASSISTANT_RESURRECT_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
FAKE_BIN="$SCRIPT_DIR/fake-bin"
SERVER="assistant-resurrect-test-$$"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/assistant-restore-test.XXXXXX")

cleanup() {
	tmux -L "$SERVER" kill-server >/dev/null 2>&1 || true
	rm -rf "$TMP"
}
trap cleanup EXIT

SID_UPDATE=019f5d76-6fe2-7d93-aa8c-62c0bf6e7900
SID_EXTERNAL=019f5d76-6fe2-7d93-aa8c-62c0bf6e7901
mkdir -p "$TMP/resurrect" "$TMP/state"
printf '%s\n' 'codex-cli 1.0.0' >"$TMP/update-version"
printf '%s\n' 'codex-cli 1.0.0' >"$TMP/external-version"
: >"$TMP/update-calls"
: >"$TMP/external-calls"

jq -n --arg update "$SID_UPDATE" --arg external "$SID_EXTERNAL" \
	'[
		{pane:"restore-test:0.0",tool:"codex",session_id:$update,cwd:"/tmp"},
		{pane:"restore-test:1.0",tool:"codex",session_id:$external,cwd:"/tmp"}
	]' \
	>"$TMP/resurrect/assistant-sessions.json"

update_command="env PATH=$FAKE_BIN:$PATH FAKE_CODEX_MODE=update FAKE_CODEX_VERSION_FILE=$TMP/update-version FAKE_CODEX_CALLS_FILE=$TMP/update-calls FAKE_CODEX_UPDATED_FILE=$TMP/updated TMUX_ASSISTANT_RESURRECT_DIR=$TMP/state /bin/bash --noprofile --norc"
external_command="env PATH=$FAKE_BIN:$PATH FAKE_CODEX_MODE=external-update FAKE_CODEX_VERSION_FILE=$TMP/external-version FAKE_CODEX_CALLS_FILE=$TMP/external-calls FAKE_CODEX_UPDATED_FILE=$TMP/external-updated TMUX_ASSISTANT_RESURRECT_DIR=$TMP/state /bin/bash --noprofile --norc"

tmux -L "$SERVER" -f /dev/null new-session -d -s restore-test "$update_command"
tmux -L "$SERVER" new-window -d -t '=restore-test:' "$external_command"
tmux -L "$SERVER" set-option -g @resurrect-dir "$TMP/resurrect"
tmux -L "$SERVER" send-keys -t '=restore-test:0.0' \
	"$ASSISTANT_RESURRECT_DIR/restore.sh" Enter

for _ in {1..100}; do
	update_count=$(wc -l <"$TMP/update-calls" | tr -d ' ')
	external_count=$(wc -l <"$TMP/external-calls" | tr -d ' ')
	[ "$update_count" -eq 2 ] && [ "$external_count" -eq 1 ] && break
	sleep 0.05
done

update_count=$(wc -l <"$TMP/update-calls" | tr -d ' ')
[ "$update_count" -eq 2 ] || {
	echo "expected two Codex launches after restore-time update, got $update_count" >&2
	tmux -L "$SERVER" capture-pane -p -t '=restore-test:0.0' >&2
	exit 1
}

external_count=$(wc -l <"$TMP/external-calls" | tr -d ' ')
[ "$external_count" -eq 1 ] || {
	echo "another pane's version change caused $external_count launches" >&2
	tmux -L "$SERVER" capture-pane -p -t '=restore-test:1.0' >&2
	exit 1
}

awk -v expected="resume $SID_UPDATE" '$0 != expected { exit 1 }' "$TMP/update-calls" || {
	echo "restore did not preserve the exact Codex session ID" >&2
	exit 1
}

awk -v expected="resume $SID_EXTERNAL" '$0 != expected { exit 1 }' "$TMP/external-calls" || {
	echo "restore changed the external-update session ID" >&2
	exit 1
}

echo "assistant restore: OK"
