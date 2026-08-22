#!/usr/bin/env bash

# Integration coverage for the repo-owned tmux persistence coordinator. Every
# tmux mutation in this file targets a unique -L socket under a private
# TMUX_TMPDIR; the default server is never addressed.

set -uo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
REAL_HOME=$HOME
PERSISTENCE=$ROOT/tmux/tmux-persistence.sh
SERVER_AGENT=$ROOT/tmux/tmux-server-agent.sh
TMUX_CONFIG=$ROOT/tmux/tmux.conf
ZSH_CONFIG=$ROOT/zsh/zshrc
BOOTSTRAP=$ROOT/.claude/commands/shell-setup.md
TMUX_BIN=${TMUX_BIN:-$(command -v tmux)}
TEST_ROOT=$(mktemp -d /tmp/tmux-persist.XXXXXX)
export TMUX_TMPDIR=$TEST_ROOT/s
export PERSISTENCE_UNDER_TEST=$PERSISTENCE
export FAKE_RESURRECT_SAVE=$ROOT/tmux/tests/fake-resurrect-save.sh
export FAKE_ASSISTANT_SAVE=$ROOT/tmux/tests/fake-assistant-save.sh
export FAKE_RESURRECT_RESTORE=$ROOT/tmux/tests/fake-resurrect-restore.sh
export FAKE_ASSISTANT_RESTORE=$ROOT/tmux/tests/fake-assistant-restore.sh
mkdir -p "$TMUX_TMPDIR" "$TEST_ROOT/home" "$TEST_ROOT/archive-source"
printf 'pane output\n' >"$TEST_ROOT/archive-source/pane.txt"
export FAKE_ARCHIVE_SOURCE=$TEST_ROOT/archive-source

failures=0
tests=0

cleanup() {
	local socket_dir socket_path socket_name
	socket_dir=$TMUX_TMPDIR/tmux-$(id -u)
	if [ -d "$socket_dir" ]; then
		for socket_path in "$socket_dir"/*; do
			[ -e "$socket_path" ] || continue
			socket_name=${socket_path##*/}
			"$TMUX_BIN" -L "$socket_name" kill-server >/dev/null 2>&1 || true
		done
	fi
	if [ -n "$TEST_ROOT" ] && [ -d "$TEST_ROOT" ]; then
		rm -rf -- "$TEST_ROOT"
	fi
}
trap cleanup EXIT INT TERM HUP

fail() {
	printf '    %s\n' "$*" >&2
	exit 1
}

assert_eq() {
	local expected=$1 actual=$2 message=${3:-values differ}
	[ "$actual" = "$expected" ] || fail "$message (expected '$expected', got '$actual')"
}

assert_file() {
	[ -f "$1" ] || fail "expected file: $1"
}

assert_not_file() {
	[ ! -e "$1" ] && [ ! -L "$1" ] || fail "unexpected file: $1"
}

assert_socket() {
	[ -S "$1" ] || fail "expected socket: $1"
}

assert_contains() {
	local file=$1 pattern=$2
	grep -Eq "$pattern" "$file" || fail "$file does not contain: $pattern"
}

assert_not_contains() {
	local file=$1 pattern=$2
	if grep -Eq "$pattern" "$file"; then
		fail "$file unexpectedly contains: $pattern"
	fi
}

run_test() {
	local name=$1 status
	shift
	tests=$((tests + 1))
	set +e
	(
		set -e
		"$@"
	)
	status=$?
	set -e
	if [ "$status" -eq 0 ]; then
		printf 'ok %d - %s\n' "$tests" "$name"
	else
		printf 'not ok %d - %s\n' "$tests" "$name"
		failures=$((failures + 1))
	fi
}

new_socket_name() {
	printf 'ctp%s-%s\n' "$$" "$1"
}

start_server() {
	local socket=$1 session=${2:-test} cwd=${3:-$TEST_ROOT}
	"$TMUX_BIN" -L "$socket" -f /dev/null new-session -d -s "$session" -c "$cwd" 'sleep 300'
}

stop_server() {
	local socket=$1
	"$TMUX_BIN" -L "$socket" kill-server >/dev/null 2>&1 || true
}

run_persistence() {
	env \
		HOME="$TEST_ROOT/home" \
		TMUX_TMPDIR="$TMUX_TMPDIR" \
		TMUX_PERSISTENCE_TMUX_BIN="$TMUX_BIN" \
		TMUX_PERSISTENCE_SOCKET_NAME="$CURRENT_SOCKET" \
		TMUX_PERSISTENCE_RESURRECT_DIR="$CURRENT_RESURRECT_DIR" \
		TMUX_PERSISTENCE_STATE_DIR="$CURRENT_STATE_DIR" \
		TMUX_PERSISTENCE_RESURRECT_SAVE="$FAKE_RESURRECT_SAVE" \
		TMUX_PERSISTENCE_ASSISTANT_SAVE="$FAKE_ASSISTANT_SAVE" \
		TMUX_PERSISTENCE_RESURRECT_RESTORE="$FAKE_RESURRECT_RESTORE" \
		TMUX_PERSISTENCE_ASSISTANT_RESTORE="$FAKE_ASSISTANT_RESTORE" \
		TMUX_PERSISTENCE_LOCK_HELD="${TMUX_PERSISTENCE_LOCK_HELD:-}" \
		"$PERSISTENCE" "$@"
}

make_context() {
	local suffix=$1
	CURRENT_SOCKET=$(new_socket_name "$suffix")
	CURRENT_RESURRECT_DIR=$TEST_ROOT/resurrect-$suffix
	CURRENT_STATE_DIR=$TEST_ROOT/state-$suffix
	export CURRENT_SOCKET CURRENT_RESURRECT_DIR CURRENT_STATE_DIR
	mkdir -p "$CURRENT_RESURRECT_DIR" "$CURRENT_STATE_DIR"
}

write_layout() {
	local destination=$1 panes=$2 session=${3:-alpha} cwd=${4:-$TEST_ROOT}
	local window=${5:-1} pane=1
	: >"$destination"
	while [ "$pane" -le "$panes" ]; do
		printf 'pane\t%s\t%s\t0\t:\t%s\thost\t:%s\t1\tzsh\t:\n' \
			"$session" "$window" "$pane" "$cwd" >>"$destination"
		pane=$((pane + 1))
	done
	printf 'window\t%s\t%s\t:name\t1\t:*\tlayout\toff\n' \
		"$session" "$window" >>"$destination"
	printf 'state\t%s\t\n' "$session" >>"$destination"
}

write_exact_layout_for_server() {
	local socket=$1 destination=$2 row session window pane cwd
	row=$("$TMUX_BIN" -L "$socket" list-panes -a \
		-F $'#{session_name}\t#{window_index}\t#{pane_index}\t#{pane_current_path}')
	IFS=$'\t' read -r session window pane cwd <<<"$row"
	write_layout "$destination" 1 "$session" "$cwd" "$window"
	# write_layout starts pane indexes at 1; replace that field with the exact
	# isolated server index so a non-default pane-base-index is covered too.
	awk -F '\t' -v OFS='\t' -v pane="$pane" '$1 == "pane" { $6 = pane } { print }' \
		"$destination" >"$destination.tmp"
	mv -f "$destination.tmp" "$destination"
}

make_archive() {
	local destination=$1
	tar -czf "$destination" -C "$FAKE_ARCHIVE_SOURCE" .
}

