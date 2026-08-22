#!/usr/bin/env bash

set -euo pipefail

if [ "${FAKE_ASSERT_EMPTY_RESTORE_SCRATCH:-no}" = yes ] &&
	find "$TMUX_PERSISTENCE_RESURRECT_DIR/restore/pane_contents" -mindepth 1 -print -quit | grep -q .; then
	exit 1
fi

if [ -n "${FAKE_RESTORE_MARKER:-}" ]; then
	printf '%s\n' "${TMUX_PERSISTENCE_RESTORE_TARGET:-unknown}" >>"$FAKE_RESTORE_MARKER"
fi

if [ "${FAKE_RESTORE_RUN_HOOKS:-no}" = yes ]; then
	: "${PERSISTENCE_UNDER_TEST:?}"
	"$PERSISTENCE_UNDER_TEST" pre-restore
	"$PERSISTENCE_UNDER_TEST" post-restore
fi
