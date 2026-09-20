#!/usr/bin/env bash
# The statusline's two data-driven choices: the weekly reset stamp's format, and
# which gauge survives once only one fits.

set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
LINE=$ROOT/.claude/statusline-command.sh
NOW=$(date +%s)

# A cached scoped weekly bucket would override the payload's seven_day values.
export HOME=$(mktemp -d /tmp/statusline-test.XXXXXX)
trap 'rm -rf -- "$HOME"' EXIT INT TERM HUP

render() { # five_pct, five_resets, week_pct, week_resets, columns
	printf '{"context_window":{"used_percentage":42},"model":{"display_name":"Test Model"},"rate_limits":{"five_hour":{"used_percentage":%s,"resets_at":%s},"seven_day":{"used_percentage":%s,"resets_at":%s}}}' \
		"$1" "$2" "$3" "$4" | NO_COLOR=1 COLUMNS=$5 sh "$LINE"
}

check() { # what, expected substring, actual
	case "$3" in
	*"$2"*) ;;
	*) printf '%s: expected %s in %s\n' "$1" "$2" "$3" >&2; exit 1 ;;
	esac
}

# Weekly reset stamp: time alone today, day + time under 48h, day alone beyond.
today=$((NOW + 1800))
check 'weekly resets today' "resets $(date -r "$today" '+%H:%M')" "$(render 5 $((NOW + 7200)) 88 "$today" 120)"
soon=$((NOW + 30 * 3600))
check 'weekly resets under 48h' "resets $(date -r "$soon" '+%a %H:%M')" "$(render 5 $((NOW + 7200)) 88 "$soon" 120)"
far=$((NOW + 5 * 86400))
check 'weekly resets beyond 48h' "resets $(date -r "$far" '+%a')" "$(render 5 $((NOW + 7200)) 88 "$far" 120)"

# One gauge only: the window whose burn rate exhausts it first.
check '5h burns out first' '5h' "$(render 92 $((NOW + 7200)) 30 "$far" 60)"
check 'weekly burns out first' '7d' "$(render 5 $((NOW + 7200)) 88 "$far" 60)"
check 'untouched 5h yields' '7d' "$(render 0 $((NOW + 18000)) 60 $((NOW + 86400)) 60)"
check 'no reset stamps keep 5h' '5h' "$(printf '{"rate_limits":{"five_hour":{"used_percentage":10},"seven_day":{"used_percentage":90}}}' | NO_COLOR=1 COLUMNS=60 sh "$LINE")"

# Both fit at full width, weekly leading.
both=$(render 92 $((NOW + 7200)) 30 "$far" 120)
check 'both gauges' '7d' "$both"
check 'both gauges' '5h' "$both"

printf 'statusline: OK\n'
