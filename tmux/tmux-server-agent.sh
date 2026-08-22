#!/usr/bin/env bash
# launchd entry point for the default tmux server. This supervisor owns the
# foreground server, guarded startup restore, and periodic-save scheduler.

set -uo pipefail

TMUX_BIN=${TMUX_PERSISTENCE_TMUX_BIN:-${TMUX_BIN:-}}
[ -n "$TMUX_BIN" ] || TMUX_BIN=$(command -v tmux 2>/dev/null || true)
PERSISTENCE=${TMUX_PERSISTENCE_SCRIPT:-$HOME/.shell-setup/tmux-persistence.sh}
LOG=${TMUX_SERVER_AGENT_LOG:-$HOME/Library/Logs/tmux-server-agent.log}
FOREIGN_POLL=${TMUX_PERSISTENCE_FOREIGN_POLL:-5}
FOREIGN_ATTEMPTS=${TMUX_PERSISTENCE_FOREIGN_ATTEMPTS:-60}
START_ATTEMPTS=${TMUX_PERSISTENCE_START_ATTEMPTS:-100}
START_DELAY=${TMUX_PERSISTENCE_START_DELAY:-0.05}
SCHEDULER_RETRY=${TMUX_PERSISTENCE_SCHEDULER_RETRY:-30}

mkdir -p "$(dirname "$LOG")"
exec >>"$LOG" 2>&1
unset TMUX TMUX_PANE
if [ -z "${TMUX_PERSISTENCE_SOCKET_PATH:-}" ] && [ -z "${TMUX_PERSISTENCE_SOCKET_NAME:-}" ]; then
	unset TMUX_TMPDIR
fi

tmux_no_start() {
	if [ -n "${TMUX_PERSISTENCE_SOCKET_PATH:-}" ]; then
		"$TMUX_BIN" -N -S "$TMUX_PERSISTENCE_SOCKET_PATH" "$@"
	elif [ -n "${TMUX_PERSISTENCE_SOCKET_NAME:-}" ]; then
		"$TMUX_BIN" -N -L "$TMUX_PERSISTENCE_SOCKET_NAME" "$@"
	else
		env -u TMUX -u TMUX_PANE -u TMUX_TMPDIR "$TMUX_BIN" -N -L default "$@"
	fi
}

server_pid() {
	tmux_no_start display-message -p '#{pid}' 2>/dev/null
}

record_external() {
	"$PERSISTENCE" record-state "$1" "${2:-0}" "${3:-}" 2>/dev/null || true
}

server_child=
scheduler_child=
owned=no
stopping=no

stop_children() {
	[ "$stopping" = no ] || return
	stopping=yes
	# Stop the scheduler first so it cannot contend with the final save.
	if [ -n "$scheduler_child" ] && kill -0 "$scheduler_child" 2>/dev/null; then
		kill -TERM "$scheduler_child" 2>/dev/null || true
		wait "$scheduler_child" 2>/dev/null || true
	fi
	if [ "$owned" = yes ] && [ "$(server_pid || true)" = "$server_child" ]; then
		# Shutdown has no later tick, so a detach save that coalesced away for
		# lock contention is only recoverable here. A save is refused unless the
		# phase is still ready, so it must run before the server is marked
		# stopping, and briefly: launchd will SIGKILL if this drags.
		TMUX_PERSISTENCE_SAVE_LOCK_TIMEOUT=5 "$PERSISTENCE" save --quiet 2>/dev/null || true
		"$PERSISTENCE" state stopping 'launchd server is stopping' 2>/dev/null || true
	fi
	if [ -n "$server_child" ] && kill -0 "$server_child" 2>/dev/null; then
		kill -TERM "$server_child" 2>/dev/null || true
		wait "$server_child" 2>/dev/null || true
	fi
	record_external stopped 0 'launchd server stopped'
}

trap 'stop_children; exit 0' INT TERM HUP

[ -n "$TMUX_BIN" ] && [ -x "$TMUX_BIN" ] || { echo "[$(date)] tmux executable is unavailable"; exit 1; }
[ -x "$PERSISTENCE" ] || { echo "[$(date)] persistence coordinator missing: $PERSISTENCE"; exit 1; }

