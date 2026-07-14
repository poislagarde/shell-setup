#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ASSISTANT_RESURRECT_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
FAKE_BIN="$SCRIPT_DIR/fake-bin"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/resume-codex-test.XXXXXX")
trap 'rm -rf "$TMP"' EXIT

export ASSISTANT_RESURRECT_DIR
export PATH="$FAKE_BIN:$PATH"

SID=019f5d76-6fe2-7d93-aa8c-62c0bf6e7900
EXPECTED="resume $SID"
UPDATE_MESSAGE='Update ran successfully! Please restart Codex.'

printf '\033[?1049h%s\033[?1049l' "$UPDATE_MESSAGE" |
	"$ASSISTANT_RESURRECT_DIR/detect-codex-update.pl" "$TMP/content-marker" || true
[ ! -e "$TMP/content-marker" ] || {
	echo "conversation content was mistaken for an updater result" >&2
	exit 1
}

printf '\033[?1049hprompt\033[?1049l%s\033[?1049hreopened\033[?1049l' \
	"$UPDATE_MESSAGE" |
	"$ASSISTANT_RESURRECT_DIR/detect-codex-update.pl" "$TMP/transient-marker" || true
[ ! -e "$TMP/transient-marker" ] || {
	echo "output before a later alternate-screen entry was mistaken for an update" >&2
	exit 1
}

printf '\033[?1049hprompt\033[?1049l%s' "$UPDATE_MESSAGE" |
	"$ASSISTANT_RESURRECT_DIR/detect-codex-update.pl" "$TMP/update-marker"
[ -e "$TMP/update-marker" ] || {
	echo "updater result was not detected after leaving the alternate screen" >&2
	exit 1
}

prepare_case() {
	local name="$1" dir="$TMP/$1"
	mkdir -p "$dir/state"
	printf '%s\n' 'codex-cli 1.0.0' >"$dir/version"
	: >"$dir/calls"
	export FAKE_CODEX_VERSION_FILE="$dir/version"
	export FAKE_CODEX_CALLS_FILE="$dir/calls"
	export FAKE_CODEX_UPDATED_FILE="$dir/updated"
	export TMUX_ASSISTANT_RESURRECT_DIR="$dir/state"
}

assert_calls() {
	local expected_count="$1" count
	count=$(wc -l <"$FAKE_CODEX_CALLS_FILE" | tr -d ' ')
	[ "$count" -eq "$expected_count" ] || {
		echo "expected $expected_count Codex call(s), got $count" >&2
		exit 1
	}
	awk -v expected="$EXPECTED" '$0 != expected { exit 1 }' "$FAKE_CODEX_CALLS_FILE" || {
		echo "Codex was resumed with different arguments" >&2
		exit 1
	}
}

prepare_case normal
FAKE_CODEX_MODE=normal "$ASSISTANT_RESURRECT_DIR/resume-codex.sh" "$SID" >/dev/null
assert_calls 1

prepare_case failed
set +e
FAKE_CODEX_MODE=failed-update \
	"$ASSISTANT_RESURRECT_DIR/resume-codex.sh" "$SID" >/dev/null 2>&1
status=$?
set -e
[ "$status" -eq 7 ] || {
	echo "expected failed update status 7, got $status" >&2
	exit 1
}
assert_calls 1

set +e
"$ASSISTANT_RESURRECT_DIR/resume-codex.sh" not-a-uuid >/dev/null 2>&1
status=$?
set -e
[ "$status" -eq 2 ] || {
	echo "expected malformed ID status 2, got $status" >&2
	exit 1
}

echo "resume-codex: OK"
