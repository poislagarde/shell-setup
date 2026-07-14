#!/usr/bin/env bash
# tmux-resurrect post-restore hook (@resurrect-hook-post-restore-all): read
# the assistant-sessions.json sidecar written by save.sh and relaunch each
# saved assistant in its restored pane.
#
# The relaunch is typed into the pane's shell with send-keys (the same
# mechanism resurrect uses for its own process restores), NOT exec'd
# directly — so the user's interactive zsh expands the `claude` alias, which
# is what re-applies CLAUDE_CODE_TMUX_TRUECOLOR=1 and --chrome. Codex goes
# through resume-codex.sh so a successful startup update retries the same
# session ID with the new binary. Keystrokes buffer in the pty while zsh is
# still initializing, so no readiness wait is needed.
set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/lib.sh"

SIDECAR=$(sidecar_file)
[ -f "$SIDECAR" ] || exit 0

jq -c '.[]' "$SIDECAR" 2>/dev/null | while read -r entry; do
	pane=$(echo "$entry" | jq -r '.pane')
	tool=$(echo "$entry" | jq -r '.tool')
	sid=$(echo "$entry" | jq -r '.session_id')

	# Session IDs are UUIDs and pane targets are session:window.pane — but
	# they cross a shell boundary (send-keys) and a sqlite query later, so
	# refuse anything that doesn't look like what we wrote.
	case "$sid" in
	*[!0-9a-fA-F-]*) log "restore: $pane has malformed session id — skipped"; continue ;;
	esac

	# `=` prefix = exact session-name match (no prefix matching surprises).
	cur=$(tmux display-message -p -t "=$pane" '#{pane_current_command}' 2>/dev/null) ||
		{ log "restore: pane $pane not found — skipped"; continue; }

	# Only type into an idle shell. Resurrect doesn't relaunch claude/codex
	# itself (they're not in @resurrect-processes), so a restored assistant
	# pane is a bare shell — anything else means this pane already runs a
	# foreground program (e.g. restore fired twice) and typing would corrupt
	# its input.
	case "$cur" in
	zsh | bash | sh | -zsh | -bash | -sh) ;;
	*) log "restore: $pane busy with '$cur' — skipped"; continue ;;
	esac

	case "$tool" in
	claude) cmd="claude --resume $sid" ;;
	codex) cmd="$SCRIPT_DIR/resume-codex.sh $sid" ;;
	*) continue ;;
	esac
	tmux send-keys -t "=$pane" "$cmd" Enter
	log "restore: $pane ← $cmd"
done
