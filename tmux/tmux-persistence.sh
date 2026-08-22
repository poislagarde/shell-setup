#!/usr/bin/env bash
# Serialize tmux-resurrect saves and publish the layout, pane contents, and
# assistant-session map as one recoverable generation. The launchd server
# agent also uses this script for guarded startup restore and readiness.

set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
TMUX_BIN=${TMUX_PERSISTENCE_TMUX_BIN:-${TMUX_BIN:-}}
[ -n "$TMUX_BIN" ] || TMUX_BIN=$(command -v tmux 2>/dev/null || true)
RESURRECT_SAVE=${TMUX_PERSISTENCE_RESURRECT_SAVE:-$HOME/.tmux/plugins/tmux-resurrect/scripts/save.sh}
RESURRECT_RESTORE=${TMUX_PERSISTENCE_RESURRECT_RESTORE:-$HOME/.tmux/plugins/tmux-resurrect/scripts/restore.sh}
ASSISTANT_SAVE=${TMUX_PERSISTENCE_ASSISTANT_SAVE:-$SCRIPT_DIR/assistant-resurrect/save.sh}
ASSISTANT_RESTORE=${TMUX_PERSISTENCE_ASSISTANT_RESTORE:-$SCRIPT_DIR/assistant-resurrect/restore.sh}
STATE_DIR=${TMUX_PERSISTENCE_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/tmux-persistence}
RUNTIME_STATE=$STATE_DIR/runtime.tsv
LOG_FILE=$STATE_DIR/persistence.log
RETENTION=${TMUX_PERSISTENCE_RETENTION:-96}
LEGACY_MIN_KEEP=${TMUX_PERSISTENCE_LEGACY_MIN_KEEP:-5}
LEGACY_DELETE_AFTER=${TMUX_PERSISTENCE_LEGACY_DELETE_AFTER:-30}
CLAIM_TTL=${TMUX_PERSISTENCE_CLAIM_TTL:-30}
CLAIM_DEAD_TTL=${TMUX_PERSISTENCE_CLAIM_DEAD_TTL:-2}
CLAIM_MAX_TTL=${TMUX_PERSISTENCE_CLAIM_MAX_TTL:-300}
CLAIM_LOCK_TIMEOUT=${TMUX_PERSISTENCE_CLAIM_LOCK_TIMEOUT:-60}
SAVE_LOCK_TIMEOUT=${TMUX_PERSISTENCE_SAVE_LOCK_TIMEOUT:-30}
SCHEDULER_RETRY_DELAY=${TMUX_PERSISTENCE_SCHEDULER_RETRY_DELAY:-60}
PYTHON_BIN=${TMUX_PERSISTENCE_PYTHON_BIN:-}
[ -n "$PYTHON_BIN" ] || PYTHON_BIN=$(command -v python3 2>/dev/null || true)
EXPECTED_PID=${TMUX_PERSISTENCE_EXPECTED_PID:-}
EXPECTED_SOCKET=${TMUX_PERSISTENCE_EXPECTED_SOCKET:-}
CANONICAL_SOCKET=${TMUX_PERSISTENCE_CANONICAL_SOCKET_PATH:-}

tmux_no_start_raw() {
	[ -n "$TMUX_BIN" ] || return 127
	if [ -n "${TMUX_PERSISTENCE_SOCKET_PATH:-}" ]; then
		"$TMUX_BIN" -N -S "$TMUX_PERSISTENCE_SOCKET_PATH" "$@"
	elif [ -n "${TMUX_PERSISTENCE_SOCKET_NAME:-}" ]; then
		"$TMUX_BIN" -N -L "$TMUX_PERSISTENCE_SOCKET_NAME" "$@"
	elif [ -n "$CANONICAL_SOCKET" ]; then
		"$TMUX_BIN" -N -S "$CANONICAL_SOCKET" "$@"
	else
		env -u TMUX -u TMUX_PANE -u TMUX_TMPDIR "$TMUX_BIN" -N -L default "$@"
	fi
}

tmux_no_start() {
	local identity pid socket
	if [ -n "$EXPECTED_PID" ] || [ -n "$EXPECTED_SOCKET" ]; then
		identity=$(tmux_no_start_raw display-message -p $'#{pid}\t#{socket_path}' 2>/dev/null) || return 1
		IFS=$'\t' read -r pid socket <<<"$identity"
		[ -z "$EXPECTED_PID" ] || [ "$pid" = "$EXPECTED_PID" ] || return 1
		[ -z "$EXPECTED_SOCKET" ] || [ "$socket" = "$EXPECTED_SOCKET" ] || return 1
	fi
	tmux_no_start_raw "$@"
}

mkdir_state() {
	mkdir -p "$STATE_DIR"
}

log() {
	mkdir_state
	printf '[%s] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" >>"$LOG_FILE"
}

# `mv` makes a name change atomic to running processes, but it does not order
# disk persistence across sudden power loss. fsync each file and directory,
# then ask macOS to drain each affected device before crossing a transaction
# boundary. There is deliberately no weaker fallback.
durability_barrier() {
	[ "$#" -gt 0 ] && [ -x "$PYTHON_BIN" ] || {
		log 'python3 durability helper is unavailable; refusing a non-durable transaction'
		return 1
	}
	"$PYTHON_BIN" - "$@" >/dev/null 2>&1 <<'PY' || {
import fcntl
import os
import sys

fds = []
devices = {}
try:
    for path in sys.argv[1:]:
        fd = os.open(path, os.O_RDONLY)
        fds.append(fd)
        os.fsync(fd)
        devices.setdefault(os.fstat(fd).st_dev, fd)
    for fd in devices.values():
        fcntl.fcntl(fd, fcntl.F_FULLFSYNC)
finally:
    for fd in fds:
        os.close(fd)
PY
		log "durability barrier failed for: $*"
		return 1
	}
}

one_line() {
	printf '%s' "$1" | tr '\t\r\n' '   '
}

require_reserved_regular_or_absent() {
	local path
	for path in "$@"; do
		if [ -e "$path" ] || [ -L "$path" ]; then
			if [ ! -f "$path" ] || [ -L "$path" ]; then
				log "reserved persistence path has an unsafe type: $path"
				return 1
			fi
		fi
	done
}

require_reserved_absent() {
	local path
	for path in "$@"; do
		if [ -e "$path" ] || [ -L "$path" ]; then
			log "reserved persistence path was not cleared: $path"
			return 1
		fi
	done
}

server_pid() {
	tmux_no_start display-message -p '#{pid}' 2>/dev/null
}

assert_managed_socket() {
	local identity pid socket
	identity=$(tmux_no_start_raw display-message -p $'#{pid}\t#{socket_path}' 2>/dev/null) || return 1
	IFS=$'\t' read -r pid socket <<<"$identity"
	if [ -n "$EXPECTED_PID" ] && [ "$pid" != "$EXPECTED_PID" ]; then
		log "refused tmux server pid=$pid (expected $EXPECTED_PID)"
		return 1
	fi
	if [ -n "$EXPECTED_SOCKET" ]; then
		[ "$socket" = "$EXPECTED_SOCKET" ] || {
			log "refused non-production socket: $socket (expected $EXPECTED_SOCKET)"
			return 1
		}
	elif [ -n "${TMUX_PERSISTENCE_SOCKET_PATH:-}" ]; then
		[ "$socket" = "$TMUX_PERSISTENCE_SOCKET_PATH" ] || return 1
	elif [ -n "${TMUX_PERSISTENCE_SOCKET_NAME:-}" ]; then
		[ "${socket##*/}" = "$TMUX_PERSISTENCE_SOCKET_NAME" ] || return 1
	elif [ -n "$CANONICAL_SOCKET" ]; then
		[ "$socket" = "$CANONICAL_SOCKET" ] || return 1
	else
		# tmux_no_start_raw reached this server only through `-L default` with
		# inherited TMUX/TMUX_TMPDIR removed, so this is the canonical socket.
		[ "${socket##*/}" = default ] || return 1
	fi
}

prepare_tmux_environment() {
	local identity pid socket
	identity=$(tmux_no_start_raw display-message -p $'#{pid}\t#{socket_path}' 2>/dev/null) || return 1
	IFS=$'\t' read -r pid socket <<<"$identity"
	[ -z "$EXPECTED_PID" ] || [ "$pid" = "$EXPECTED_PID" ] || return 1
	[ -z "$EXPECTED_SOCKET" ] || [ "$socket" = "$EXPECTED_SOCKET" ] || return 1
	# Resurrect derives its explicit -S target from TMUX. launchd starts with
	# TMUX unset, so reconstruct it for the exact server queried above.
	export TMUX="$socket,$pid,0"
}

RESURRECT_DIR_CACHE=

