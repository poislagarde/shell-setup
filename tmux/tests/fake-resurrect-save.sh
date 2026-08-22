#!/usr/bin/env bash

set -euo pipefail

: "${PERSISTENCE_UNDER_TEST:?}"
: "${TMUX_PERSISTENCE_RESURRECT_DIR:?}"
: "${FAKE_LAYOUT_SOURCE:?}"
: "${FAKE_ARCHIVE_SOURCE:?}"

if [ "${FAKE_ASSERT_EMPTY_SAVE_SCRATCH:-no}" = yes ] &&
	find "$TMUX_PERSISTENCE_RESURRECT_DIR/save/pane_contents" -mindepth 1 -print -quit | grep -q .; then
	exit 1
fi

if [ -n "${FAKE_SAVE_MARKER:-}" ]; then
	printf 'started\n' >"$FAKE_SAVE_MARKER"
fi
if [ "${FAKE_SAVE_DELAY:-0}" != 0 ]; then
	sleep "$FAKE_SAVE_DELAY"
fi

candidate=$TMUX_PERSISTENCE_RESURRECT_DIR/tmux_resurrect_fake.txt
cp -p "$FAKE_LAYOUT_SOURCE" "$candidate"
if [ "${FAKE_KILL_COORDINATOR_AFTER_CANDIDATE:-no}" = yes ]; then
	kill -KILL "$PPID"
	exit 0
fi
"$PERSISTENCE_UNDER_TEST" post-save-layout "$candidate"
tar -czf "$TMUX_PERSISTENCE_RESURRECT_DIR/pane_contents.tar.gz" \
	-C "$FAKE_ARCHIVE_SOURCE" .
