#!/bin/sh
# session-window-changed hook: when you switch to a window, select the pane that
# wants you. Panes are marked by set-state.sh — @assistant-pending is "input"
# when the assistant is blocked on you and "done" when it finished a turn.
#
# The mark is CONSUMED here, for every pane in the window, not just the one
# selected: a window you have already looked at goes back to restoring whichever
# pane you last used, so an unanswered prompt can't keep yanking focus on every
# visit. "input" outranks "done", newest wins within a rank.
#
# Hung off session-window-changed rather than the window-switching keybinds:
# the hook covers every route into a window (index keys, next/prev, last-window,
# the session picker, a client switching sessions), and there is nothing to keep
# in sync when a binding is added.
#
# Usage: focus-pending.sh <session-name>
set -u

session="${1:-}"
[ -n "$session" ] || exit 0

win=$(tmux display-message -p -t "$session" '#{window_id}' 2>/dev/null) || exit 0
[ -n "$win" ] || exit 0

# One line per marked pane, nothing for the rest — so fields never shift when a
# pane has no mark (pane ids, marks and timestamps hold no spaces).
marked=$(tmux list-panes -t "$win" -F \
	'#{?#{@assistant-pending},#{pane_id} #{@assistant-pending} #{@assistant-state-at},}' \
	2>/dev/null) || exit 0
[ -n "$marked" ] || exit 0

best="" best_rank=0 best_at=0 all=""
while read -r id mark at; do
	[ -n "$id" ] || continue
	all="$all $id"
	case "$mark" in
	input) rank=2 ;;
	*) rank=1 ;;
	esac
	at=${at:-0}
	if [ "$rank" -gt "$best_rank" ] ||
		{ [ "$rank" -eq "$best_rank" ] && [ "$at" -gt "$best_at" ]; }; then
		best="$id" best_rank="$rank" best_at="$at"
	fi
done <<EOF
$marked
EOF

[ -n "$best" ] || exit 0

for id in $all; do
	tmux set -up -t "$id" @assistant-pending 2>/dev/null
done
tmux select-pane -t "$best" 2>/dev/null || true

exit 0