resurrect_dir() {
	local dir
	if [ -n "$RESURRECT_DIR_CACHE" ]; then
		printf '%s\n' "$RESURRECT_DIR_CACHE"
		return
	fi
	if [ -n "${TMUX_PERSISTENCE_RESURRECT_DIR:-}" ]; then
		RESURRECT_DIR_CACHE=$TMUX_PERSISTENCE_RESURRECT_DIR
		printf '%s\n' "$RESURRECT_DIR_CACHE"
		return
	fi
	dir=$(tmux_no_start show-option -gqv @resurrect-dir 2>/dev/null || true)
	if [ -z "$dir" ]; then
		if [ -d "$HOME/.tmux/resurrect" ]; then
			dir=$HOME/.tmux/resurrect
		else
			dir=${XDG_DATA_HOME:-$HOME/.local/share}/tmux/resurrect
		fi
	fi
	dir=${dir//\$HOME/$HOME}
	dir=${dir//\$HOSTNAME/$(hostname)}
	dir=${dir/#\~/$HOME}
	# The assistant helpers must land on the same directory, so hand them the
	# resolved answer instead of letting them re-derive it by different rules.
	RESURRECT_DIR_CACHE=$dir
	export TMUX_PERSISTENCE_RESURRECT_DIR=$dir
	printf '%s\n' "$dir"
}

ensure_resurrect_dir() {
	local dir=$1
	if ! mkdir -p "$dir" || [ ! -d "$dir" ] || [ ! -r "$dir" ] || \
	   [ ! -w "$dir" ] || [ ! -x "$dir" ]; then
		log "persistence data directory is unavailable: $dir"
		return 1
	fi
}

is_layout_basename() {
	[[ "$1" =~ ^tmux_resurrect_[A-Za-z0-9._-]+\.txt$ ]]
}

is_managed_layout() {
	[[ "$1" =~ ^tmux_resurrect_[0-9]{8}T[0-9]{6}-g[0-9]+-[0-9]{3}\.txt$ ]]
}

layout_generation() {
	local base=$1 generation
	is_layout_basename "$base" || return 1
	generation=${base#tmux_resurrect_}
	printf '%s\n' "${generation%.txt}"
}

pane_companion() {
	local generation
	generation=$(layout_generation "$1") || return 1
	printf '%s/pane_contents_%s.tar.gz\n' "$(resurrect_dir)" "$generation"
}

assistant_companion() {
	local generation
	generation=$(layout_generation "$1") || return 1
	printf '%s/assistant_sessions_%s.json\n' "$(resurrect_dir)" "$generation"
}

layout_valid() {
	[ -f "$1" ] || return 1
	awk -F '\t' '
		NF == 0 { next }
		$1 == "pane" { seen = 1; if (NF < 11) bad = 1; next }
		$1 == "window" { seen = 1; if (NF < 7) bad = 1; next }
		$1 == "state" { seen = 1; if (NF < 3) bad = 1; next }
		$1 == "grouped_session" { seen = 1; if (NF < 5) bad = 1; next }
		{ bad = 1 }
		END { exit(bad || !seen) }
	' "$1"
}

archive_valid() {
	[ -f "$1" ] && gzip -t "$1" >/dev/null 2>&1 && tar tzf "$1" >/dev/null 2>&1
}

assistant_json_valid() {
	[ -f "$1" ] && jq -e 'type == "array"' "$1" >/dev/null 2>&1
}

generation_complete() {
	local base=$1 dir=${2:-} generation pane assistant
	[ -n "$dir" ] || dir=$(resurrect_dir)
	generation=$(layout_generation "$base") || return 1
	pane=$dir/pane_contents_$generation.tar.gz
	assistant=$dir/assistant_sessions_$generation.json
	layout_valid "$dir/$base" && archive_valid "$pane" && assistant_json_valid "$assistant"
}

last_basename() {
	local dir target
	dir=$(resurrect_dir)
	[ -L "$dir/last" ] || return 1
	target=$(readlink "$dir/last") || return 1
	basename "$target"
}

point_last() {
	local dir base tmp
	dir=$(resurrect_dir)
	base=$1
	[ -f "$dir/$base" ] || return 1
	[ ! -d "$dir/last" ] || return 1
	tmp=$dir/.last.$$
	rm -f "$tmp"
	ln -s "$base" "$tmp" && mv -f "$tmp" "$dir/last" && durability_barrier "$dir"
}

list_layouts() {
	local dir file
	dir=$(resurrect_dir)
	for file in "$dir"/tmux_resurrect_*.txt; do
		[ -f "$file" ] || continue
		printf '%s\n' "${file##*/}"
	done | LC_ALL=C sort
}

# Newest complete generation, never $pivot itself. Mode `older` starts only
# once $pivot has been passed in descending order.
restorable_layout() {
	local mode=$1 pivot=${2:-} dir base seen=no
	dir=$(resurrect_dir)
	while IFS= read -r base; do
		[ -n "$base" ] || continue
		if [ "$base" = "$pivot" ]; then seen=yes; continue; fi
		[ "$mode" != older ] || [ "$seen" = yes ] || continue
		is_managed_layout "$base" || continue
		generation_complete "$base" "$dir" || continue
		printf '%s\n' "$base"
		return 0
	done < <(list_layouts | LC_ALL=C sort -r)
	return 1
}

write_runtime_state() {
	local phase=$1 pid=${2:-0} target=${3:-} detail=${4:-} tmp
	mkdir_state
	tmp=$RUNTIME_STATE.$$
	printf '%s\t%s\t%s\t%s\t%s\n' \
		"$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$pid" "$phase" \
		"$(one_line "$target")" "$(one_line "$detail")" >"$tmp" && mv -f "$tmp" "$RUNTIME_STATE"
}

warning_for_phase() {
	case "$1" in
	needs-review) printf '%s\n' '⚠ RESTORE REVIEW' ;;
	degraded | error) printf '%s\n' '⚠ SAVES PAUSED' ;;
	restoring | verifying) printf '%s\n' 'RESTORING…' ;;
	*) printf '\n' ;;
	esac
}

set_phase() {
	local phase=$1 detail=${2:-} target=${3:-} pid warning save_error
	pid=$(server_pid 2>/dev/null || printf 0)
	warning=$(warning_for_phase "$phase")
	if [ -z "$warning" ] && [ "$pid" != 0 ]; then
		save_error=$(tmux_no_start show-option -gqv @shell-setup-persistence-save-error 2>/dev/null || true)
		[ -z "$save_error" ] || warning='⚠ SAVE FAILED'
	fi
	write_runtime_state "$phase" "$pid" "$target" "$detail"
	if [ "$pid" != 0 ]; then
		tmux_no_start set-option -gq @shell-setup-persistence-state "$phase" 2>/dev/null || true
		tmux_no_start set-option -gq @shell-setup-persistence-detail "$(one_line "$detail")" 2>/dev/null || true
		tmux_no_start set-option -gq @shell-setup-persistence-target "$target" 2>/dev/null || true
		tmux_no_start set-option -gq @shell-setup-persistence-warning "$warning" 2>/dev/null || true
	fi
	log "state=$phase${target:+ target=$target}${detail:+ detail=$(one_line "$detail")}"
}

record_external_state() {
	write_runtime_state "$1" "${2:-0}" "" "${3:-}"
	log "state=$1${3:+ detail=$(one_line "$3")}"
}

show_tmux_message() {
	tmux_no_start display-message -d 8000 "$1" 2>/dev/null || true
}

mark_save_error() {
	local detail=$1 phase warning
	tmux_no_start set-option -gq @shell-setup-persistence-save-error "$(one_line "$detail")" 2>/dev/null || true
	phase=$(current_phase || true)
	warning=$(warning_for_phase "$phase")
	[ -n "$warning" ] || warning='⚠ SAVE FAILED'
	tmux_no_start set-option -gq @shell-setup-persistence-warning "$warning" 2>/dev/null || true
	log "save failed: $(one_line "$detail")"
	show_tmux_message "tmux save failed; previous generation kept — see $LOG_FILE"
}

clear_save_error() {
	local phase warning
	tmux_no_start set-option -gu @shell-setup-persistence-save-error 2>/dev/null || true
	phase=$(tmux_no_start show-option -gqv @shell-setup-persistence-state 2>/dev/null || true)
	warning=$(warning_for_phase "$phase")
	tmux_no_start set-option -gq @shell-setup-persistence-warning "$warning" 2>/dev/null || true
}

set_client_attachable() {
	case "$1" in yes | no) ;; *) return 2 ;; esac
	tmux_no_start set-option -gq @shell-setup-persistence-client-attachable "$1" 2>/dev/null
}

client_attachable() {
	local phase=${1:-}
	[ -n "$phase" ] || phase=$(current_phase || true)
	case "$phase" in
	ready) return 0 ;;
	degraded)
		[ "$(tmux_no_start show-option -gqv @shell-setup-persistence-client-attachable 2>/dev/null || true)" = yes ]
		;;
	*) return 1 ;;
	esac
}

lock_file() {
	printf '%s/.shell-setup-persistence.lock\n' "$(resurrect_dir)"
}

acquire_lock() {
	local timeout=$1 file status
	file=$(lock_file)
	mkdir -p "$(dirname "$file")" || return 74
	{ exec 9>>"$file"; } 2>/dev/null || return 74
	/usr/bin/lockf -s -t "$timeout" 9
	status=$?
	return "$status"
}

acquire_claim_lock() {
	local timeout=$1
	mkdir_state || return 1
	exec 8>>"$STATE_DIR/client-claims.lock"
	/usr/bin/lockf -s -t "$timeout" 8
}

