#!/usr/bin/env bash
# tmux-resurrect post-save hook (@resurrect-hook-post-save-all): map every
# pane running Claude Code or Codex CLI to its session ID and write the
# result as a JSON sidecar (assistant-sessions.json) next to resurrect's own
# save files. restore.sh reads it back after resurrect rebuilds the layout.
#
# Runs on every resurrect save — continuum's 15-min timer, the
# client-detached quit-save, and manual prefix+Ctrl-s — so it must stay fast:
# one ps snapshot, one tmux list-panes, and at most one sqlite query per
# codex pane.
set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/lib.sh"

STATE_DIR=$(assistant_state_dir)
SIDECAR=$(sidecar_file)
mkdir -p "$(dirname "$SIDECAR")"

# Single process snapshot, reused for every pane (`args=` last so the full
# command line is preserved).
SNAPSHOT=$(ps -eo pid=,ppid=,args=)

# Session IDs already assigned during this save. The cwd-based lookups
# (claude method 3, codex method 2) would otherwise hand two panes in the
# same directory the same "most recent" session.
USED_IDS=$'\n'

id_used() { case "$USED_IDS" in *$'\n'"$1"$'\n'*) return 0 ;; *) return 1 ;; esac }
mark_used() { USED_IDS="${USED_IDS}$1"$'\n'; }