make_complete_generation() {
	local dir=$1 base=$2 panes=${3:-1} cwd=${4:-$TEST_ROOT} generation
	generation=${base#tmux_resurrect_}
	generation=${generation%.txt}
	write_layout "$dir/$base" "$panes" alpha "$cwd"
	make_archive "$dir/pane_contents_$generation.tar.gz"
	printf '[]\n' >"$dir/assistant_sessions_$generation.json"
}

make_complete_exact_generation() {
	local dir=$1 base=$2 socket=$3 generation
	generation=${base#tmux_resurrect_}
	generation=${generation%.txt}
	write_exact_layout_for_server "$socket" "$dir/$base"
	make_archive "$dir/pane_contents_$generation.tar.gz"
	printf '[]\n' >"$dir/assistant_sessions_$generation.json"
}

test_config_wiring() {
	local preflight_line approval_line activation_line config_link_line config_source_line
	bash -n "$PERSISTENCE"
	bash -n "$ROOT/tmux/tmux-server-agent.sh"
	zsh -n "$ZSH_CONFIG"
	assert_contains "$TMUX_CONFIG" "@plugin ['\"]tmux-plugins/tmux-resurrect['\"]"
	assert_not_contains "$TMUX_CONFIG" "@plugin ['\"]tmux-plugins/tmux-continuum['\"]"
	assert_not_contains "$TMUX_CONFIG" 'continuum_save\.sh|continuum_restore\.sh'
	assert_not_contains "$TMUX_CONFIG" "@continuum-restore[[:space:]]+['\"]?on"
	assert_contains "$TMUX_CONFIG" "client-detached.*tmux-persistence\.sh save --quiet --coalesce"
	assert_contains "$TMUX_CONFIG" "@resurrect-hook-post-save-layout.*tmux-persistence\.sh post-save-layout"
	assert_contains "$TMUX_CONFIG" "@resurrect-hook-pre-restore-all.*tmux-persistence\.sh pre-restore"
	assert_contains "$TMUX_CONFIG" "@resurrect-hook-post-restore-all.*tmux-persistence\.sh post-restore"
	assert_contains "$TMUX_CONFIG" "bind(-key)? C-s run-shell -b.*tmux-persistence\.sh save"
	assert_contains "$TMUX_CONFIG" "bind(-key)? C-r run-shell -b.*tmux-persistence\.sh restore"
	assert_contains "$PERSISTENCE" 'TMUX_BIN.*-N -L.*TMUX_PERSISTENCE_SOCKET_NAME'
	assert_contains "$PERSISTENCE" 'F_FULLFSYNC'
	assert_contains "$ZSH_CONFIG" 'tmux-persistence\.sh.*client-ready|"\$_tmux_persistence" client-ready'
	assert_contains "$ZSH_CONFIG" '"\$_tmux_persistence" claim "\$_tmux_kind" "\$\$"'
	assert_contains "$BOOTSTRAP" 'TMUX_PERSISTENCE_MIGRATION_APPROVAL.*_tmux_review_token'
	assert_contains "$BOOTSTRAP" '_tmux_activation_token.*_tmux_review_token'
	assert_contains "$BOOTSTRAP" "printf '%s:%s"
	preflight_line=$(grep -n '_tmux_initial_phase=' "$BOOTSTRAP" | head -n 1 | cut -d: -f1)
	approval_line=$(grep -n 'TMUX_PERSISTENCE_MIGRATION_APPROVAL:-' "$BOOTSTRAP" | head -n 1 | cut -d: -f1)
	activation_line=$(grep -n '_tmux_activation_token=' "$BOOTSTRAP" | head -n 1 | cut -d: -f1)
	config_link_line=$(grep -n 'ln -sfn.*tmux/tmux.conf.*~/\.tmux.conf' "$BOOTSTRAP" | head -n 1 | cut -d: -f1)
	config_source_line=$(grep -n '_tmux_default source-file ~/\.tmux.conf' "$BOOTSTRAP" | head -n 1 | cut -d: -f1)
	[ "$preflight_line" -lt "$config_link_line" ] || fail 'bootstrap changes tmux.conf before inspecting live persistence state'
	[ "$approval_line" -lt "$config_link_line" ] || fail 'bootstrap changes tmux.conf before migration approval'
	[ "$activation_line" -lt "$config_link_line" ] || fail 'bootstrap changes tmux.conf before rechecking the approved topology'
	[ "$config_source_line" -gt "$config_link_line" ] || fail 'bootstrap sources tmux.conf before its guarded activation phase'
	assert_contains "$ZSH_CONFIG" 'tmux -N -L default attach-session'
}

test_loaded_config_bindings_and_warning() {
	local socket home key_table save_binding= restore_binding= detach_hook rendered i=0
	socket=$(new_socket_name loaded-config)
	home=$TEST_ROOT/config-home
	mkdir -p "$home/.shell-setup" "$home/.tmux/plugins"
	ln -s "$ROOT/tmux/pane-border-format.conf" "$home/.shell-setup/pane-border-format.conf"
	ln -s "$ROOT/tmux/status-refresh.sh" "$home/.shell-setup/status-refresh.sh"
	ln -s "$ROOT/tmux/tmux-persistence.sh" "$home/.shell-setup/tmux-persistence.sh"
	ln -s "$ROOT/tmux/assistant-resurrect" "$home/.shell-setup/assistant-resurrect"
	ln -s "$ROOT/tmux/assistant-activity" "$home/.shell-setup/assistant-activity"
	ln -s "$REAL_HOME/.tmux/plugins/tpm" "$home/.tmux/plugins/tpm"
	ln -s "$REAL_HOME/.tmux/plugins/tmux-resurrect" "$home/.tmux/plugins/tmux-resurrect"

	env HOME="$home" TMUX_TMPDIR="$TMUX_TMPDIR" \
		"$TMUX_BIN" -L "$socket" -f "$TMUX_CONFIG" new-session -d -s loaded 'sleep 300'
	# run-shell jobs queued while tmux parses its config finish asynchronously
	# from the client that created the server. Wait for the TPM-plus-overlay job
	# to settle, then assert that its final bindings are the guarded ones.
	while [ "$i" -lt 100 ]; do
		key_table=$("$TMUX_BIN" -L "$socket" list-keys -T prefix)
		save_binding=$(printf '%s\n' "$key_table" | awk '$1 == "bind-key" && $2 == "-T" && $3 == "prefix" && $4 == "C-s"')
		restore_binding=$(printf '%s\n' "$key_table" | awk '$1 == "bind-key" && $2 == "-T" && $3 == "prefix" && $4 == "C-r"')
		case "$save_binding:$restore_binding" in
		*'tmux-persistence.sh save'*:*'tmux-persistence.sh restore'*) break ;;
		esac
		sleep 0.02
		i=$((i + 1))
	done
	detach_hook=$("$TMUX_BIN" -L "$socket" show-hooks -g client-detached)
	case "$save_binding" in *'run-shell -b'*'tmux-persistence.sh save'*) ;; *) fail 'TPM overwrote the background guarded C-s binding' ;; esac
	case "$restore_binding" in *'run-shell -b'*'tmux-persistence.sh restore'*) ;; *) fail 'TPM overwrote the background guarded C-r binding' ;; esac
	case "$detach_hook" in *'tmux-persistence.sh save --quiet --coalesce'*) ;; *) fail 'detach bypasses explicit save coalescing' ;; esac
	"$TMUX_BIN" -L "$socket" set-option -g @shell-setup-persistence-warning 'SAVES PAUSED'
	rendered=$("$TMUX_BIN" -L "$socket" display-message -p '#{E:status-left}')
	case "$rendered" in *'SAVES PAUSED'*) ;; *) fail 'persistence warning is not rendered in the status line' ;; esac
	stop_server "$socket"
}

