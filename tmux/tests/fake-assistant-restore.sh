#!/usr/bin/env bash

set -euo pipefail

if [ -n "${FAKE_ASSISTANT_RESTORE_MARKER:-}" ]; then
	printf 'called\n' >>"$FAKE_ASSISTANT_RESTORE_MARKER"
fi