clear_expired_claims() {
	local now ttl=$CLAIM_TTL dead_ttl=$CLAIM_DEAD_TTL max_ttl=$CLAIM_MAX_TTL
	local rows name attached
	local claim_field at_field owner_field claim at owner age
	local owner_known=no owner_alive=no
	case "$ttl" in *[!0-9]* | '') ttl=30 ;; esac
	case "$max_ttl" in *[!0-9]* | '') max_ttl=300 ;; esac
	case "$dead_ttl" in *[!0-9]* | '') dead_ttl=2 ;; esac
	[ "$max_ttl" -ge "$ttl" ] || max_ttl=$ttl
	# A dead owner must never be protected longer than an unknown one.
	[ "$dead_ttl" -le "$ttl" ] || dead_ttl=$ttl
	now=$(date +%s)
	rows=$(tmux_no_start list-sessions -F $'#{session_name}\t#{session_attached}\tX#{@shell-setup-client-claim}\tX#{@shell-setup-client-claim-at}\tX#{@shell-setup-client-claim-owner}' 2>/dev/null || true)
	while IFS=$'\t' read -r name attached claim_field at_field owner_field; do
		[ -n "$name" ] || continue
		claim=${claim_field#X}
		at=${at_field#X}
		owner=${owner_field#X}
		[ "$attached" = 0 ] && [ -n "$claim" ] || continue
		case "$at" in
		*[!0-9]* | '') age=$ttl ;;
		*) age=$((now - at)) ;;
		esac
		owner_known=no
		owner_alive=no
		case "$owner" in
		'' | *[!0-9]*) ;;
		*) owner_known=yes; kill -0 "$owner" 2>/dev/null && owner_alive=yes ;;
		esac
		# Three grace periods. A live owner is still mid-attach, so only a lease
		# stuck past the hard ceiling is reclaimable. A dead owner released
		# nothing -- a closed Ghostty surface is SIGHUP'd before it can -- so its
		# session becomes adoptable quickly, but not instantly: the reserving
		# shell may not have reached attach-session yet.
		if [ "$owner_alive" = yes ]; then
			[ "$age" -ge "$max_ttl" ] || continue
		elif [ "$owner_known" = yes ]; then
			[ "$age" -ge "$dead_ttl" ] || continue
		else
			[ "$age" -ge "$ttl" ] || continue
		fi
		tmux_no_start set-option -u -t "=$name:" @shell-setup-client-claim \; \
			set-option -u -t "=$name:" @shell-setup-client-claim-at \; \
			set-option -u -t "=$name:" @shell-setup-client-claim-owner >/dev/null 2>&1 || true
	done <<<"$rows"
}

has_pending_detached_claims() {
	local rows name attached claim_field claim
	rows=$(tmux_no_start list-sessions -F $'#{session_name}\t#{session_attached}\tX#{@shell-setup-client-claim}' 2>/dev/null) || return 2
	while IFS=$'\t' read -r name attached claim_field; do
		[ -n "$name" ] || continue
		claim=${claim_field#X}
		[ "$attached" = 0 ] && [ -n "$claim" ] && return 0
	done <<<"$rows"
	return 1
}

wait_for_pending_client_claims() {
	local attempts=${TMUX_PERSISTENCE_RESTORE_CLAIM_ATTEMPTS:-300}
	local delay=${TMUX_PERSISTENCE_RESTORE_CLAIM_DELAY:-0.1}
	local i=0 pending_status
	case "$attempts" in *[!0-9]* | '') attempts=300 ;; esac
	while [ "$i" -lt "$attempts" ]; do
		acquire_claim_lock 10 || return 1
		clear_expired_claims || { exec 8>&-; return 1; }
		has_pending_detached_claims
		pending_status=$?
		exec 8>&-
		case "$pending_status" in
		1) return 0 ;;
		2) return 1 ;;
		esac
		sleep "$delay"
		i=$((i + 1))
	done
	return 75
}

find_claim_candidate() {
	local kind=$1 rows name attached claim_field at_field claim
	rows=$(tmux_no_start list-sessions -F $'#{session_name}\t#{session_attached}\tX#{@shell-setup-client-claim}\tX#{@shell-setup-client-claim-at}' 2>/dev/null || true)
	if [ "$kind" = quick ]; then rows=$(printf '%s\n' "$rows" | sort -V); fi
	while IFS=$'\t' read -r name attached claim_field at_field; do
		[ -n "$name" ] || continue
		claim=${claim_field#X}
		[ "$attached" = 0 ] && [ -z "$claim" ] || continue
		if [ "$kind" = quick ]; then
			is_quick_session "$name" || continue
		else
			is_quick_session "$name" && continue
		fi
		printf '%s\n' "$name"
		return 0
	done <<<"$rows"
	return 1
}

is_quick_session() {
	[[ "$1" =~ ^quick(-[0-9]+)?$ ]]
}

create_claim_session() {
	local kind=$1 name n
	if [ "$kind" = quick ]; then
		if ! tmux_no_start has-session -t '=quick' 2>/dev/null; then
			name=quick
		else
			n=2
			while tmux_no_start has-session -t "=quick-$n" 2>/dev/null; do n=$((n + 1)); done
			name=quick-$n
		fi
		tmux_no_start new-session -d -P -F '#{session_name}' -s "$name"
	elif ! tmux_no_start has-session -t '=main' 2>/dev/null; then
		tmux_no_start new-session -d -P -F '#{session_name}' -s main
	else
		tmux_no_start new-session -d -P -F '#{session_name}'
	fi
}

clear_claim_if_token() {
	local target=$1 token=$2 current
	current=$(tmux_no_start show-options -qv -t "=$target:" @shell-setup-client-claim 2>/dev/null || true)
	[ "$current" = "$token" ] || return 0
	tmux_no_start set-option -u -t "=$target:" @shell-setup-client-claim \; \
		set-option -u -t "=$target:" @shell-setup-client-claim-at \; \
		set-option -u -t "=$target:" @shell-setup-client-claim-owner >/dev/null 2>&1
}

claim_session_command() {
	local kind=${1:-} owner=${2:-$PPID} candidate token now attached attempt=0 lock_status
	local lock_timeout=$CLAIM_LOCK_TIMEOUT phase
	case "$kind" in quick | regular) ;; *) printf '%s\n' 'claim requires quick or regular' >&2; return 2 ;; esac
	case "$owner" in '' | *[!0-9]*) printf '%s\n' 'claim owner must be a process id' >&2; return 2 ;; esac
	kill -0 "$owner" 2>/dev/null || { printf '%s\n' 'claim owner is not running' >&2; return 2; }
	case "$lock_timeout" in *[!0-9]* | '') lock_timeout=60 ;; esac
	prepare_tmux_environment || return 1
	assert_managed_socket || return 1
	acquire_lock "$lock_timeout"
	lock_status=$?
	[ "$lock_status" -eq 0 ] || return "$lock_status"
	phase=$(current_phase || true)
	client_attachable "$phase" || return 1
	acquire_claim_lock 10 || return 1
	clear_expired_claims || return 1
	while [ "$attempt" -lt 3 ]; do
		candidate=$(find_claim_candidate "$kind" || true)
		[ -n "$candidate" ] || candidate=$(create_claim_session "$kind") || return 1
		now=$(date +%s)
		token="$$-$now-${RANDOM:-0}"
		if ! tmux_no_start set-option -t "=$candidate:" @shell-setup-client-claim "$token" \; \
		   set-option -t "=$candidate:" @shell-setup-client-claim-at "$now" \; \
		   set-option -t "=$candidate:" @shell-setup-client-claim-owner "$owner" >/dev/null 2>&1; then
			return 1
		fi
		attached=$(tmux_no_start display-message -p -t "=$candidate:" '#{session_attached}' 2>/dev/null || true)
		if [ "$attached" = 0 ]; then
			phase=$(current_phase || true)
			client_attachable "$phase" || {
				clear_claim_if_token "$candidate" "$token" || true
				return 1
			}
			exec 8>&-
			exec 9>&-
			printf '%s\t%s\n' "$candidate" "$token"
			return 0
		fi
		clear_claim_if_token "$candidate" "$token" || true
		attempt=$((attempt + 1))
	done
	return 1
}

release_claim_command() {
	local target=${1:-} token=${2:-}
	[ -n "$target" ] && [ -n "$token" ] || return 2
	prepare_tmux_environment || return 0
	assert_managed_socket || return 1
	acquire_claim_lock 10 || return 1
	clear_claim_if_token "$target" "$token" || return 1
	exec 8>&-
}

transaction_file() { printf '%s/.shell-setup-save-transaction\n' "$(resurrect_dir)"; }
pane_backup() { printf '%s/.shell-setup-pane-backup.tar.gz\n' "$(resurrect_dir)"; }
assistant_backup() { printf '%s/.shell-setup-assistant-backup.json\n' "$(resurrect_dir)"; }
staged_layout() { printf '%s/save-layout-%s\n' "$STATE_DIR" "$1"; }