test_bounded_readiness_and_no_start() {
	local socket_dir waiter status_file stderr_file i strict_status
	local foreign_root foreign_socket foreign_pid canonical_socket
	make_context readiness-missing
	socket_dir=$TMUX_TMPDIR/tmux-$(id -u)
	export TMUX_PERSISTENCE_READY_ATTEMPTS=3
	export TMUX_PERSISTENCE_READY_DELAY=0.01
	for i in 1 2 3; do
		status_file=$TEST_ROOT/missing-status-$i
		stderr_file=$TEST_ROOT/missing-stderr-$i
		(
			if run_persistence client-ready 2>"$stderr_file"; then
				printf '0\n' >"$status_file"
			else
				printf '%s\n' "$?" >"$status_file"
			fi
		) &
	done
	wait
	for i in 1 2 3; do
		status=$(<"$TEST_ROOT/missing-status-$i")
		[ "$status" -ne 0 ] || fail "missing-server waiter $i unexpectedly succeeded"
		assert_contains "$TEST_ROOT/missing-stderr-$i" 'continuing in a plain shell'
	done
	assert_not_file "$socket_dir/$CURRENT_SOCKET"

	make_context readiness-live
	start_server "$CURRENT_SOCKET"
	export TMUX_PERSISTENCE_READY_ATTEMPTS=100
	export TMUX_PERSISTENCE_READY_DELAY=0.01
	for i in 1 2 3; do
		status_file=$TEST_ROOT/live-status-$i
		(
			if run_persistence client-ready >/dev/null 2>&1; then
				printf '0\n' >"$status_file"
			else
				printf '%s\n' "$?" >"$status_file"
			fi
		) &
	done
	sleep 0.05
	"$TMUX_BIN" -L "$CURRENT_SOCKET" set-option -g @shell-setup-persistence-state ready
	wait
	for i in 1 2 3; do
		assert_eq 0 "$(<"$TEST_ROOT/live-status-$i")" "ready waiter $i failed"
	done
	assert_socket "$socket_dir/$CURRENT_SOCKET"

	"$TMUX_BIN" -L "$CURRENT_SOCKET" set-option -g @shell-setup-persistence-state degraded
	"$TMUX_BIN" -L "$CURRENT_SOCKET" set-option -g @shell-setup-persistence-client-attachable no
	if run_persistence client-ready >/dev/null 2>&1; then
		fail 'a degraded restore was attachable before completion was recorded'
	fi
	"$TMUX_BIN" -L "$CURRENT_SOCKET" set-option -g @shell-setup-persistence-client-attachable yes
	run_persistence client-ready >/dev/null
	if run_persistence wait-ready >/dev/null 2>&1; then
		fail 'strict administrative readiness accepted a degraded save gate'
	fi

	"$TMUX_BIN" -L "$CURRENT_SOCKET" set-option -g @shell-setup-persistence-state booting
	export TMUX_PERSISTENCE_ADMIN_READY_ATTEMPTS=100
	(
		if run_persistence wait-ready >/dev/null 2>&1; then
			printf '0\n' >"$TEST_ROOT/strict-ready-status"
		else
			printf '%s\n' "$?" >"$TEST_ROOT/strict-ready-status"
		fi
	) &
	waiter=$!
	sleep 0.05
	"$TMUX_BIN" -L "$CURRENT_SOCKET" set-option -g @shell-setup-persistence-state ready
	wait "$waiter"
	strict_status=$(<"$TEST_ROOT/strict-ready-status")
	assert_eq 0 "$strict_status" 'administrative readiness did not wait through startup'
	stop_server "$CURRENT_SOCKET"

	foreign_root=$TEST_ROOT/same-basename-foreign
	mkdir -p "$foreign_root"
	env TMUX_TMPDIR="$foreign_root" "$TMUX_BIN" -L default -f /dev/null \
		new-session -d -s foreign 'sleep 300'
	env TMUX_TMPDIR="$foreign_root" "$TMUX_BIN" -L default \
		set-option -g @shell-setup-persistence-state ready
	foreign_pid=$(env TMUX_TMPDIR="$foreign_root" "$TMUX_BIN" -L default display-message -p '#{pid}')
	foreign_socket=$(env TMUX_TMPDIR="$foreign_root" "$TMUX_BIN" -L default display-message -p '#{socket_path}')
	canonical_socket=$TEST_ROOT/same-basename-canonical/tmux-$(id -u)/default
	mkdir -p "${canonical_socket%/*}"
	if env \
		HOME="$TEST_ROOT/home" \
		TMUX="$foreign_socket,$foreign_pid,0" \
		TMUX_PERSISTENCE_TMUX_BIN="$TMUX_BIN" \
		TMUX_PERSISTENCE_CANONICAL_SOCKET_PATH="$canonical_socket" \
		TMUX_PERSISTENCE_STATE_DIR="$TEST_ROOT/same-basename-state" \
		TMUX_PERSISTENCE_READY_ATTEMPTS=1 \
		TMUX_PERSISTENCE_READY_DELAY=0.01 \
		"$PERSISTENCE" client-ready >/dev/null 2>&1; then
		fail 'an inherited foreign socket named default bypassed canonical socket targeting'
	fi
	assert_eq ready "$(env TMUX_TMPDIR="$foreign_root" "$TMUX_BIN" -L default \
		show-option -gqv @shell-setup-persistence-state)" \
		'canonical socket probe mutated the inherited foreign server'
	env TMUX_TMPDIR="$foreign_root" "$TMUX_BIN" -L default kill-server
}

