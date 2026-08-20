#!/bin/sh
# Assistant activity hook: record what the assistant running in this pane is
# doing, so the tmux window label can show it. Writes per-pane tmux options:
#
#   @assistant-state     busy | input | idle
#   @assistant-state-at  epoch of the last write — busy TTL, and focus ordering
#   @assistant-pid       the assistant process: liveness, and finding its tools
#   @assistant-pending   input | done — an unconsumed "look at this pane" mark
#
# status-refresh.sh aggregates these into the @assistant-window option the
# window-status formats color from; focus-pending.sh consumes @assistant-pending.
# Registered for both assistants (~/.claude/settings.json, ~/.codex/hooks.json).
#
# Presence of @assistant-state is also what tells the loop this pane's assistant
# reports through hooks, so it can stop trusting the pane title's spinner glyph
# for it. A pane with no state at all keeps the glyph fallback.
#
# This runs on EVERY tool call: keep it at two forks (`date` plus one chained
# `tmux set`), no jq, and no reading state back. Never print to stdout —
# SessionStart stdout is injected into the conversation as context.
#
# Usage: set-state.sh start <claude|codex> | tool-start | busy | input
#                     | idle | end
set -u

[ -n "${TMUX_PANE:-}" ] || exit 0
command -v tmux >/dev/null 2>&1 || exit 0

action="${1:-}"
p="$TMUX_PANE"

# Walk up to the nearest ancestor that is the assistant. Hooks may be spawned
# through an intermediate shell, so $PPID isn't necessarily it. The NEAREST
# match is enough here (the pid is only used for liveness and to spot a tool's
# child shell) — unlike lib.sh's find_agent_pid, which needs the outermost
# process because it identifies a session.
assistant_pid() {
	tool="$1" walk="$PPID" depth=6
	[ -n "$tool" ] || { echo "$PPID"; return; }
	while [ "$depth" -gt 0 ] && [ "${walk:-1}" -gt 1 ]; do
		case $(ps -o comm= -p "$walk" 2>/dev/null) in
		"$tool" | */"$tool")
			echo "$walk"
			return
			;;
		esac
		walk=$(ps -o ppid= -p "$walk" 2>/dev/null | tr -d ' ')
		depth=$((depth - 1))
	done
	echo "$PPID"
}

# PreToolUse fires for every tool, including the ones that hand control back to
# you. One hook decides which, rather than a general hook plus a matcher hook
# for those tools: both would fire for them, in either order, and the loser's
# write would win. Shell patterns over the raw payload keep it fork-free; the
# two spacings cover compact and pretty-printed JSON.
if [ "$action" = tool-start ]; then
	payload=$(cat 2>/dev/null) || payload=""
	case $payload in
	*'"tool_name":"AskUserQuestion"'* | *'"tool_name": "AskUserQuestion"'* | \
		*'"tool_name":"ExitPlanMode"'* | *'"tool_name": "ExitPlanMode"'*)
		action=input
		;;
	esac
fi

now=$(date +%s)

case "$action" in
start)
	tmux set -p -t "$p" @assistant-state idle \; \
		set -p -t "$p" @assistant-state-at "$now" \; \
		set -p -t "$p" @assistant-pid "$(assistant_pid "${2:-}")" \; \
		set -up -t "$p" @assistant-pending 2>/dev/null
	;;
tool-start | busy)
	tmux set -p -t "$p" @assistant-state busy \; \
		set -p -t "$p" @assistant-state-at "$now" 2>/dev/null
	;;
input)
	tmux set -p -t "$p" @assistant-state input \; \
		set -p -t "$p" @assistant-state-at "$now" \; \
		set -p -t "$p" @assistant-pending input 2>/dev/null
	;;
idle)
	tmux set -p -t "$p" @assistant-state idle \; \
		set -p -t "$p" @assistant-state-at "$now" \; \
		set -p -t "$p" @assistant-pending done 2>/dev/null
	;;
end)
	tmux set -up -t "$p" @assistant-state \; \
		set -up -t "$p" @assistant-state-at \; \
		set -up -t "$p" @assistant-pid \; \
		set -up -t "$p" @assistant-pending 2>/dev/null
	;;
esac

exit 0