restore_save_backups() {
	local validate_existing=${1:-no} dir pane_b assistant_b status=0 sync_paths
	local pane_dest assistant_dest
	local pane_needs_validation=$validate_existing assistant_needs_validation=$validate_existing
	dir=$(resurrect_dir)
	sync_paths=( "$dir" )
	pane_b=$(pane_backup)
	assistant_b=$(assistant_backup)
	pane_dest=$dir/pane_contents.tar.gz
	assistant_dest=$dir/assistant-sessions.json
	require_reserved_regular_or_absent "$pane_b" "$assistant_b" "$pane_dest" "$assistant_dest" || return 1
	# The overwhelmingly common call is transaction recovery with no journal and
	# no orphaned backups. Nothing was renamed or created, so there is no
	# durability boundary to cross.
	if [ "$validate_existing" = no ] && [ ! -f "$pane_b" ] && [ ! -f "$assistant_b" ]; then
		return 0
	fi
	if [ -f "$pane_b" ]; then
		pane_needs_validation=yes
		archive_valid "$pane_b" || { log 'save-transaction pane backup is invalid'; return 1; }
		if mv -f "$pane_b" "$pane_dest"; then
			if ! archive_valid "$pane_dest"; then
				mv -f "$pane_dest" "$pane_b" 2>/dev/null || true
				status=1
			fi
		else
			status=1
		fi
	fi
	if [ -f "$assistant_b" ]; then
		assistant_needs_validation=yes
		assistant_json_valid "$assistant_b" || { log 'save-transaction assistant backup is invalid'; return 1; }
		if mv -f "$assistant_b" "$assistant_dest"; then
			if ! assistant_json_valid "$assistant_dest"; then
				mv -f "$assistant_dest" "$assistant_b" 2>/dev/null || true
				status=1
			fi
		else
			status=1
		fi
	fi
	if [ "$pane_needs_validation" = yes ] && [ -f "$pane_dest" ]; then
		archive_valid "$pane_dest" || status=1
		sync_paths+=( "$pane_dest" )
	fi
	if [ "$assistant_needs_validation" = yes ] && [ -f "$assistant_dest" ]; then
		assistant_json_valid "$assistant_dest" || status=1
		sync_paths+=( "$assistant_dest" )
	fi
	[ ! -f "$pane_b" ] || sync_paths+=( "$pane_b" )
	[ ! -f "$assistant_b" ] || sync_paths+=( "$assistant_b" )
	durability_barrier "${sync_paths[@]}" || status=1
	return "$status"
}

discard_save_backups() {
	rm -f "$(pane_backup)" "$(assistant_backup)"
}

cleanup_transaction_artifacts() {
	local planned=$1 keep_planned=$2 previous=${3:-} fallback=${4:-}
	local dir staged source_record source_path= source_base= generation path status=0
	dir=$(resurrect_dir)
	staged=$(staged_layout "${planned:-unknown}")
	source_record=$staged.source
	if [ -f "$source_record" ]; then
		IFS= read -r source_path <"$source_record" || true
		source_base=${source_path##*/}
		if is_layout_basename "$source_base" && [ "$source_path" = "$dir/$source_base" ]; then
			if [ "$source_base" != "$planned" ] && [ "$source_base" != "$previous" ] && \
			   [ "$source_base" != "$fallback" ]; then
				rm -f "$source_path" || status=1
			fi
		fi
	fi
	if is_managed_layout "$planned"; then
		generation=$(layout_generation "$planned") || return 1
		if [ "$keep_planned" != yes ]; then
			rm -f "$dir/$planned" "$dir/pane_contents_$generation.tar.gz" \
				"$dir/assistant_sessions_$generation.json" || status=1
		fi
		for path in "$dir/.$planned".* "$dir/.pane_contents_$generation".*.tar.gz \
			"$dir/.assistant_sessions_$generation".*.json; do
			[ -e "$path" ] || [ -L "$path" ] || continue
			[ -f "$path" ] || [ -L "$path" ] || { status=1; continue; }
			rm -f -- "$path" || status=1
		done
	fi
	[ "$status" -eq 0 ] || {
		log 'could not remove all interrupted transaction artifacts; journal retained'
		return 1
	}
	rm -f "$staged" "$source_record" || return 1
	if [ -d "$STATE_DIR" ]; then
		durability_barrier "$dir" "$STATE_DIR"
	else
		durability_barrier "$dir"
	fi
}

recover_transaction() {
	local journal planned previous recorded_fallback dir fallback staged source_record outcome keep_planned=no
	local generation pane assistant
	dir=$(resurrect_dir)
	ensure_resurrect_dir "$dir" || return 1
	journal=$dir/.shell-setup-save-transaction
	require_reserved_regular_or_absent "$journal" "$(pane_backup)" "$(assistant_backup)" || return 1
	[ -f "$journal" ] || {
		restore_save_backups no || {
			log 'could not restore orphaned save backups; retrying on the next operation'
			return 1
		}
		return
	}
	IFS=$'\t' read -r planned previous recorded_fallback <"$journal" || true
	if ! is_managed_layout "${planned:-}" || \
	   { [ -n "${previous:-}" ] && ! is_layout_basename "$previous"; } || \
	   { [ -n "${recorded_fallback:-}" ] && ! is_layout_basename "$recorded_fallback"; }; then
		log 'save transaction journal is malformed; refusing automatic recovery'
		return 1
	fi
	staged=$(staged_layout "${planned:-unknown}")
	source_record=$staged.source
	if [ -n "${planned:-}" ] && generation_complete "$planned" "$dir"; then
		generation=$(layout_generation "$planned") || return 1
		pane=$dir/pane_contents_$generation.tar.gz
		assistant=$dir/assistant_sessions_$generation.json
		durability_barrier "$dir/$planned" "$pane" "$assistant" "$dir" || {
			log "could not make interrupted generation durable at $planned; journal retained"
			return 1
		}
		point_last "$planned" || {
			log "could not commit interrupted save transaction at $planned; journal retained"
			return 1
		}
		discard_save_backups || {
			log "could not discard backups for committed transaction $planned; journal retained"
			return 1
		}
		keep_planned=yes
		outcome="completed interrupted save transaction at $planned"
	else
		fallback=
		if [ -n "${previous:-}" ] && layout_valid "$dir/$previous"; then
			if ! is_managed_layout "$previous" || generation_complete "$previous" "$dir"; then
				fallback=$previous
			fi
		fi
		if [ -z "$fallback" ] && [ -n "${recorded_fallback:-}" ] && \
		   layout_valid "$dir/$recorded_fallback"; then
			if ! is_managed_layout "$recorded_fallback" || generation_complete "$recorded_fallback" "$dir"; then
				fallback=$recorded_fallback
			fi
		fi
		if [ -n "$fallback" ]; then
			point_last "$fallback" || {
				log "could not roll back last to $fallback; journal retained"
				return 1
			}
		else
			rm -f "$dir/last" || {
				log 'could not clear an invalid last pointer; journal retained'
				return 1
			}
			durability_barrier "$dir" || {
				log 'could not durably clear an invalid last pointer; journal retained'
				return 1
			}
		fi
		restore_save_backups yes || {
			log 'could not restore save backups during rollback; journal retained'
			return 1
		}
		outcome="rolled back interrupted save transaction${fallback:+ to $fallback}"
	fi
	cleanup_transaction_artifacts "$planned" "$keep_planned" "${previous:-}" "${fallback:-}" || return 1
	if ! rm -f "$journal" || ! durability_barrier "$dir"; then
		log 'could not remove the completed transaction journal; recovery will retry'
		return 1
	fi
	log "$outcome"
}

fail_save_with_recovery() {
	local reason=$1
	if ! recover_transaction; then
		reason="$reason; transaction recovery also failed and its journal was retained"
	fi
	mark_save_error "$reason"
	return 1
}

clear_pane_scratch() {
	local area=$1 dir scratch entry
	case "$area" in save | restore) ;; *) return 1 ;; esac
	dir=$(resurrect_dir)
	scratch=$dir/$area/pane_contents
	mkdir -p "$scratch" || return 1
	for entry in "$scratch"/* "$scratch"/.[!.]* "$scratch"/..?*; do
		[ -e "$entry" ] || [ -L "$entry" ] || continue
		if [ ! -f "$entry" ] && [ ! -L "$entry" ]; then
			log "refusing unexpected pane scratch entry: $entry"
			return 1
		fi
		rm -f -- "$entry" || return 1
	done
}

current_phase() {
	tmux_no_start show-option -gqv @shell-setup-persistence-state 2>/dev/null
}

unique_managed_basename() {
	local dir stamp seq base
	dir=$(resurrect_dir)
	stamp=$(date +%Y%m%dT%H%M%S)
	seq=0
	while :; do
		# The lock makes this a global per-second sequence. Keep it before the
		# fixed suffix so lexical order is also publication order, even when two
		# saves in one second run in different coordinator processes.
		base=$(printf 'tmux_resurrect_%s-g%06d-000.txt' "$stamp" "$seq")
		if [ ! -e "$dir/$base" ]; then
			printf '%s\n' "$base"
			return
		fi
		seq=$((seq + 1))
	done
}

atomic_copy() {
	local source=$1 destination=$2 tmp=$2.tmp.$$
	cp -p "$source" "$tmp" && mv -f "$tmp" "$destination"
}

publish_generation() {
	local source_layout=$1 planned=$2 dir generation pane_final assistant_final
	local layout_tmp pane_tmp assistant_tmp
	dir=$(resurrect_dir)
	generation=$(layout_generation "$planned") || return 1
	pane_final=$dir/pane_contents_$generation.tar.gz
	assistant_final=$dir/assistant_sessions_$generation.json
	layout_tmp=$dir/.$planned.$$
	pane_tmp=$dir/.pane_contents_$generation.$$.tar.gz
	assistant_tmp=$dir/.assistant_sessions_$generation.$$.json

	cp -p "$source_layout" "$layout_tmp" || return 1
	cp -p "$dir/pane_contents.tar.gz" "$pane_tmp" || { rm -f "$layout_tmp"; return 1; }
	cp -p "$dir/assistant-sessions.json" "$assistant_tmp" || {
		rm -f "$layout_tmp" "$pane_tmp"
		return 1
	}
	if ! layout_valid "$layout_tmp" || ! archive_valid "$pane_tmp" || ! assistant_json_valid "$assistant_tmp"; then
		rm -f "$layout_tmp" "$pane_tmp" "$assistant_tmp"
		return 1
	fi
	mv -f "$pane_tmp" "$pane_final" || return 1
	mv -f "$assistant_tmp" "$assistant_final" || return 1
	mv -f "$layout_tmp" "$dir/$planned" || return 1
	if [ "${TMUX_PERSISTENCE_TEST_KILL_AFTER_PUBLISH_RENAMES:-no}" = yes ]; then
		kill -KILL "$$"
	fi
	generation_complete "$planned" "$dir" && \
		durability_barrier "$dir/$planned" "$pane_final" "$assistant_final" "$dir"
}

# Every transaction target and the current pointer survive pruning.
protected_layout() {
	local base=$1 target
	shift
	for target in "$@"; do
		[ "$base" = "$target" ] && return 0
	done
	return 1
}

prune_generations() {
	local keep=$RETENTION legacy_keep=$LEGACY_MIN_KEEP
	local legacy_days=$LEGACY_DELETE_AFTER dir current journal planned= previous= fallback=
	local count=0 legacy_count=0 base generation status=0 changed=no
	local layouts= legacy_old=
	case "$keep" in *[!0-9]* | '') keep=96 ;; esac
	case "$legacy_keep" in *[!0-9]* | '') legacy_keep=5 ;; esac
	case "$legacy_days" in *[!0-9]* | '') legacy_days=30 ;; esac
	[ "$keep" -ge 1 ] || keep=1
	[ "$legacy_keep" -ge 1 ] || legacy_keep=1
	dir=$(resurrect_dir)
	current=$(last_basename 2>/dev/null || true)
	journal=$(transaction_file)
	if [ -f "$journal" ]; then IFS=$'\t' read -r planned previous fallback <"$journal" || true; fi
	layouts=$(list_layouts | LC_ALL=C sort -r)
	# One age sweep for the whole directory instead of a find per candidate.
	legacy_old=$'\n'$(find "$dir" -maxdepth 1 -type f -name 'tmux_resurrect_*.txt' \
		-mtime "+$legacy_days" 2>/dev/null | sed 's|.*/||')$'\n'

	# Managed layouts and both companions are one deletion unit. Validation is
	# only what earns a place in the recovery budget, so it stops once the budget
	# is full: everything past it is deleted either way. An unrestorable
	# generation is not a recovery point, so it is collected rather than kept.
	while IFS= read -r base; do
		[ -n "$base" ] || continue
		is_managed_layout "$base" || continue
		if [ "$count" -lt "$keep" ] && generation_complete "$base" "$dir"; then
			count=$((count + 1))
			continue
		fi
		protected_layout "$base" "$current" "$planned" "$previous" "$fallback" && continue
		generation=$(layout_generation "$base") || continue
		rm -f "$dir/$base" "$dir/pane_contents_$generation.tar.gz" \
			"$dir/assistant_sessions_$generation.json" || status=1
		[ "$status" -ne 0 ] || changed=yes
	done <<<"$layouts"

	# Resurrect's own age pruner cannot remain enabled: it sees the managed
	# layout filenames but not their keyed companions. Apply its legacy policy
	# here instead, keeping the newest readable snapshots and every transaction
	# or current-pointer target. Deletion stays age-gated.
	while IFS= read -r base; do
		[ -n "$base" ] || continue
		is_managed_layout "$base" && continue
		if [ "$legacy_count" -lt "$legacy_keep" ] && layout_valid "$dir/$base"; then
			legacy_count=$((legacy_count + 1))
			continue
		fi
		protected_layout "$base" "$current" "$planned" "$previous" "$fallback" && continue
		case "$legacy_old" in *$'\n'"$base"$'\n'*) ;; *) continue ;; esac
		rm -f "$dir/$base" || status=1
		[ "$status" -ne 0 ] || changed=yes
	done <<<"$layouts"
	[ "$status" -ne 0 ] || [ "$changed" != yes ] || durability_barrier "$dir" || status=1
	return "$status"
}