test_agent_owns_startup_before_three_clients() {
	local agent_pid server_pid parent_pid foreign_pid i status_file waiter_pid name token
	local owner first_name first_token second_name second_token reused_name reused_token now
	local restore_base restore_marker restore_name restore_token restore_status
	local waiter_pids=() claim_pids=() claim_names
	make_context agent-startup
	export TMUX_PERSISTENCE_READY_ATTEMPTS=200
	export TMUX_PERSISTENCE_READY_DELAY=0.02
	env -u TMUX -u TMUX_PANE \
		HOME="$TEST_ROOT/home" \
		TMUX_TMPDIR="$TMUX_TMPDIR" \
		TMUX_PERSISTENCE_TMUX_BIN="$TMUX_BIN" \
		TMUX_PERSISTENCE_SCRIPT="$PERSISTENCE" \
		TMUX_PERSISTENCE_SOCKET_NAME="$CURRENT_SOCKET" \
		TMUX_PERSISTENCE_CONFIG=/dev/null \
		TMUX_PERSISTENCE_RESURRECT_DIR="$CURRENT_RESURRECT_DIR" \
		TMUX_PERSISTENCE_STATE_DIR="$CURRENT_STATE_DIR" \
		TMUX_PERSISTENCE_RESURRECT_SAVE="$FAKE_RESURRECT_SAVE" \
		TMUX_PERSISTENCE_ASSISTANT_SAVE="$FAKE_ASSISTANT_SAVE" \
		TMUX_PERSISTENCE_RESURRECT_RESTORE="$FAKE_RESURRECT_RESTORE" \
		TMUX_PERSISTENCE_ASSISTANT_RESTORE="$FAKE_ASSISTANT_RESTORE" \
		TMUX_PERSISTENCE_INTERVAL=300 \
		TMUX_SERVER_AGENT_LOG="$TEST_ROOT/agent-startup.log" \
		"$SERVER_AGENT" &
	agent_pid=$!

	for i in 1 2 3; do
		status_file=$TEST_ROOT/agent-waiter-status-$i
		(
			if run_persistence client-ready >/dev/null 2>&1; then
				printf '0\n' >"$status_file"
			else
				printf '%s\n' "$?" >"$status_file"
			fi
		) &
		waiter_pids+=( "$!" )
	done
	for waiter_pid in "${waiter_pids[@]}"; do wait "$waiter_pid"; done
	for i in 1 2 3; do
		assert_eq 0 "$(<"$TEST_ROOT/agent-waiter-status-$i")" \
			"startup waiter $i did not observe the verified launchd-owned server"
	done

	server_pid=$("$TMUX_BIN" -L "$CURRENT_SOCKET" display-message -p '#{pid}')
	parent_pid=$(ps -o ppid= -p "$server_pid" | tr -d ' ')
	assert_eq "$agent_pid" "$parent_pid" 'the supervisor does not own the tmux server process'
	assert_eq ready "$("$TMUX_BIN" -L "$CURRENT_SOCKET" show-option -gqv @shell-setup-persistence-state)" \
		'the launchd-owned empty startup did not become ready'

	for i in 1 2 3; do
		status_file=$TEST_ROOT/agent-claim-status-$i
		(
			if run_persistence claim regular >"$TEST_ROOT/agent-claim-$i"; then
				printf '0\n' >"$status_file"
			else
				printf '%s\n' "$?" >"$status_file"
			fi
		) &
		claim_pids+=( "$!" )
	done
	for waiter_pid in "${claim_pids[@]}"; do wait "$waiter_pid"; done
	for i in 1 2 3; do
		assert_eq 0 "$(<"$TEST_ROOT/agent-claim-status-$i")" \
			"concurrent session claim $i failed"
	done
	claim_names=$(awk -F '\t' '{ print $1 }' "$TEST_ROOT"/agent-claim-[123] | LC_ALL=C sort -u | wc -l | tr -d ' ')
	assert_eq 3 "$claim_names" 'concurrent clients claimed the same detached session'
	for i in 1 2 3; do
		IFS=$'\t' read -r name token <"$TEST_ROOT/agent-claim-$i"
		run_persistence release-claim "$name" "$token"
	done

	# A restore must not overtake the interval between a successful reservation
	# and the owning shell's attach-session call.
	restore_base=tmux_resurrect_20260101T000000-g7-000.txt
	make_complete_generation "$CURRENT_RESURRECT_DIR" "$restore_base" 1
	ln -s "$restore_base" "$CURRENT_RESURRECT_DIR/last"
	restore_marker=$TEST_ROOT/restore-during-client-claim
	export FAKE_RESTORE_MARKER=$restore_marker
	IFS=$'\t' read -r restore_name restore_token < <(run_persistence claim regular "$$")
	export TMUX_PERSISTENCE_RESTORE_CLAIM_ATTEMPTS=2
	export TMUX_PERSISTENCE_RESTORE_CLAIM_DELAY=0.01
	if run_persistence restore --quiet; then
		fail 'restore overtook a detached session reservation with a live owner'
	else
		restore_status=$?
	fi
	assert_eq 75 "$restore_status" 'pending client claim did not report a bounded restore deferral'
	assert_not_file "$restore_marker"
	run_persistence release-claim "$restore_name" "$restore_token"
	run_persistence restore --quiet
	assert_file "$restore_marker"
	"$TMUX_BIN" -L "$CURRENT_SOCKET" set-option -g @shell-setup-persistence-state ready
	"$TMUX_BIN" -L "$CURRENT_SOCKET" set-option -g @shell-setup-persistence-client-attachable yes
	unset FAKE_RESTORE_MARKER TMUX_PERSISTENCE_RESTORE_CLAIM_ATTEMPTS
	unset TMUX_PERSISTENCE_RESTORE_CLAIM_DELAY

	# A detached reservation stays exclusive while its owning shell is alive,
	# even after the short stale-owner TTL. Once the owner is gone, it is reusable.
	export TMUX_PERSISTENCE_CLAIM_TTL=1
	export TMUX_PERSISTENCE_CLAIM_MAX_TTL=30
	owner=$$
	IFS=$'\t' read -r first_name first_token < <(run_persistence claim regular "$owner")
	now=$(date +%s)
	"$TMUX_BIN" -L "$CURRENT_SOCKET" set-option -t "=$first_name:" \
		@shell-setup-client-claim-at "$((now - 2))"
	IFS=$'\t' read -r second_name second_token < <(run_persistence claim regular "$owner")
	[ "$first_name" != "$second_name" ] || fail 'a live owner lost its detached session lease'
	"$TMUX_BIN" -L "$CURRENT_SOCKET" set-option -t "=$first_name:" \
		@shell-setup-client-claim-owner 999999
	IFS=$'\t' read -r reused_name reused_token < <(run_persistence claim regular "$owner")
	assert_eq "$first_name" "$reused_name" 'a dead owner kept an expired session lease'
	run_persistence release-claim "$reused_name" "$reused_token"
	run_persistence release-claim "$second_name" "$second_token"
	unset TMUX_PERSISTENCE_CLAIM_TTL TMUX_PERSISTENCE_CLAIM_MAX_TTL

	# A closed Ghostty surface is SIGHUP'd before zsh can release its claim, so
	# the orphaned lease must lapse on the short dead-owner grace rather than the
	# full unknown-owner TTL -- otherwise every reopen mints a new session.
	export TMUX_PERSISTENCE_CLAIM_TTL=600
	export TMUX_PERSISTENCE_CLAIM_DEAD_TTL=1
	export TMUX_PERSISTENCE_CLAIM_MAX_TTL=900
	IFS=$'\t' read -r first_name first_token < <(run_persistence claim regular "$$")
	now=$(date +%s)
	"$TMUX_BIN" -L "$CURRENT_SOCKET" set-option -t "=$first_name:" \
		@shell-setup-client-claim-at "$((now - 2))"
	"$TMUX_BIN" -L "$CURRENT_SOCKET" set-option -t "=$first_name:" \
		@shell-setup-client-claim-owner 999999
	IFS=$'\t' read -r reused_name reused_token < <(run_persistence claim regular "$$")
	assert_eq "$first_name" "$reused_name" \
		'a session orphaned by a closed surface waited out the full claim TTL'
	run_persistence release-claim "$reused_name" "$reused_token"
	unset TMUX_PERSISTENCE_CLAIM_TTL TMUX_PERSISTENCE_CLAIM_DEAD_TTL
	unset TMUX_PERSISTENCE_CLAIM_MAX_TTL

	"$TMUX_BIN" -L "$CURRENT_SOCKET" new-session -d -s quick-2notes 'sleep 300'
	IFS=$'\t' read -r name token < <(run_persistence claim quick)
	assert_eq quick "$name" 'quick-2notes was incorrectly classified as a quick session'
	run_persistence release-claim "$name" "$token"

	kill -STOP "$agent_pid"
	kill -TERM "$server_pid"
	i=0
	while "$TMUX_BIN" -N -L "$CURRENT_SOCKET" display-message -p '#{pid}' >/dev/null 2>&1 && \
	      [ "$i" -lt 100 ]; do
		sleep 0.02
		i=$((i + 1))
	done
	if "$TMUX_BIN" -N -L "$CURRENT_SOCKET" display-message -p '#{pid}' >/dev/null 2>&1; then
		kill -CONT "$agent_pid" 2>/dev/null || true
		kill -TERM "$agent_pid" 2>/dev/null || true
		fail 'the isolated owned server did not exit for replacement test'
	fi
	"$TMUX_BIN" -L "$CURRENT_SOCKET" -f /dev/null new-session -d -s foreign 'sleep 300'
	foreign_pid=$("$TMUX_BIN" -L "$CURRENT_SOCKET" display-message -p '#{pid}')
	kill -CONT "$agent_pid"
	i=0
	while kill -0 "$agent_pid" 2>/dev/null && [ "$i" -lt 150 ]; do
		sleep 0.02
		i=$((i + 1))
	done
	if kill -0 "$agent_pid" 2>/dev/null; then
		kill -TERM "$agent_pid" 2>/dev/null || true
		stop_server "$CURRENT_SOCKET"
		fail 'the supervisor did not exit promptly after its owned server died'
	fi
	wait "$agent_pid" 2>/dev/null || true
	assert_eq "$foreign_pid" "$("$TMUX_BIN" -L "$CURRENT_SOCKET" display-message -p '#{pid}')" \
		'the supervisor killed or replaced a foreign server that reused its socket'
	assert_eq '' "$("$TMUX_BIN" -L "$CURRENT_SOCKET" show-option -gqv @shell-setup-persistence-state)" \
		'the supervisor mutated a foreign replacement server'
	stop_server "$CURRENT_SOCKET"
}

