#!/usr/bin/env bash
# Assistant SessionEnd hook: drop the state file written by session-track.sh
# when a <tool> process exits, so a later process that reuses the pid isn't
# mapped to a dead session. Tool passed as $1 (claude | codex).
#
# Only Claude registers this (under hooks.SessionEnd). Codex has no SessionEnd
# event, so a Codex state file is instead kept fresh by the next SessionStart
# overwriting it, and cleared wholesale by the /tmp wipe at reboot.
set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/lib.sh"

TOOL="${1:-}"
case "$TOOL" in claude | codex) ;; *) exit 0 ;; esac

# Same ancestry walk as the track hook so both resolve the same pid.
rm -f "$(assistant_state_dir)/$TOOL-$(find_agent_pid "$TOOL").json"