# --- pane_assistant <pane_shell_pid> ---
# Print "pid<TAB>args" of the first assistant process in the pane: the pane
# pid itself (exec-replaced shell) or any descendant. Single-pass awk builds
# the descendant set relying on ps listing parents before children (holds on
# macOS libproc; same assumption upstream tmux-assistant-resurrect makes).
# First match wins — ps order is ascending pid, so an outer claude beats any
# claude it spawned itself.
pane_assistant() {
	local root="$1" pid args
	while IFS=$'\t' read -r pid args; do
		[ -n "$args" ] || continue
		if [ -n "$(detect_tool "$args")" ]; then
			printf '%s\t%s\n' "$pid" "$args"
			return 0
		fi
	done < <(echo "$SNAPSHOT" | awk -v root="$root" '
		BEGIN { pids[root] = 1 }
		($1 == root) || ($2 in pids) {
			pids[$1] = 1
			printf "%s\t%s\n", $1, substr($0, index($0, $3))
		}')
	return 1
}

# macOS ps has no etimes (elapsed seconds); parse etime ([[dd-]hh:]mm:ss).
process_start_epoch() {
	local e d=0 h=0 a b c
	e=$(ps -o etime= -p "$1" 2>/dev/null | tr -d ' ') || true
	[ -n "$e" ] || { echo 0; return; }
	case "$e" in *-*) d="${e%%-*}" e="${e#*-}" ;; esac
	IFS=: read -r a b c <<<"$e"
	if [ -n "${c:-}" ]; then h="$a" a="$b" b="$c"; fi
	echo $(($(date +%s) - ((10#$d * 24 + 10#$h) * 3600 + 10#$a * 60 + 10#$b)))
}

# --- claude_session_id <pid> <args> <cwd> ---
claude_session_id() {
	local sid state_file="$STATE_DIR/claude-$1.json"

	# 1. State file from the SessionStart hook — exact, per-process. The
	#    normal path for any claude started (or /clear'd, resumed, compacted)
	#    after the hook was installed.
	if [ -f "$state_file" ]; then
		sid=$(jq -r '.session_id // empty' "$state_file" 2>/dev/null || true)
		if [ -n "$sid" ] && ! id_used "$sid"; then
			echo "$sid"
			return
		fi
	fi

	# 2. --resume <id> in the process args — covers a freshly restored claude
	#    whose SessionStart hook hasn't been observed yet.
	sid=$(echo "$2" | sed -n 's/.*--resume[= ][[:space:]]*\([0-9a-fA-F-]\{36\}\).*/\1/p')
	if [ -n "$sid" ] && ! id_used "$sid"; then
		echo "$sid"
		return
	fi

	# 3. Newest transcript for the pane's cwd under ~/.claude/projects — the
	#    same per-directory lookup `claude --continue` performs. Project dir
	#    encoding: every non-alphanumeric path char becomes '-'. Needed for
	#    sessions started BEFORE the hook existed; ambiguous when several
	#    pre-hook claudes share a cwd (the used-ids filter keeps assignments
	#    distinct, but two such panes may swap sessions).
	local proj="$HOME/.claude/projects/$(echo "$3" | sed 's/[^a-zA-Z0-9]/-/g')" f
	for f in $(ls -t "$proj"/*.jsonl 2>/dev/null); do
		sid=$(basename "$f" .jsonl)
		# Transcript files are named <uuid>.jsonl; skip anything else.
		case "$sid" in
		[0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]-*) ;;
		*) continue ;;
		esac
		if ! id_used "$sid"; then
			echo "$sid"
			return
		fi
	done
}

# --- codex_session_id <pid> <args> <cwd> ---
codex_session_id() {
	local sid

	# 1. `resume <uuid>` in the process args (freshly restored codex).
	sid=$(echo "$2" | sed -n 's/.*resume[[:space:]][[:space:]]*\([0-9a-fA-F-]\{36\}\).*/\1/p')
	if [ -n "$sid" ] && ! id_used "$sid"; then
		echo "$sid"
		return
	fi

	# 2. Codex's own state DB: ~/.codex/state_*.sqlite (filename version-
	#    bumped on schema changes — glob and take the newest), table
	#    `threads` with id/cwd/updated_at/archived. Codex bumps updated_at
	#    on every user turn, so rank unarchived threads in this cwd
	#    preferring ones updated after the process started (rules out stale
	#    same-cwd threads), then most recently updated; skip IDs already
	#    assigned to another pane.
	local db start
	db=$(ls -t "$HOME"/.codex/state_*.sqlite 2>/dev/null | head -1)
	[ -n "$db" ] || return 0
	start=$(process_start_epoch "$1")
	while read -r sid; do
		if [ -n "$sid" ] && ! id_used "$sid"; then
			echo "$sid"
			return
		fi
	done < <(sqlite3 -readonly "$db" \
		"SELECT id FROM threads WHERE cwd = '${3//\'/\'\'}' AND archived = 0 \
		 ORDER BY (updated_at >= $start) DESC, updated_at DESC LIMIT 10" 2>/dev/null)
}

# --- main ---
ENTRIES=$(mktemp)
trap 'rm -f "$ENTRIES"' EXIT

while IFS=$'\t' read -r pane pane_pid pane_cwd; do
	match=$(pane_assistant "$pane_pid") || continue
	IFS=$'\t' read -r apid aargs <<<"$match"
	tool=$(detect_tool "$aargs")

	case "$tool" in
	claude) sid=$(claude_session_id "$apid" "$aargs" "$pane_cwd") ;;
	codex) sid=$(codex_session_id "$apid" "$aargs" "$pane_cwd") ;;
	*) continue ;;
	esac

	if [ -z "$sid" ]; then
		log "save: $pane runs $tool (pid $apid) but no session id found — skipped"
		continue
	fi
	mark_used "$sid"
	jq -n --arg pane "$pane" --arg tool "$tool" --arg sid "$sid" --arg cwd "$pane_cwd" \
		'{pane: $pane, tool: $tool, session_id: $sid, cwd: $cwd}' >>"$ENTRIES"
done < <(tmux list-panes -a -F "#{session_name}:#{window_index}.#{pane_index}	#{pane_pid}	#{pane_current_path}")

# Atomic replace so a save interrupted mid-write (e.g. during shutdown)
# can't leave a truncated sidecar.
TMP="$SIDECAR.tmp"
jq -s '.' "$ENTRIES" >"$TMP" && mv "$TMP" "$SIDECAR"
log "save: $(jq length "$SIDECAR") assistant session(s) recorded"