test_exact_topology_and_cwd_verification() {
	local layout target phase actual_cwd wrong_cwd name token
	make_context exact
	mkdir -p "$TEST_ROOT/cwd-exact" "$TEST_ROOT/cwd-wrong"
	start_server "$CURRENT_SOCKET" alpha "$TEST_ROOT/cwd-exact"
	target=tmux_resurrect_20260101T000000.txt
	layout=$CURRENT_RESURRECT_DIR/$target
	write_exact_layout_for_server "$CURRENT_SOCKET" "$layout"
	ln -s "$target" "$CURRENT_RESURRECT_DIR/last"

	TMUX_PERSISTENCE_LOCK_HELD=1 run_persistence post-restore
	phase=$("$TMUX_BIN" -L "$CURRENT_SOCKET" show-option -gqv @shell-setup-persistence-state)
	assert_eq ready "$phase" 'an exact restore signature was not accepted'

	actual_cwd=$("$TMUX_BIN" -L "$CURRENT_SOCKET" list-panes -a -F '#{pane_current_path}')
	wrong_cwd=$TEST_ROOT/cwd-wrong
	awk -F '\t' -v OFS='\t' -v from=":$actual_cwd" -v to=":$wrong_cwd" \
		'$1 == "pane" && $8 == from { $8 = to } { print }' "$layout" >"$layout.tmp"
	mv -f "$layout.tmp" "$layout"
	TMUX_PERSISTENCE_LOCK_HELD=1 run_persistence post-restore
	phase=$("$TMUX_BIN" -L "$CURRENT_SOCKET" show-option -gqv @shell-setup-persistence-state)
	assert_eq ready "$phase" 'a cwd-only difference closed the structural save gate'
	assert_contains "$CURRENT_STATE_DIR/last-restore.diff" '^[-+]D[[:space:]]'

	write_exact_layout_for_server "$CURRENT_SOCKET" "$layout"
	awk -F '\t' -v OFS='\t' '$1 == "window" { $3 += 1 } $1 == "pane" { $3 += 1 } { print }' \
		"$layout" >"$layout.tmp"
	mv -f "$layout.tmp" "$layout"
	TMUX_PERSISTENCE_LOCK_HELD=1 run_persistence post-restore
	phase=$("$TMUX_BIN" -L "$CURRENT_SOCKET" show-option -gqv @shell-setup-persistence-state)
	assert_eq degraded "$phase" 'same counts with different window identities were accepted'
	if run_persistence save --quiet; then
		fail 'a structurally degraded restore accepted a save without acknowledgement'
	fi
	run_persistence client-ready >/dev/null
	IFS=$'\t' read -r name token < <(run_persistence claim regular "$$")
	assert_eq alpha "$name" 'a completed degraded restore was not available to a new client'
	run_persistence release-claim "$name" "$token"
	stop_server "$CURRENT_SOCKET"
}

test_unique_generations_and_lock_coalescing() {
	local layout first second count marker i phase reserved_backup name token claim_status
	make_context saves
	start_server "$CURRENT_SOCKET"
	layout=$TEST_ROOT/save-source.txt
	write_exact_layout_for_server "$CURRENT_SOCKET" "$layout"
	export FAKE_LAYOUT_SOURCE=$layout
	export FAKE_SAVE_DELAY=0
	mkdir -p "$CURRENT_RESURRECT_DIR/save/pane_contents"
	printf 'stale\n' >"$CURRENT_RESURRECT_DIR/save/pane_contents/pane-stale"
	export FAKE_ASSERT_EMPTY_SAVE_SCRATCH=yes
	unset FAKE_SAVE_MARKER
	reserved_backup=$CURRENT_RESURRECT_DIR/.shell-setup-pane-backup.tar.gz
	mkdir "$reserved_backup"
	if run_persistence save --seed --quiet; then
		fail 'a reserved save-backup directory was accepted as a file target'
	fi
	rmdir "$reserved_backup"
	mkdir "$CURRENT_RESURRECT_DIR/pane_contents.tar.gz"
	if run_persistence save --seed --quiet; then
		fail 'a singleton sidecar directory was accepted as a save source'
	fi
	rmdir "$CURRENT_RESURRECT_DIR/pane_contents.tar.gz"

	if run_persistence save --quiet; then
		fail 'an unverified server accepted an ordinary save'
	fi
	run_persistence save --seed --quiet
	phase=$("$TMUX_BIN" -L "$CURRENT_SOCKET" show-option -gqv @shell-setup-persistence-state)
	assert_eq ready "$phase" 'an explicit migration seed did not open the save gate'
	run_persistence validate-current >/dev/null
	unset FAKE_ASSERT_EMPTY_SAVE_SCRATCH
	first=$(readlink "$CURRENT_RESURRECT_DIR/last")
	run_persistence save --quiet
	second=$(readlink "$CURRENT_RESURRECT_DIR/last")
	[ "$first" != "$second" ] || fail 'two saves in one second reused a generation name'
	[[ "$first" < "$second" ]] || fail 'generation names do not preserve publication order'
	for target in "$first" "$second"; do
		assert_file "$CURRENT_RESURRECT_DIR/$target"
		target=${target#tmux_resurrect_}
		target=${target%.txt}
		assert_file "$CURRENT_RESURRECT_DIR/pane_contents_$target.tar.gz"
		assert_file "$CURRENT_RESURRECT_DIR/assistant_sessions_$target.json"
	done

	marker=$TEST_ROOT/save-started
	export FAKE_SAVE_MARKER=$marker
	export FAKE_SAVE_DELAY=0.5
	run_persistence save --quiet &
	first=$!
	i=0
	while [ ! -f "$marker" ] && [ "$i" -lt 100 ]; do
		sleep 0.01
		i=$((i + 1))
	done
	assert_file "$marker"
	run_persistence save --quiet --coalesce
	wait "$first"
	count=$(find "$CURRENT_RESURRECT_DIR" -maxdepth 1 -type f \
		-name 'tmux_resurrect_*-g*-???.txt' | wc -l | tr -d ' ')
	assert_eq 3 "$count" 'an explicit detach-style save did not coalesce under the lock'

	rm -f "$marker"
	run_persistence save --quiet &
	first=$!
	i=0
	while [ ! -f "$marker" ] && [ "$i" -lt 100 ]; do
		sleep 0.01
		i=$((i + 1))
	done
	assert_file "$marker"
	export TMUX_PERSISTENCE_CLAIM_LOCK_TIMEOUT=0
	if run_persistence claim regular "$$" >/dev/null; then
		fail 'a client reservation ignored its bounded persistence-lock wait'
	else
		claim_status=$?
	fi
	assert_eq 75 "$claim_status" 'claim contention did not retain the lock-timeout status'
	export TMUX_PERSISTENCE_CLAIM_LOCK_TIMEOUT=2
	IFS=$'\t' read -r name token < <(run_persistence claim regular "$$")
	wait "$first"
	run_persistence release-claim "$name" "$token"
	unset TMUX_PERSISTENCE_CLAIM_LOCK_TIMEOUT

	rm -f "$marker"
	run_persistence save --quiet &
	first=$!
	i=0
	while [ ! -f "$marker" ] && [ "$i" -lt 100 ]; do
		sleep 0.01
		i=$((i + 1))
	done
	assert_file "$marker"
	run_persistence save --quiet
	wait "$first"
	count=$(find "$CURRENT_RESURRECT_DIR" -maxdepth 1 -type f \
		-name 'tmux_resurrect_*-g*-???.txt' | wc -l | tr -d ' ')
	assert_eq 6 "$count" 'a scheduler-style quiet save was dropped under lock contention'
	stop_server "$CURRENT_SOCKET"
}

test_failed_last_commit_retains_transaction() {
	local layout journal
	make_context failed-last
	start_server "$CURRENT_SOCKET"
	"$TMUX_BIN" -L "$CURRENT_SOCKET" set-option -g @shell-setup-persistence-state ready
	layout=$TEST_ROOT/failed-last-source.txt
	write_exact_layout_for_server "$CURRENT_SOCKET" "$layout"
	export FAKE_LAYOUT_SOURCE=$layout
	export FAKE_SAVE_DELAY=0
	unset FAKE_SAVE_MARKER
	mkdir "$CURRENT_RESURRECT_DIR/last"
	if run_persistence save --quiet; then
		fail 'save unexpectedly committed through a corrupt last directory'
	fi
	journal=$CURRENT_RESURRECT_DIR/.shell-setup-save-transaction
	assert_file "$journal"
	rmdir "$CURRENT_RESURRECT_DIR/last"
	run_persistence save --quiet
	assert_not_file "$journal"
	run_persistence validate-current >/dev/null
	stop_server "$CURRENT_SOCKET"
}

test_interrupted_raw_layout_is_not_promoted() {
	local layout phase marker
	make_context killed-raw
	start_server "$CURRENT_SOCKET"
	"$TMUX_BIN" -L "$CURRENT_SOCKET" set-option -g @shell-setup-persistence-state ready
	layout=$TEST_ROOT/killed-raw-source.txt
	write_exact_layout_for_server "$CURRENT_SOCKET" "$layout"
	write_exact_layout_for_server "$CURRENT_SOCKET" \
		"$CURRENT_RESURRECT_DIR/tmux_resurrect_uncommitted-older.txt"
	export FAKE_LAYOUT_SOURCE=$layout
	export FAKE_SAVE_DELAY=0
	export FAKE_KILL_COORDINATOR_AFTER_CANDIDATE=yes
	if run_persistence save --quiet; then
		fail 'a coordinator killed during raw publication reported success'
	fi
	unset FAKE_KILL_COORDINATOR_AFTER_CANDIDATE
	assert_file "$CURRENT_RESURRECT_DIR/.shell-setup-save-transaction"
	assert_file "$CURRENT_RESURRECT_DIR/tmux_resurrect_fake.txt"

	run_persistence prune
	assert_not_file "$CURRENT_RESURRECT_DIR/.shell-setup-save-transaction"
	assert_not_file "$CURRENT_RESURRECT_DIR/last"
	marker=$TEST_ROOT/killed-raw-restore-called
	export FAKE_RESTORE_MARKER=$marker
	run_persistence restore --quiet
	phase=$("$TMUX_BIN" -L "$CURRENT_SOCKET" show-option -gqv @shell-setup-persistence-state)
	assert_eq needs-review "$phase" 'an uncommitted raw layout was accepted after transaction recovery'
	assert_not_file "$marker"
	stop_server "$CURRENT_SOCKET"
}

test_interrupted_published_generation_is_recovered() {
	local layout journal selected
	make_context killed-published
	start_server "$CURRENT_SOCKET"
	"$TMUX_BIN" -L "$CURRENT_SOCKET" set-option -g @shell-setup-persistence-state ready
	layout=$TEST_ROOT/killed-published-source.txt
	write_exact_layout_for_server "$CURRENT_SOCKET" "$layout"
	export FAKE_LAYOUT_SOURCE=$layout
	export FAKE_SAVE_DELAY=0
	export TMUX_PERSISTENCE_TEST_KILL_AFTER_PUBLISH_RENAMES=yes
	if run_persistence save --quiet; then
		fail 'a coordinator killed before the publication barrier reported success'
	fi
	unset TMUX_PERSISTENCE_TEST_KILL_AFTER_PUBLISH_RENAMES
	journal=$CURRENT_RESURRECT_DIR/.shell-setup-save-transaction
	assert_file "$journal"
	run_persistence prune
	assert_not_file "$journal"
	selected=$(readlink "$CURRENT_RESURRECT_DIR/last")
	case "$selected" in
	tmux_resurrect_*-g*-???.txt) ;;
	*) fail "interrupted complete generation was not recovered: $selected" ;;
	esac
	run_persistence validate-current >/dev/null
	stop_server "$CURRENT_SOCKET"
}

