#!/bin/sh
# Open a herdr tab or split and type a command into its shell (default: claude).
# Usage: claude-pane.sh tab|right|down [command]
# Meant for a [[keys.command]] shell binding: herdr supplies HERDR_BIN_PATH,
# HERDR_ACTIVE_WORKSPACE_ID, HERDR_ACTIVE_PANE_ID and HERDR_ACTIVE_PANE_CWD.
set -eu
herdr=${HERDR_BIN_PATH:-herdr}
cmd=${2:-claude}
case ${1:-} in
  tab)
    json=$("$herdr" tab create --workspace "$HERDR_ACTIVE_WORKSPACE_ID" --cwd "$HOME" --focus)
    key=root_pane ;;
  right|down)
    json=$("$herdr" pane split --pane "$HERDR_ACTIVE_PANE_ID" --direction "$1" \
      --cwd "${HERDR_ACTIVE_PANE_CWD:-$HOME}" --focus)
    key=pane ;;
  *) echo "usage: $0 tab|right|down [command]" >&2; exit 2 ;;
esac
pane=$(printf '%s' "$json" | jq -er ".result.$key.pane_id")
"$herdr" pane run "$pane" "$cmd"
