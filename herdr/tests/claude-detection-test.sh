#!/bin/sh
# Classifies Claude footer fixtures against the generated detection override.
# Runs under a throwaway HOME, so the live herdr server and config are untouched.
set -eu
unset HERDR_SOCKET_PATH
repo=$(cd "$(dirname "$0")/../.." && pwd)
remote="$HOME/.local/state/herdr/agent-detection/remote/claude.toml"
herdr=$(command -v herdr || echo "$HOME/.local/bin/herdr")
[ -f "$remote" ] || { echo "SKIP: no cached remote manifest at $remote"; exit 0; }

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/.local/state/herdr/agent-detection/remote"
cp "$remote" "$tmp/.local/state/herdr/agent-detection/remote/"
HOME="$tmp" sh "$repo/herdr/claude-detection-overlay.sh"

prompt='────────────────
❯
────────────────'
fail=0
check() { # footer expected-state [body, replacing the prompt box]
  printf '%s\n%s\n' "${3:-$prompt}" "$1" >"$tmp/screen.txt"
  got=$(HOME="$tmp" "$herdr" agent explain --file "$tmp/screen.txt" --agent claude --json | jq -r .state)
  [ "$got" = "$2" ] && echo "ok   $2: $1" || { echo "FAIL want $2 got $got: $1"; fail=1; }
}
check '  ⏵⏵ auto mode on · ← 3 agents' idle
check '  ⏵⏵ auto mode on · PR #1 · 1 shell · ← 3 agents' working
check '  ⏵⏵ auto mode on · ← 3 agents · 2 shells' working
check '  ⏵⏵ auto mode on · 1 shell, 1 monitor · ← 3 agents' working
check '  ⏸ plan mode on · 1 monitor' working
check '  ⏵⏵ auto mode on · 1 shell · ← 3 agents' blocked ' Bash command
   rm -rf /tmp/x
 Do you want to proceed?
 ❯ 1. Yes
   2. No
 Esc to cancel · Tab to amend · ctrl+e to explain'
exit "$fail"