test_poisoned_and_incomplete_candidates() {
	local previous poison orphan incomplete selected phase marker empty legacy
	make_context candidates
	start_server "$CURRENT_SOCKET"
	previous=tmux_resurrect_20260101T000000-g1-000.txt
	orphan=tmux_resurrect_20260101T000050.txt
	poison=tmux_resurrect_20260101T000100-g1-000.txt
	make_complete_generation "$CURRENT_RESURRECT_DIR" "$previous" 9
	write_layout "$CURRENT_RESURRECT_DIR/$orphan" 1
	make_complete_generation "$CURRENT_RESURRECT_DIR" "$poison" 1
	ln -s "$poison" "$CURRENT_RESURRECT_DIR/last"
	marker=$TEST_ROOT/restore-called
	export FAKE_RESTORE_MARKER=$marker
	run_persistence restore --quiet
	phase=$("$TMUX_BIN" -L "$CURRENT_SOCKET" show-option -gqv @shell-setup-persistence-state)
	assert_eq needs-review "$phase" 'a drastically collapsed generation restored without review'
	assert_not_file "$marker"
	assert_eq "$poison" "$(readlink "$CURRENT_RESURRECT_DIR/last")" \
		'a poisoned candidate was silently replaced instead of requiring review'
	stop_server "$CURRENT_SOCKET"

	make_context incomplete
	start_server "$CURRENT_SOCKET" alpha "$TEST_ROOT"
	previous=tmux_resurrect_20260102T000000-g1-000.txt
	incomplete=tmux_resurrect_20260102T000100-g1-000.txt
	make_complete_exact_generation "$CURRENT_RESURRECT_DIR" "$previous" "$CURRENT_SOCKET"
	write_exact_layout_for_server "$CURRENT_SOCKET" "$CURRENT_RESURRECT_DIR/$incomplete"
	make_archive "$CURRENT_RESURRECT_DIR/pane_contents_20260102T000100-g1-000.tar.gz"
	ln -s "$incomplete" "$CURRENT_RESURRECT_DIR/last"
	printf 'corrupt singleton scratch\n' >"$CURRENT_RESURRECT_DIR/pane_contents.tar.gz"
	printf 'not json\n' >"$CURRENT_RESURRECT_DIR/assistant-sessions.json"
	marker=$TEST_ROOT/incomplete-restore-called
	export FAKE_RESTORE_MARKER=$marker
	export FAKE_RESTORE_RUN_HOOKS=yes
	mkdir -p "$CURRENT_RESURRECT_DIR/restore/pane_contents"
	printf 'stale\n' >"$CURRENT_RESURRECT_DIR/restore/pane_contents/pane-stale"
	export FAKE_ASSERT_EMPTY_RESTORE_SCRATCH=yes
	run_persistence restore --quiet
	unset FAKE_ASSERT_EMPTY_RESTORE_SCRATCH
	selected=$(readlink "$CURRENT_RESURRECT_DIR/last")
	assert_eq "$previous" "$selected" 'an incomplete triplet was not repaired to the last complete one'
	assert_file "$marker"
	phase=$("$TMUX_BIN" -L "$CURRENT_SOCKET" show-option -gqv @shell-setup-persistence-state)
	assert_eq ready "$phase" 'the repaired complete generation did not verify successfully'
	stop_server "$CURRENT_SOCKET"

	make_context legacy-fallback
	start_server "$CURRENT_SOCKET" alpha "$TEST_ROOT"
	legacy=tmux_resurrect_20260104T000000.txt
	incomplete=tmux_resurrect_20260104T000100-g1-000.txt
	write_exact_layout_for_server "$CURRENT_SOCKET" "$CURRENT_RESURRECT_DIR/$legacy"
	write_exact_layout_for_server "$CURRENT_SOCKET" "$CURRENT_RESURRECT_DIR/$incomplete"
	make_archive "$CURRENT_RESURRECT_DIR/pane_contents_20260104T000100-g1-000.tar.gz"
	ln -s "$incomplete" "$CURRENT_RESURRECT_DIR/last"
	marker=$TEST_ROOT/legacy-fallback-restore-called
	export FAKE_RESTORE_MARKER=$marker
	export FAKE_RESTORE_RUN_HOOKS=yes
	run_persistence restore --quiet
	phase=$("$TMUX_BIN" -L "$CURRENT_SOCKET" show-option -gqv @shell-setup-persistence-state)
	assert_eq needs-review "$phase" 'an unpointed legacy layout bypassed explicit review'
	assert_not_file "$marker"
	selected=$(readlink "$CURRENT_RESURRECT_DIR/last")
	assert_eq "$incomplete" "$selected" 'automatic repair rewrote last to an unpointed legacy layout'
	if run_persistence client-ready >/dev/null 2>&1; then
		fail 'a not-yet-restored legacy candidate was exposed as client-ready'
	fi
	# Unkeyed layouts are not restorable at all now: their singleton sidecars
	# cannot be paired with a generation, so even an explicit last pointer goes
	# to review instead of being restored.
	rm -f "$CURRENT_RESURRECT_DIR/last"
	ln -s "$legacy" "$CURRENT_RESURRECT_DIR/last"
	run_persistence restore --quiet
	assert_not_file "$marker"
	phase=$("$TMUX_BIN" -L "$CURRENT_SOCKET" show-option -gqv @shell-setup-persistence-state)
	assert_eq needs-review "$phase" 'an explicitly pointed legacy layout was restored'
	stop_server "$CURRENT_SOCKET"

	make_context empty-layout
	start_server "$CURRENT_SOCKET" alpha "$TEST_ROOT"
	previous=tmux_resurrect_20260103T000000-g1-000.txt
	empty=tmux_resurrect_20260103T000100-g1-000.txt
	make_complete_exact_generation "$CURRENT_RESURRECT_DIR" "$previous" "$CURRENT_SOCKET"
	printf 'state\t\t\n' >"$CURRENT_RESURRECT_DIR/$empty"
	make_archive "$CURRENT_RESURRECT_DIR/pane_contents_20260103T000100-g1-000.tar.gz"
	printf '[]\n' >"$CURRENT_RESURRECT_DIR/assistant_sessions_20260103T000100-g1-000.json"
	ln -s "$empty" "$CURRENT_RESURRECT_DIR/last"
	marker=$TEST_ROOT/empty-restore-called
	export FAKE_RESTORE_MARKER=$marker
	export FAKE_RESTORE_RUN_HOOKS=no
	run_persistence restore --quiet
	selected=$(readlink "$CURRENT_RESURRECT_DIR/last")
	phase=$("$TMUX_BIN" -L "$CURRENT_SOCKET" show-option -gqv @shell-setup-persistence-state)
	assert_eq needs-review "$phase" 'an intentional empty generation bypassed review against nonempty state'
	assert_eq "$empty" "$selected" 'an intentional empty generation was silently replaced'
	assert_not_file "$marker"
	stop_server "$CURRENT_SOCKET"
}