save_locked() {
	local allow_seed=$1 quiet=$2 dir phase planned previous rollback journal staged
	local backup_sync_paths
	prepare_tmux_environment || { mark_save_error 'tmux server is unavailable'; return 1; }
	assert_managed_socket || { mark_save_error 'refusing to save a non-production tmux socket'; return 1; }
	dir=$(resurrect_dir)
	ensure_resurrect_dir "$dir" || {
		mark_save_error "persistence data directory is unavailable: $dir"
		return 1
	}
	recover_transaction || {
		mark_save_error 'an interrupted save transaction could not be recovered; journal retained'
		return 1
	}
	phase=$(current_phase || true)
	if [ "$phase" != ready ] && [ "$allow_seed" != yes ]; then
		log "save refused: server state is ${phase:-unset}"
		[ "$quiet" = yes ] || show_tmux_message "tmux save refused: persistence is ${phase:-not ready}"
		return 3
	fi
	[ -x "$PYTHON_BIN" ] || { mark_save_error 'python3 durability helper is unavailable'; return 1; }
	[ -x "$RESURRECT_SAVE" ] || { mark_save_error "Resurrect save script is missing: $RESURRECT_SAVE"; return 1; }
	[ -x "$ASSISTANT_SAVE" ] || { mark_save_error "assistant save script is missing: $ASSISTANT_SAVE"; return 1; }
	clear_pane_scratch save || {
		mark_save_error 'could not clear Resurrect save scratch space'
		return 1
	}

	planned=$(unique_managed_basename)
	previous=$(last_basename 2>/dev/null || true)
	rollback=
	if [ -n "$previous" ] && layout_valid "$dir/$previous"; then
		if ! is_managed_layout "$previous" || generation_complete "$previous" "$dir"; then
			rollback=$previous
		fi
	fi
	[ -n "$rollback" ] || rollback=$(restorable_layout newest || true)
	journal=$(transaction_file)
	staged=$(staged_layout "$planned")
	mkdir_state || { mark_save_error "cannot create persistence state directory: $STATE_DIR"; return 1; }
	require_reserved_absent "$journal" "$(pane_backup)" "$(assistant_backup)" || {
		mark_save_error 'reserved save-transaction paths are not clear'
		return 1
	}
	require_reserved_regular_or_absent "$dir/pane_contents.tar.gz" \
		"$dir/assistant-sessions.json" || {
		mark_save_error 'singleton sidecar paths have unsafe types'
		return 1
	}
	if ! printf '%s\t%s\t%s\n' "$planned" "$previous" "$rollback" >"$journal.tmp.$$" || \
	   ! mv -f "$journal.tmp.$$" "$journal" || ! durability_barrier "$journal" "$dir"; then
		rm -f "$journal.tmp.$$"
		mark_save_error 'could not durably create the save transaction journal'
		return 1
	fi
	rm -f "$staged" "$staged.source"

	if [ -f "$dir/pane_contents.tar.gz" ] && \
	   ! mv -f "$dir/pane_contents.tar.gz" "$(pane_backup)"; then
		fail_save_with_recovery 'could not stage the previous pane-content archive'
		return 1
	fi
	if [ -f "$dir/assistant-sessions.json" ] && \
	   ! mv -f "$dir/assistant-sessions.json" "$(assistant_backup)"; then
		fail_save_with_recovery 'could not stage the previous assistant-session map'
		return 1
	fi
	backup_sync_paths=( "$dir" )
	[ ! -f "$(pane_backup)" ] || backup_sync_paths+=( "$(pane_backup)" )
	[ ! -f "$(assistant_backup)" ] || backup_sync_paths+=( "$(assistant_backup)" )
	if ! durability_barrier "${backup_sync_paths[@]}"; then
		fail_save_with_recovery 'could not durably stage the previous singleton sidecars'
		return 1
	fi

	export TMUX_PERSISTENCE_LOCK_HELD=1
	export TMUX_PERSISTENCE_STAGED_LAYOUT=$staged
	"$RESURRECT_SAVE" quiet >/dev/null 2>&1 || true

	if ! layout_valid "$staged"; then
		fail_save_with_recovery 'Resurrect did not produce a valid layout for this transaction'
		return 1
	fi
	if ! archive_valid "$dir/pane_contents.tar.gz"; then
		fail_save_with_recovery 'Resurrect did not produce valid pane contents for this transaction'
		return 1
	fi
	if ! "$ASSISTANT_SAVE" || ! assistant_json_valid "$dir/assistant-sessions.json"; then
		fail_save_with_recovery 'assistant session mapping failed for this transaction'
		return 1
	fi
	if ! publish_generation "$staged" "$planned"; then
		fail_save_with_recovery 'coherent generation publication failed validation'
		return 1
	fi
	point_last "$planned" || {
		fail_save_with_recovery 'could not commit the new last pointer'
		return 1
	}
	discard_save_backups || {
		fail_save_with_recovery 'could not discard save-transaction backups'
		return 1
	}
	if ! cleanup_transaction_artifacts "$planned" yes "$previous" "$rollback"; then
		mark_save_error 'generation committed but transaction artifacts could not be cleaned'
		return 1
	fi
	if ! rm -f "$journal" || ! durability_barrier "$dir"; then
		mark_save_error 'generation committed but its transaction journal could not be removed'
		return 1
	fi
	if ! prune_generations; then
		mark_save_error 'generation committed but retention cleanup failed'
		return 1
	fi
	clear_save_error
	tmux_no_start set-option -gq @shell-setup-persistence-last-save "$(date -u +%Y-%m-%dT%H:%M:%SZ)" 2>/dev/null || true
	if [ "$allow_seed" = yes ] && [ "$phase" != ready ]; then
		set_phase ready 'live topology seeded explicitly' "$planned"
	fi
	log "save committed: $planned"
	[ "$quiet" = yes ] || show_tmux_message "Tmux environment saved: $planned"
}

