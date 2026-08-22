#!/usr/bin/env bash

set -euo pipefail

: "${TMUX_PERSISTENCE_RESURRECT_DIR:?}"
printf '[]\n' >"$TMUX_PERSISTENCE_RESURRECT_DIR/assistant-sessions.json"
if [ "${FAKE_ASSISTANT_USE_REAL_LOG:-no}" = yes ]; then
	SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
	# Exercise the production helper's diagnostic-failure behavior after a valid
	# map has already been written.
	source "$SCRIPT_DIR/../assistant-resurrect/lib.sh"
	log 'fake assistant save completed'
fi