test_assistant_map_failure_preserves_current_generation() {
	local layout current next generation save_error
	make_context assistant-required
	start_server "$CURRENT_SOCKET"
	layout=$TEST_ROOT/assistant-required-layout.txt
	write_exact_layout_for_server "$CURRENT_SOCKET" "$layout"
	export FAKE_LAYOUT_SOURCE=$layout
	export FAKE_SAVE_DELAY=0
	unset FAKE_SAVE_MARKER
	run_persistence save --seed --quiet
	current=$(readlink "$CURRENT_RESURRECT_DIR/last")
	generation=${current#tmux_resurrect_}
	generation=${generation%.txt}
	export FAKE_ASSISTANT_SAVE=/usr/bin/false
	if run_persistence save --quiet; then
		fail 'a generation committed without its required assistant-session map'
	fi
	assert_eq "$current" "$(readlink "$CURRENT_RESURRECT_DIR/last")" \
		'assistant-map failure advanced the current generation'
	assert_file "$CURRENT_RESURRECT_DIR/$current"
	assert_file "$CURRENT_RESURRECT_DIR/pane_contents_$generation.tar.gz"
	assert_file "$CURRENT_RESURRECT_DIR/assistant_sessions_$generation.json"
	save_error=$("$TMUX_BIN" -L "$CURRENT_SOCKET" show-option -gqv @shell-setup-persistence-save-error)
	case "$save_error" in
	*'assistant session mapping failed'*) ;;
	*) fail "assistant-map failure was not surfaced (got '${save_error:-empty}')" ;;
	esac

	export FAKE_ASSISTANT_SAVE=$ROOT/tmux/tests/fake-assistant-save.sh
	export FAKE_ASSISTANT_USE_REAL_LOG=yes
	"$TMUX_BIN" -L "$CURRENT_SOCKET" set-option -g @resurrect-dir "$CURRENT_RESURRECT_DIR"
	mkdir "$CURRENT_RESURRECT_DIR/assistant-resurrect.log"
	run_persistence save --quiet
	next=$(readlink "$CURRENT_RESURRECT_DIR/last")
	[ "$next" != "$current" ] || fail 'diagnostic log failure blocked a valid assistant map'
	save_error=$("$TMUX_BIN" -L "$CURRENT_SOCKET" show-option -gqv @shell-setup-persistence-save-error)
	assert_eq '' "$save_error" 'successful map capture did not clear the prior save error'
	stop_server "$CURRENT_SOCKET"
}