save_command() {
	local quiet=no seed=no coalesce=no timeout=$SAVE_LOCK_TIMEOUT lock_status
	case "$timeout" in *[!0-9]* | '') timeout=30 ;; esac
	while [ "$#" -gt 0 ]; do
		case "$1" in
		--quiet) quiet=yes ;;
		--coalesce) coalesce=yes; timeout=0 ;;
		--seed) seed=yes ;;
		*) printf 'unknown save option: %s\n' "$1" >&2; return 2 ;;
		esac
		shift
	done
	prepare_tmux_environment || { log 'save refused: tmux server is unavailable'; return 1; }
	assert_managed_socket || return 1
	acquire_lock "$timeout"
	lock_status=$?
	if [ "$lock_status" -ne 0 ]; then
		if [ "$lock_status" -eq 75 ]; then
			if [ "$coalesce" = yes ]; then
				log 'save coalesced: another persistence operation holds the lock'
				return 0
			fi
			log 'save delayed: another persistence operation still holds the lock'
			[ "$quiet" = yes ] || show_tmux_message 'another tmux persistence operation is still running'
			return 75
		fi
		mark_save_error 'persistence lock is unavailable'
		return 1
	fi
	save_locked "$seed" "$quiet"
}

post_save_layout_hook() {
	local source=${1:-} destination=${TMUX_PERSISTENCE_STAGED_LAYOUT:-}
	[ "${TMUX_PERSISTENCE_LOCK_HELD:-}" = 1 ] || return 1
	assert_managed_socket || return 1
	[ -n "$source" ] && [ -n "$destination" ] && layout_valid "$source" || return 1
	atomic_copy "$source" "$destination" && layout_valid "$destination" || return 1
	printf '%s\n' "$source" >"$destination.source"
}

topology_counts() {
	awk -F '\t' '
		$1 == "pane" { panes++; sessions[$2] = 1 }
		$1 == "window" { windows++; sessions[$2] = 1 }
		$1 == "grouped_session" { sessions[$2] = 1 }
		END { for (s in sessions) n++; printf "%d\t%d\t%d\n", n, windows, panes }
	' "$1"
}

collapse_reason() {
	local candidate=$1 previous=$2 cs cw cp ps pw pp
	IFS=$'\t' read -r cs cw cp < <(topology_counts "$candidate")
	IFS=$'\t' read -r ps pw pp < <(topology_counts "$previous")
	if { [ "$pp" -gt 0 ] && [ "$cp" -eq 0 ]; } || \
	   { [ "$pp" -ge 8 ] && [ $((cp * 3)) -le "$pp" ] && [ $((pp - cp)) -ge 6 ]; } || \
	   { [ "$pw" -ge 6 ] && [ $((cw * 3)) -le "$pw" ] && [ $((pw - cw)) -ge 4 ]; } || \
	   { [ "$ps" -ge 4 ] && [ $((cs * 3)) -le "$ps" ] && [ $((ps - cs)) -ge 3 ]; }; then
		printf 'candidate topology collapsed from %s sessions/%s windows/%s panes to %s/%s/%s' \
			"$ps" "$pw" "$pp" "$cs" "$cw" "$cp"
		return 0
	fi
	return 1
}

select_candidate() {
	local dir candidate fallback
	dir=$(resurrect_dir)
	candidate=$(last_basename 2>/dev/null || true)
	if [ -n "$candidate" ] && is_managed_layout "$candidate" && \
	   generation_complete "$candidate" "$dir"; then
		printf '%s\n' "$candidate"
		return 0
	fi
	# A raw layout discovered by a scan may be the uncommitted output of an
	# interrupted save, so automatic repair requires a full triplet.
	fallback=$(restorable_layout newest "$candidate" || true)
	[ -n "$fallback" ] || return 1
	point_last "$fallback" || return 1
	log "repaired last pointer to $fallback"
	printf '%s\n' "$fallback"
}


stage_restore_companions() {
	local dir target pane assistant
	dir=$(resurrect_dir)
	target=$1
	[ -n "$target" ] && generation_complete "$target" "$dir" || return 1
	mkdir_state || return 1
	pane=$(pane_companion "$target")
	assistant=$(assistant_companion "$target")
	atomic_copy "$pane" "$dir/pane_contents.tar.gz" || return 1
	atomic_copy "$assistant" "$dir/assistant-sessions.json" || return 1
	archive_valid "$dir/pane_contents.tar.gz" || return 1
	assistant_json_valid "$dir/assistant-sessions.json" || return 1
	log "restore companions staged: $target"
}


pre_restore_hook() {
	local target
	[ "${TMUX_PERSISTENCE_LOCK_HELD:-}" = 1 ] || return 1
	assert_managed_socket || return 1
	target=${TMUX_PERSISTENCE_RESTORE_TARGET:-$(last_basename 2>/dev/null || true)}
	[ -z "${TMUX_PERSISTENCE_PRE_RESTORE_MARKER:-}" ] || rm -f "$TMUX_PERSISTENCE_PRE_RESTORE_MARKER"
	set_phase restoring "restoring $target" "$target"
	if [ -n "${TMUX_PERSISTENCE_PRE_RESTORE_MARKER:-}" ]; then
		printf 'ok\n' >"$TMUX_PERSISTENCE_PRE_RESTORE_MARKER"
	fi
}

write_expected_signature() {
	awk -F '\t' 'BEGIN { OFS = "\t" }
		$1 == "pane" {
			sessions[$2] = 1
			pkey = $2 OFS $3 OFS $6
			panes[pkey] = 1
			wkey = $2 OFS $3
			counts[wkey]++
			dir = $8; sub(/^:/, "", dir); gsub(/\\ /, " ", dir)
			cwd[pkey] = dir
		}
		$1 == "window" { sessions[$2] = 1; windows[$2 OFS $3] = 1 }
		$1 == "grouped_session" { groups[$2] = $3; sessions[$2] = 1 }
		END {
			for (s in sessions) print "S", s
			for (w in windows) print "W", w
			for (p in panes) { print "P", p; print "D", p, cwd[p] }
			for (w in counts) print "C", w, counts[w]
			for (g in groups) {
				o = groups[g]
				for (w in windows) {
					split(w, a, OFS)
					if (a[1] == o) print "W", g, a[2]
				}
				for (p in panes) {
					split(p, a, OFS)
					if (a[1] == o) {
						print "P", g, a[2], a[3]
						print "D", g, a[2], a[3], cwd[p]
					}
				}
				for (w in counts) {
					split(w, a, OFS)
					if (a[1] == o) print "C", g, a[2], counts[w]
				}
			}
		}
	' "$1" | LC_ALL=C sort
}

write_actual_signature() {
	local tmp=$1
	: >"$tmp"
	tmux_no_start list-sessions -F $'S\t#{session_name}' >>"$tmp" 2>/dev/null || true
	tmux_no_start list-windows -a -F $'W\t#{session_name}\t#{window_index}' >>"$tmp" 2>/dev/null || true
	tmux_no_start list-panes -a -F $'P\t#{session_name}\t#{window_index}\t#{pane_index}' >>"$tmp" 2>/dev/null || true
	tmux_no_start list-panes -a -F $'D\t#{session_name}\t#{window_index}\t#{pane_index}\t#{pane_current_path}' >>"$tmp" 2>/dev/null || true
	tmux_no_start list-panes -a -F $'#{session_name}\t#{window_index}' 2>/dev/null | \
		awk -F '\t' 'BEGIN { OFS="\t" } { count[$1 OFS $2]++ } END { for (w in count) print "C", w, count[w] }' >>"$tmp" || true
	LC_ALL=C sort "$tmp"
}