# Never restore into or kill a server this launchd job did not start. Automatic
# Ghostty clients use tmux -N, so on a normal login this state is only possible
# during migration or after an explicit manual server start.
# Bounded: an orphaned server that outlives its supervisor would otherwise
# stall this loop forever, silently stopping every periodic save. Give up so
# launchd records a failed start and throttles the retry.
foreign_polls=0
foreign_logged=
while foreign_pid=$(server_pid); do
	if [ "$foreign_pid" != "$foreign_logged" ]; then
		echo "[$(date)] waiting for foreign tmux server pid=$foreign_pid"
		record_external foreign-server "$foreign_pid" 'waiting for the unowned default server to exit'
		foreign_logged=$foreign_pid
	fi
	if [ "$foreign_polls" -ge "$FOREIGN_ATTEMPTS" ]; then
		echo "[$(date)] giving up: foreign tmux server pid=$foreign_pid still owns the socket after $FOREIGN_ATTEMPTS polls"
		record_external foreign-server "$foreign_pid" 'unowned default server never exited; no supervisor is saving this server'
		exit 1
	fi
	foreign_polls=$((foreign_polls + 1))
	sleep "$FOREIGN_POLL"
done

args=()
if [ -n "${TMUX_PERSISTENCE_SOCKET_PATH:-}" ]; then
	args+=( -S "$TMUX_PERSISTENCE_SOCKET_PATH" )
elif [ -n "${TMUX_PERSISTENCE_SOCKET_NAME:-}" ]; then
	args+=( -L "$TMUX_PERSISTENCE_SOCKET_NAME" )
fi
if [ -n "${TMUX_PERSISTENCE_CONFIG:-}" ]; then
	args+=( -f "$TMUX_PERSISTENCE_CONFIG" )
fi
args+=( -D )

echo "[$(date)] starting launchd-owned tmux server"
"$TMUX_BIN" "${args[@]}" &
server_child=$!

i=0
connected_pid=
connected_socket=
while [ "$i" -lt "$START_ATTEMPTS" ]; do
	if ! kill -0 "$server_child" 2>/dev/null; then break; fi
	connected_pid=$(server_pid || true)
	if [ "$connected_pid" = "$server_child" ]; then
		connected_socket=$(tmux_no_start display-message -p '#{socket_path}' 2>/dev/null || true)
		[ -n "$connected_socket" ] && break
	fi
	connected_pid=
	connected_socket=
	sleep "$START_DELAY"
	i=$((i + 1))
done

if [ "$connected_pid" != "$server_child" ]; then
	echo "[$(date)] server ownership check failed (child=$server_child connected=${connected_pid:-none})"
	record_external error "$server_child" 'tmux server ownership check failed'
	if kill -0 "$server_child" 2>/dev/null; then kill -TERM "$server_child" 2>/dev/null || true; fi
	wait "$server_child" 2>/dev/null || true
	exit 1
fi

owned=yes
export TMUX_PERSISTENCE_EXPECTED_PID=$server_child
export TMUX_PERSISTENCE_EXPECTED_SOCKET=$connected_socket
"$PERSISTENCE" state booting 'launchd owns the tmux server' || {
	echo "[$(date)] could not initialize persistence state"
	stop_children
	exit 1
}
"$PERSISTENCE" startup || {
	echo "[$(date)] startup restore command failed; saves remain paused"
	"$PERSISTENCE" state error 'startup restore command failed; inspect persistence log' 2>/dev/null || true
}

"$PERSISTENCE" scheduler &
scheduler_child=$!

while kill -0 "$server_child" 2>/dev/null; do
	if kill -0 "$scheduler_child" 2>/dev/null; then
		sleep 1
		continue
	fi
	wait "$scheduler_child" 2>/dev/null || true
	echo "[$(date)] persistence scheduler exited; saves paused while it is retried"
	"$PERSISTENCE" save-error 'periodic-save scheduler exited unexpectedly; retrying' 2>/dev/null || true
	sleep "$SCHEDULER_RETRY"
	kill -0 "$server_child" 2>/dev/null || break
	"$PERSISTENCE" scheduler &
	scheduler_child=$!
done

if kill -0 "$scheduler_child" 2>/dev/null; then
	kill -TERM "$scheduler_child" 2>/dev/null || true
	wait "$scheduler_child" 2>/dev/null || true
fi
wait "$server_child" 2>/dev/null
status=$?
record_external stopped 0 "tmux server exited with status $status"
exit "$status"