test_clean_recovery_skips_barrier_and_validation_creates_state() {
	local base generation fake_python marker barrier_calls
	make_context verification-workspace
	start_server "$CURRENT_SOCKET" alpha "$TEST_ROOT"
	base=tmux_resurrect_20260106T000000-g1-000.txt
	make_complete_exact_generation "$CURRENT_RESURRECT_DIR" "$base" "$CURRENT_SOCKET"
	ln -s "$base" "$CURRENT_RESURRECT_DIR/last"
	"$TMUX_BIN" -L "$CURRENT_SOCKET" set-option -g @shell-setup-persistence-state ready
	generation=${base#tmux_resurrect_}
	generation=${generation%.txt}
	fake_python=$TEST_ROOT/fake-durability-helper
	marker=$TEST_ROOT/durability-calls
	printf '%s\n' '#!/usr/bin/env bash' 'printf x >>"$FAKE_DURABILITY_MARKER"' >"$fake_python"
	chmod +x "$fake_python"
	export TMUX_PERSISTENCE_PYTHON_BIN=$fake_python
	export FAKE_DURABILITY_MARKER=$marker
	rm -rf "$CURRENT_STATE_DIR"
	run_persistence validate-current >/dev/null
	[ -d "$CURRENT_STATE_DIR" ] || fail 'validate-current did not recreate its state directory'
	assert_not_file "$marker"

	cp -p "$CURRENT_RESURRECT_DIR/pane_contents_$generation.tar.gz" \
		"$CURRENT_RESURRECT_DIR/.shell-setup-pane-backup.tar.gz"
	run_persistence prune
	barrier_calls=$(wc -c <"$marker" | tr -d ' ')
	assert_eq 1 "$barrier_calls" 'orphan backup recovery did not cross exactly one durability barrier'
	stop_server "$CURRENT_SOCKET"
}

test_split_pane_record_is_rejoined() {
	local layout base committed
	make_context split-record
	start_server "$CURRENT_SOCKET"
	layout=$TEST_ROOT/split-source.txt
	write_exact_layout_for_server "$CURRENT_SOCKET" "$layout"
	# Resurrect's ps capture prints one line per matching process, so a pane
	# whose shell has two children arrives with its record split in two.
	awk '!done && /^pane\t/ { printf "%s\n%s\n", $0, "bash resume-codex.sh 019f"; done = 1; next }
	     { print }' "$layout" >"$layout.split"
	mv -f "$layout.split" "$layout"
	grep -q '^bash resume-codex.sh 019f$' "$layout" || fail 'the fixture did not split a pane record'
	export FAKE_LAYOUT_SOURCE=$layout
	run_persistence save --seed --quiet || fail 'a split pane record failed the save'
	base=$(readlink "$CURRENT_RESURRECT_DIR/last")
	committed=$CURRENT_RESURRECT_DIR/$base
	if grep -q '^bash resume-codex.sh 019f$' "$committed"; then
		fail 'the committed layout kept the split pane record'
	fi
	grep -q 'bash resume-codex.sh 019f$' "$committed" || \
		fail 'the split command was dropped instead of rejoined'
	stop_server "$CURRENT_SOCKET"
}

test_retention_counts_complete_generations() {
	local base generation i complete_count pane_count assistant_count legacy_count protected_legacy
	make_context retention
	start_server "$CURRENT_SOCKET"
	i=1
	while [ "$i" -le 110 ]; do
		base=$(printf 'tmux_resurrect_20260101T000000-g9-%03d.txt' "$i")
		make_complete_generation "$CURRENT_RESURRECT_DIR" "$base" 1
		i=$((i + 1))
	done
	ln -s 'tmux_resurrect_20260101T000000-g9-110.txt' "$CURRENT_RESURRECT_DIR/last"

	# Newer incomplete layouts must not consume the complete-generation budget.
	i=1
	while [ "$i" -le 12 ]; do
		base=$(printf 'tmux_resurrect_20270101T000000-g8-%03d.txt' "$i")
		write_layout "$CURRENT_RESURRECT_DIR/$base" 1
		i=$((i + 1))
	done
	# Newer nonempty but corrupt triplets likewise must not evict a usable
	# recovery point from the complete-generation budget.
	i=1
	while [ "$i" -le 8 ]; do
		base=$(printf 'tmux_resurrect_20280101T000000-g7-%03d.txt' "$i")
		make_complete_generation "$CURRENT_RESURRECT_DIR" "$base" 1
		generation=${base#tmux_resurrect_}
		generation=${generation%.txt}
		if [ "$i" -le 4 ]; then
			printf 'not a gzip archive\n' >"$CURRENT_RESURRECT_DIR/pane_contents_$generation.tar.gz"
		else
			printf '{\n' >"$CURRENT_RESURRECT_DIR/assistant_sessions_$generation.json"
		fi
		i=$((i + 1))
	done
	run_persistence prune
	complete_count=$(find "$CURRENT_RESURRECT_DIR" -maxdepth 1 -type f \
		-name 'tmux_resurrect_2026*.txt' | wc -l | tr -d ' ')
	assert_eq 96 "$complete_count" 'default retention did not keep exactly 96 complete generations'
	# Unrestorable generations are not recovery points, so they are collected
	# rather than kept forever alongside their orphaned companions.
	assert_eq 0 "$(find "$CURRENT_RESURRECT_DIR" -maxdepth 1 -type f \
		\( -name 'tmux_resurrect_2027*.txt' -o -name 'tmux_resurrect_2028*.txt' \) \
		| wc -l | tr -d ' ')" \
		'unrestorable managed generations were retained instead of collected'

	export TMUX_PERSISTENCE_RETENTION=1
	run_persistence prune
	complete_count=$(find "$CURRENT_RESURRECT_DIR" -maxdepth 1 -type f \
		-name 'tmux_resurrect_2026*.txt' | wc -l | tr -d ' ')
	pane_count=$(find "$CURRENT_RESURRECT_DIR" -maxdepth 1 -type f \
		-name 'pane_contents_2026*.tar.gz' | wc -l | tr -d ' ')
	assistant_count=$(find "$CURRENT_RESURRECT_DIR" -maxdepth 1 -type f \
		-name 'assistant_sessions_2026*.json' | wc -l | tr -d ' ')
	assert_eq 1 "$complete_count" 'retention did not honour an explicit smaller budget'
	assert_eq 1 "$pane_count" 'retention orphaned or over-pruned pane archives'
	assert_eq 1 "$assistant_count" 'retention orphaned or over-pruned assistant maps'

	# Legacy layouts use age-based pruning owned by the coordinator; current is
	# protected even when it falls outside the five newest legacy snapshots.
	i=1
	while [ "$i" -le 9 ]; do
		base=$(printf 'tmux_resurrect_20200101T000000-%03d.txt' "$i")
		write_layout "$CURRENT_RESURRECT_DIR/$base" 1
		touch -t 202001010000 "$CURRENT_RESURRECT_DIR/$base"
		i=$((i + 1))
	done
	# Newer corrupt legacy layouts do not consume the five valid recovery slots.
	i=1
	while [ "$i" -le 7 ]; do
		base=$(printf 'tmux_resurrect_20290101T000000-%03d.txt' "$i")
		if [ "$i" -le 3 ]; then
			: >"$CURRENT_RESURRECT_DIR/$base"
		else
			printf 'not a resurrect layout\n' >"$CURRENT_RESURRECT_DIR/$base"
		fi
		touch -t 202001010000 "$CURRENT_RESURRECT_DIR/$base"
		i=$((i + 1))
	done
	protected_legacy=tmux_resurrect_20200101T000000-001.txt
	rm -f "$CURRENT_RESURRECT_DIR/last"
	ln -s "$protected_legacy" "$CURRENT_RESURRECT_DIR/last"
	run_persistence prune
	legacy_count=$(find "$CURRENT_RESURRECT_DIR" -maxdepth 1 -type f \
		-name 'tmux_resurrect_20200101T*.txt' | wc -l | tr -d ' ')
	assert_eq 6 "$legacy_count" 'legacy retention did not keep five newest plus the current target'
	assert_file "$CURRENT_RESURRECT_DIR/$protected_legacy"
	stop_server "$CURRENT_SOCKET"
}

printf '1..14\n'
run_test 'config uses the coordinator without Continuum' test_config_wiring
run_test 'loaded config keeps guarded bindings and renders warnings' \
	test_loaded_config_bindings_and_warning
run_test 'three bounded waiters never start a server and later share one ready server' \
	test_bounded_readiness_and_no_start
run_test 'the supervisor owns startup and three clients claim distinct sessions' \
	test_agent_owns_startup_before_three_clients
run_test 'restore verification gates topology while cwd remains diagnostic' \
	test_exact_topology_and_cwd_verification
run_test 'saves publish fresh coherent generations and coalesce under one lock' \
	test_unique_generations_and_lock_coalescing
run_test 'a failed last-pointer commit retains and later recovers its transaction' \
	test_failed_last_commit_retains_transaction
run_test 'a killed raw save cannot become the automatic restore candidate' \
	test_interrupted_raw_layout_is_not_promoted
run_test 'a killed complete publication is synced before recovery commits it' \
	test_interrupted_published_generation_is_recovered
run_test 'poisoned, incomplete, and empty candidates are handled safely' \
	test_poisoned_and_incomplete_candidates
run_test 'assistant-map failure preserves the prior coherent generation' \
	test_assistant_map_failure_preserves_current_generation
run_test 'clean recovery skips durability work and validation creates state' \
	test_clean_recovery_skips_barrier_and_validation_creates_state
run_test 'a split pane record is rejoined instead of failing the save' \
	test_split_pane_record_is_rejoined
run_test 'retention bounds managed generations and ages legacy layouts' \
	test_retention_counts_complete_generations

if [ "$failures" -ne 0 ]; then
	printf '%s of %s tests failed\n' "$failures" "$tests" >&2
	exit 1
fi