verify_restore() {
	local target=$1 dir tmp expected actual expected_topology actual_topology diff_file
	VERIFY_CWD_MISMATCH=no
	VERIFY_FAILURE_DETAIL=
	dir=$(resurrect_dir)
	if ! mkdir_state; then
		VERIFY_FAILURE_DETAIL="cannot create persistence state directory: $STATE_DIR"
		log "$VERIFY_FAILURE_DETAIL"
		return 2
	fi
	tmp=$(mktemp -d "$STATE_DIR/verify.XXXXXX") || {
		VERIFY_FAILURE_DETAIL="cannot create restore-verification workspace in $STATE_DIR"
		log "$VERIFY_FAILURE_DETAIL"
		return 2
	}
	expected=$tmp/expected
	actual=$tmp/actual
	expected_topology=$tmp/expected-topology
	actual_topology=$tmp/actual-topology
	diff_file=$STATE_DIR/last-restore.diff
	if ! write_expected_signature "$dir/$target" >"$expected" || \
	   ! write_actual_signature "$tmp/actual.unsorted" >"$actual" || \
	   ! awk -F '\t' '$1 != "D"' "$expected" >"$expected_topology" || \
	   ! awk -F '\t' '$1 != "D"' "$actual" >"$actual_topology"; then
		rm -rf "$tmp"
		VERIFY_FAILURE_DETAIL='could not build restore-verification signatures'
		log "$VERIFY_FAILURE_DETAIL"
		return 2
	fi
	if ! cmp -s "$expected_topology" "$actual_topology"; then
		if ! diff -u "$expected" "$actual" >"$diff_file"; then
			[ -f "$diff_file" ] || {
				rm -rf "$tmp"
				VERIFY_FAILURE_DETAIL="cannot write restore diff: $diff_file"
				log "$VERIFY_FAILURE_DETAIL"
				return 2
			}
		fi
		rm -rf "$tmp"
		return 1
	fi
	if cmp -s "$expected" "$actual"; then
		rm -rf "$tmp"
		rm -f "$diff_file"
		return 0
	fi
	diff -u "$expected" "$actual" >"$diff_file" || true
	rm -rf "$tmp"
	VERIFY_CWD_MISMATCH=yes
	log "restore topology verified; pane cwd differs (see $diff_file)"
	return 0
}

validate_current_command() {
	local target dir lock_status verify_status=0
	prepare_tmux_environment || { printf '%s\n' 'tmux server is unavailable' >&2; return 1; }
	assert_managed_socket || return 1
	acquire_lock 30
	lock_status=$?
	[ "$lock_status" -eq 0 ] || {
		[ "$lock_status" -eq 75 ] && printf '%s\n' 'another persistence operation is running' >&2 || \
			printf '%s\n' 'persistence lock is unavailable' >&2
		return 1
	}
	recover_transaction || { printf '%s\n' 'save transaction recovery failed' >&2; return 1; }
	dir=$(resurrect_dir)
	target=$(last_basename 2>/dev/null || true)
	if [ -z "$target" ] || ! is_managed_layout "$target" || ! generation_complete "$target" "$dir"; then
		printf '%s\n' 'last does not point to a complete managed generation' >&2
		return 1
	fi
	verify_restore "$target" || verify_status=$?
	case "$verify_status" in
	0) ;;
	1)
		printf 'managed generation does not match the live topology; inspect %s\n' \
			"$STATE_DIR/last-restore.diff" >&2
		return 1
		;;
	*)
		printf 'managed generation could not be verified: %s\n' \
			"${VERIFY_FAILURE_DETAIL:-unknown verification error}" >&2
		return 1
		;;
	esac
	if [ "$VERIFY_CWD_MISMATCH" = yes ]; then
		printf 'valid managed topology with pane cwd differences: %s (inspect %s)\n' \
			"$target" "$STATE_DIR/last-restore.diff"
	else
		printf 'valid managed generation: %s\n' "$target"
	fi
}

post_restore_hook() {
	local target=${TMUX_PERSISTENCE_RESTORE_TARGET:-$(last_basename 2>/dev/null || true)}
	local verified=no verify_status=0
	assert_managed_socket || return 1
	if [ -n "${TMUX_PERSISTENCE_PRE_RESTORE_MARKER:-}" ] && \
	   [ ! -f "$TMUX_PERSISTENCE_PRE_RESTORE_MARKER" ]; then
		set_phase degraded 'generation sidecars could not be staged before restore' "$target"
		return 1
	fi
	if [ "${TMUX_PERSISTENCE_LOCK_HELD:-}" != 1 ]; then
		set_phase degraded 'restore bypassed the persistence coordinator lock' "$target"
		return 1
	fi
	set_phase verifying "verifying $target" "$target"
	verify_restore "$target" || verify_status=$?
	if [ "$verify_status" -eq 0 ]; then
		verified=yes
	fi
	if [ "$verified" = yes ]; then
		if [ -x "$ASSISTANT_RESTORE" ]; then
			"$ASSISTANT_RESTORE" || log 'assistant resume hook failed (restore verification is unaffected)'
		else
			log "assistant restore script missing: $ASSISTANT_RESTORE"
		fi
	fi
	[ -z "${TMUX_PERSISTENCE_PRE_RESTORE_MARKER:-}" ] || rm -f "$TMUX_PERSISTENCE_PRE_RESTORE_MARKER"
	set_client_attachable yes || true
	if [ "$verified" = yes ]; then
		if [ "$VERIFY_CWD_MISMATCH" = yes ]; then
			set_phase ready "restore topology verified; pane cwd differs; inspect $STATE_DIR/last-restore.diff" "$target"
		else
			set_phase ready "restore verified" "$target"
		fi
	else
		if [ "$verify_status" -eq 1 ]; then
			set_phase degraded "restored topology differs; inspect $STATE_DIR/last-restore.diff" "$target"
		else
			set_phase degraded "restored topology could not be verified: ${VERIFY_FAILURE_DETAIL:-unknown verification error}" "$target"
		fi
	fi
}

restore_locked() {
	local accept_risk=$1 quiet=$2 dir target previous reason phase pre_marker
	dir=$(resurrect_dir)
	ensure_resurrect_dir "$dir" || {
		set_phase error "persistence data directory is unavailable: $dir"
		return 1
	}
	assert_managed_socket || { set_phase error 'refusing to restore a non-production tmux socket'; return 1; }
	recover_transaction || {
		set_phase error 'an interrupted save transaction could not be recovered; journal retained'
		return 1
	}
	if [ ! -x "$PYTHON_BIN" ] || [ ! -x "$RESURRECT_SAVE" ] || \
	   [ ! -x "$RESURRECT_RESTORE" ] || [ ! -x "$ASSISTANT_SAVE" ]; then
		set_phase error 'persistence save/restore dependencies are unavailable'
		return 1
	fi
	if ! target=$(select_candidate); then
		if [ -z "$(list_layouts)" ]; then
			set_client_attachable yes || true
			set_phase ready 'no saved environment; starting fresh'
			return 0
		fi
		set_phase needs-review "saved layouts exist but none is a complete managed generation or the valid last target; repoint $dir/last explicitly"
		return 0
	fi
	previous=$(restorable_layout older "$target" || true)
	if [ "$accept_risk" != yes ] && [ -n "$previous" ]; then
		reason=$(collapse_reason "$dir/$target" "$dir/$previous" || true)
		if [ -n "$reason" ]; then
			set_phase needs-review "$reason; run $SCRIPT_DIR/tmux-persistence.sh restore --accept-risk or repoint last" "$target"
			[ "$quiet" = yes ] || show_tmux_message 'Restore needs review; saves are paused'
			return 0
		fi
	fi
	[ -x "$RESURRECT_RESTORE" ] || {
		set_phase error "Resurrect restore script is missing: $RESURRECT_RESTORE" "$target"
		return 1
	}
	point_last "$target" || return 1
	prepare_tmux_environment || { set_phase error 'tmux server is unavailable' "$target"; return 1; }
	export TMUX_PERSISTENCE_LOCK_HELD=1
	export TMUX_PERSISTENCE_RESTORE_TARGET=$target
	if ! clear_pane_scratch restore; then
		set_phase degraded 'could not clear Resurrect restore scratch space' "$target"
		return 0
	fi
	if ! stage_restore_companions "$target"; then
		set_phase degraded 'generation sidecars could not be staged safely' "$target"
		return 0
	fi
	# Debris from a killed restore. Restores are lock-serialized, so nothing
	# this old can belong to a live operation.
	find "$STATE_DIR" -maxdepth 1 -mmin +60 \
		\( -name 'verify.*' -o -name 'pre-restore.*.ok' -o -name 'runtime.tsv.*' \) \
		-exec rm -rf {} + 2>/dev/null || true
	pre_marker=$STATE_DIR/pre-restore.$$.ok
	rm -f "$pre_marker"
	export TMUX_PERSISTENCE_PRE_RESTORE_MARKER=$pre_marker
	set_phase restoring "restoring $target" "$target"
	"$RESURRECT_RESTORE" >/dev/null 2>&1 || true
	phase=$(current_phase || true)
	if [ "$phase" = restoring ] || [ "$phase" = verifying ]; then
		set_phase degraded 'Resurrect did not complete restore verification' "$target"
	fi
	rm -f "$pre_marker"
	phase=$(current_phase || true)
	[ "$quiet" = yes ] || {
		case "$phase" in
		ready) show_tmux_message "Tmux restore verified: $target" ;;
		*) show_tmux_message "Tmux restore is $phase; saves remain paused" ;;
		esac
	}
}

restore_command() {
	local accept=no quiet=no timeout=30 lock_status claim_status
	while [ "$#" -gt 0 ]; do
		case "$1" in
		--accept-risk) accept=yes ;;
		--quiet | --startup) quiet=yes ;;
		*) printf 'unknown restore option: %s\n' "$1" >&2; return 2 ;;
		esac
		shift
	done
	prepare_tmux_environment || { log 'restore refused: tmux server is unavailable'; return 1; }
	assert_managed_socket || return 1
	acquire_lock "$timeout"
	lock_status=$?
	if [ "$lock_status" -ne 0 ]; then
		if [ "$lock_status" -eq 75 ]; then
			log 'restore refused: another persistence operation holds the lock'
			[ "$quiet" = yes ] || show_tmux_message 'another tmux persistence operation is running'
		else
			set_phase error 'persistence lock is unavailable'
		fi
		return 1
	fi
	wait_for_pending_client_claims
	claim_status=$?
	if [ "$claim_status" -ne 0 ]; then
		if [ "$claim_status" -eq 75 ]; then
			log 'restore deferred: a client attachment is still in progress'
			[ "$quiet" = yes ] || show_tmux_message 'tmux restore deferred while a client attaches'
		else
			log 'restore refused: client-claim state could not be inspected safely'
			[ "$quiet" = yes ] || show_tmux_message 'tmux restore could not verify pending client claims'
		fi
		return "$claim_status"
	fi
	restore_locked "$accept" "$quiet"
}

acknowledge_command() {
	local phase detail lock_status
	prepare_tmux_environment || return 1
	assert_managed_socket || return 1
	acquire_lock 30
	lock_status=$?
	[ "$lock_status" -eq 0 ] || {
		[ "$lock_status" -eq 75 ] && printf '%s\n' 'another persistence operation is running' >&2 || \
			printf '%s\n' 'persistence lock is unavailable' >&2
		return 1
	}
	phase=$(current_phase || true)
	case "$phase" in
	degraded)
		set_phase ready 'degraded live state explicitly acknowledged'
		show_tmux_message 'Tmux persistence re-enabled for the current live state'
		;;
	needs-review)
		printf 'candidate has not been restored; use: %s restore --accept-risk\n' "$SCRIPT_DIR/tmux-persistence.sh" >&2
		return 1
		;;
	ready)
		detail=$(tmux_no_start show-option -gqv @shell-setup-persistence-save-error 2>/dev/null || true)
		if [ -n "$detail" ]; then
			printf 'the save error remains visible until a save succeeds: %s\n' "$detail" >&2
			return 1
		fi
		;;
	*)
		printf 'cannot acknowledge persistence state: %s\n' "${phase:-unset}" >&2
		return 1
		;;
	esac
}

client_ready_command() {
	local attempts=${TMUX_PERSISTENCE_READY_ATTEMPTS:-50}
	local delay=${TMUX_PERSISTENCE_READY_DELAY:-0.2}
	local phase= detail= i=0
	case "$attempts" in *[!0-9]* | '') attempts=50 ;; esac
	while [ "$i" -lt "$attempts" ]; do
		phase=$(tmux_no_start show-option -gqv @shell-setup-persistence-state 2>/dev/null || true)
		if client_attachable "$phase"; then
			return 0
		fi
		case "$phase" in
		needs-review | degraded | error)
			detail=$(tmux_no_start show-option -gqv @shell-setup-persistence-detail 2>/dev/null || true)
			break
			;;
		esac
		sleep "$delay"
		i=$((i + 1))
	done
	if [ -z "$detail" ] && [ -f "$RUNTIME_STATE" ]; then
		detail=$(cut -f5- "$RUNTIME_STATE" 2>/dev/null || true)
		[ -z "$detail" ] || detail="last recorded state: $detail"
	fi
	printf 'tmux is not ready%s; continuing in a plain shell.\n' "${detail:+: $detail}" >&2
	return 1
}

wait_ready_command() {
	local attempts=${TMUX_PERSISTENCE_ADMIN_READY_ATTEMPTS:-600}
	local delay=${TMUX_PERSISTENCE_READY_DELAY:-0.2}
	local phase= detail= i=0
	case "$attempts" in *[!0-9]* | '') attempts=600 ;; esac
	while [ "$i" -lt "$attempts" ]; do
		phase=$(tmux_no_start show-option -gqv @shell-setup-persistence-state 2>/dev/null || true)
		case "$phase" in
		ready) return 0 ;;
		needs-review | degraded | error | stopping | stopped | foreign-server)
			detail=$(tmux_no_start show-option -gqv @shell-setup-persistence-detail 2>/dev/null || true)
			printf 'tmux persistence reached %s%s.\n' "$phase" "${detail:+: $detail}" >&2
			return 1
			;;
		esac
		sleep "$delay"
		i=$((i + 1))
	done
	if [ -f "$RUNTIME_STATE" ]; then
		detail=$(cut -f5- "$RUNTIME_STATE" 2>/dev/null || true)
		[ -z "$detail" ] || detail="last recorded state: $detail"
	fi
	printf 'tmux persistence did not become ready%s.\n' "${detail:+: $detail}" >&2
	return 1
}

scheduler_command() {
	local interval=${TMUX_PERSISTENCE_INTERVAL:-900} retry=$SCHEDULER_RETRY_DELAY delay child= status
	case "$interval" in *[!0-9]* | '') interval=900 ;; esac
	case "$retry" in *[!0-9]* | '') retry=60 ;; esac
	delay=$interval
	trap '[ -z "${child:-}" ] || kill "$child" 2>/dev/null; exit 0' INT TERM HUP
	while server_pid >/dev/null 2>&1; do
		sleep "$delay" & child=$!
		wait "$child" || return 1
		child=
		server_pid >/dev/null 2>&1 || break
		if "$0" save --quiet; then
			delay=$interval
		else
			status=$?
			if [ "$status" -eq 75 ]; then
				log "scheduled save will retry in $retry seconds after lock contention"
				delay=$retry
			else
				delay=$interval
			fi
		fi
	done
}

status_command() {
	local phase detail target last_save save_error
	phase=$(current_phase || printf unavailable)
	detail=$(tmux_no_start show-option -gqv @shell-setup-persistence-detail 2>/dev/null || true)
	target=$(tmux_no_start show-option -gqv @shell-setup-persistence-target 2>/dev/null || true)
	last_save=$(tmux_no_start show-option -gqv @shell-setup-persistence-last-save 2>/dev/null || true)
	save_error=$(tmux_no_start show-option -gqv @shell-setup-persistence-save-error 2>/dev/null || true)
	printf 'state: %s\n' "$phase"
	[ -z "$target" ] || printf 'target: %s\n' "$target"
	[ -z "$detail" ] || printf 'detail: %s\n' "$detail"
	[ -z "$last_save" ] || printf 'last save: %s\n' "$last_save"
	[ -z "$save_error" ] || printf 'save error: %s\n' "$save_error"
	printf 'log: %s\n' "$LOG_FILE"
}

state_command() {
	local phase=${1:?phase required}
	prepare_tmux_environment || return 1
	assert_managed_socket || return 1
	case "$phase" in
	booting | restoring | verifying | stopping | error | needs-review)
		set_client_attachable no || true
		;;
	esac
	set_phase "$phase" "${2:-}" "${3:-}"
}

save_error_command() {
	prepare_tmux_environment || return 1
	assert_managed_socket || return 1
	mark_save_error "${1:?detail required}"
}

usage() {
	cat >&2 <<'EOF'
usage: tmux-persistence.sh COMMAND
  save [--quiet] [--coalesce] [--seed]
                                  publish a coherent generation
  restore [--quiet] [--accept-risk]
  post-save-layout PATH | pre-restore | post-restore
  client-ready                  bounded live-server readiness check
  wait-ready                    strict administrative readiness check
  claim quick|regular           reserve one detached/new client session
  release-claim SESSION TOKEN   release a matching client reservation
  scheduler                     periodic save loop
  acknowledge                   accept a degraded live restore
  state PHASE [DETAIL]          set an owned server state
  record-state PHASE PID DETAIL write diagnostics without touching a server
  save-error DETAIL               record a loud scheduler/save failure
  status                        show persistence health
  validate-current              validate last's triplet and live topology
  prune                         enforce retained-generation count
EOF
}

command=${1:-}
[ "$#" -eq 0 ] || shift
case "$command" in
save) save_command "$@" ;;
restore) restore_command "$@" ;;
startup) restore_command --startup "$@" ;;
post-save-layout) post_save_layout_hook "$@" ;;
pre-restore) pre_restore_hook "$@" ;;
post-restore) post_restore_hook "$@" ;;
client-ready) client_ready_command "$@" ;;
wait-ready) wait_ready_command "$@" ;;
claim) claim_session_command "$@" ;;
release-claim) release_claim_command "$@" ;;
scheduler) scheduler_command "$@" ;;
acknowledge) acknowledge_command "$@" ;;
state) state_command "$@" ;;
record-state) record_external_state "${1:?phase required}" "${2:-0}" "${3:-}" ;;
save-error) save_error_command "$@" ;;
status) status_command "$@" ;;
validate-current) validate_current_command "$@" ;;
prune) prepare_tmux_environment && assert_managed_socket && acquire_lock 30 && recover_transaction && prune_generations ;;
*) usage; exit 2 ;;
esac
