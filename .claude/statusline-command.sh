#!/bin/sh
input=$(cat)

# Refresh the model-specific weekly usage cache in the background, at most once
# per 180s (via an attempt marker) — this must never block rendering on the
# network. The oauth token is read from the keychain and never written to disk;
# a failed/401 fetch leaves the last good cache in place (tmp file + mv).
CACHE_DIR="$HOME/.claude/cache"
USAGE_CACHE="$CACHE_DIR/oauth-usage.json"
USAGE_ATTEMPT="$CACHE_DIR/oauth-usage.attempt"
mkdir -p "$CACHE_DIR" 2>/dev/null
attempt_mtime=$(stat -f %m "$USAGE_ATTEMPT" 2>/dev/null)
[ -z "$attempt_mtime" ] && attempt_mtime=0
if [ "$(( $(date +%s) - attempt_mtime ))" -ge 180 ]; then
  touch "$USAGE_ATTEMPT" 2>/dev/null
  (
    token=$(security find-generic-password -s "Claude Code-credentials" -a "$USER" -w 2>/dev/null | jq -r '.claudeAiOauth.accessToken // empty')
    if [ -n "$token" ]; then
      curl -fsS --max-time 5 https://api.anthropic.com/api/oauth/usage \
        -H "Authorization: Bearer $token" \
        -H "anthropic-beta: oauth-2025-04-20" \
        -o "$USAGE_CACHE.tmp" \
        && mv "$USAGE_CACHE.tmp" "$USAGE_CACHE"
    fi
  ) >/dev/null 2>&1 &
fi

# Pull every field in one jq pass, newline-separated so empty values keep their
# slot — read line by line (model display names contain spaces, never newlines).
{
  read -r used
  read -r model
  read -r effort
  read -r five_pct
  read -r five_resets
  read -r week_pct
  read -r week_resets
} <<EOF
$(printf '%s' "$input" | jq -r '
  (.context_window.used_percentage // ""),
  (.model.display_name // ""),
  (.effort.level // ""),
  (.rate_limits.five_hour.used_percentage // ""),
  (.rate_limits.five_hour.resets_at // ""),
  (.rate_limits.seven_day.used_percentage // ""),
  (.rate_limits.seven_day.resets_at // "")
')
EOF

# Prefer the model-specific weekly bucket (from the cached usage API response,
# matched by display name) over the payload's all-models seven_day bucket.
# Falls back to the payload values read above when there's no cache yet, no
# matching scoped entry, or the cache fails to parse.
if [ -n "$model" ] && [ -s "$USAGE_CACHE" ]; then
  scoped_pct=""; scoped_resets=""
  {
    read -r scoped_pct
    read -r scoped_resets
  } <<EOF
$(jq -r --arg m "$model" '
  ($m | ascii_downcase) as $mdl
  | [.limits[]?
      | (.scope.model?.display_name? // "") as $n
      | select($n != "" and ($mdl | startswith($n | ascii_downcase)))]
  | first
  | select(. != null)
  | (.percent // ""),
    ((.resets_at // "") | if . == "" then "" else (sub("\\.[0-9]+"; "") | sub("\\+00:00$"; "Z") | fromdate) end)
' "$USAGE_CACHE" 2>/dev/null)
EOF
  [ -n "$scoped_pct" ] && { week_pct="$scoped_pct"; week_resets="$scoped_resets"; }
fi

# Colors (24-bit; palette shared with the Codex status line). Claude Code always
# captures this script's stdout, so we can't gate on a tty — emit color
# unconditionally, but honor NO_COLOR. ESC is always a real escape so the width
# stripper below never chews on literal "[…m" text (e.g. "[xhigh]").
ESC=$(printf '\033')
if [ -n "$NO_COLOR" ]; then
  C_CTX=""; C_MODEL=""; C_EFFORT=""; C_HOT=""; C_RESET=""; SEP=" · "
else
  C_CTX="${ESC}[38;2;233;183;149m"      # #E9B795  context
  C_MODEL="${ESC}[38;2;243;227;188m"    # #F3E3BC  model name
  C_EFFORT="${ESC}[38;2;255;248;226m"   # #FFF8E2  [effort] (brightest)
  C_HOT="${ESC}[38;2;221;148;169m"      # #DD94A9  weekly/5h "x% resets y" once usage > 80%
  C_RESET="${ESC}[0m"
  SEP="${ESC}[38;2;147;149;152m · ${C_RESET}"  # #939598  separator
fi

# Build a 10-cell progress bar (█ filled, ░ empty) from a 0-100 percentage.
make_bar() {
  filled=$(awk -v p="$1" 'BEGIN { v = p * 10 / 100; printf "%d", (v < 0 ? 0 : (v > 10 ? 10 : v + 0.5)) }')
  [ -z "$filled" ] && filled=0
  bar=""; i=0
  while [ "$i" -lt "$filled" ]; do bar="${bar}█"; i=$((i+1)); done
  while [ "$i" -lt 10 ];        do bar="${bar}░"; i=$((i+1)); done
  printf '%s' "$bar"
}

# Display width of a string = code points (wc -m) + a caller-supplied bonus of
# +1 per single-codepoint 2-cell emoji it contains. Our emojis: 🧠 and 📅 need
# +1 each; ⏱️ is two code points already counted as two cells, so it needs none.
# (macOS awk counts bytes and `wc -L` is unreliable here, hence this approach.)
# SGR color sequences are stripped first so they don't count toward the width.
dwidth() { printf '%s' "$(( $(printf '%s' "$1" | sed "s/${ESC}\[[0-9;]*m//g" | wc -m | tr -d ' ') + $2 ))"; }

# Pieces, built once (each empty if its data is absent).
now=$(date +%s)
ctx=""
[ -n "$used" ] && ctx="${C_CTX}🧠 $(printf '%.0f' "$used")%${C_RESET}"

five_icon="⏱️"; five_label="5h"
week_icon="📅"; week_label="7d"
five_bar=""; five_pctstr=""; five_resetstr=""; five_hl=""; five_hlr=""
if [ -n "$five_pct" ]; then
  five_bar=$(make_bar "$five_pct")
  five_pctstr="$(printf '%.0f' "$five_pct")%"
  [ -n "$five_resets" ] && { t=$(date -r "$five_resets" '+%H:%M' 2>/dev/null); [ -n "$t" ] && five_resetstr="resets $t"; }
  # Past 80% usage the "x% resets y" tail turns red; otherwise it stays default.
  awk -v p="$five_pct" 'BEGIN{exit !(p+0>80)}' && { five_hl="$C_HOT"; five_hlr="$C_RESET"; }
fi

week_bar=""; week_pctstr=""; week_resetstr=""; week_hl=""; week_hlr=""
if [ -n "$week_pct" ]; then
  week_bar=$(make_bar "$week_pct")
  week_pctstr="$(printf '%.0f' "$week_pct")%"
  # Reset stamp: time alone when it lands today, day + time when under 48h away,
  # otherwise just the day (a week out, the hour is noise).
  if [ -n "$week_resets" ]; then
    if [ "$(date -r "$week_resets" '+%F' 2>/dev/null)" = "$(date '+%F')" ]; then
      wfmt='+%H:%M'
    elif [ "$(( week_resets - now ))" -lt 172800 ]; then
      wfmt='+%a %H:%M'
    else
      wfmt='+%a'
    fi
    t=$(date -r "$week_resets" "$wfmt" 2>/dev/null); [ -n "$t" ] && week_resetstr="resets $t"
  fi
  awk -v p="$week_pct" 'BEGIN{exit !(p+0>80)}' && { week_hl="$C_HOT"; week_hlr="$C_RESET"; }
fi

# Only one gauge fits from level 1 down: keep whichever runs out first. Project
# each window's exhaustion from its burn rate so far (elapsed = window length -
# time left); a window at 0% or already reset counts as never hit, and without
# both reset stamps 5h wins.
# ponytail: assumes a flat burn rate; revisit if it flaps mid-session.
primary=""
[ -n "$five_pctstr" ] && primary=five
[ -n "$week_pctstr" ] && [ -z "$primary" ] && primary=week
if [ -n "$five_pctstr" ] && [ -n "$week_pctstr" ]; then
  primary=$(awk -v fp="$five_pct" -v fr="$five_resets" -v wp="$week_pct" -v wr="$week_resets" -v now="$now" 'BEGIN {
    ft = fr - now; wt = wr - now
    if (ft <= 0 || wt <= 0) { print "five"; exit }
    fe = 18000 - ft; we = 604800 - wt
    ff = (fe > 0 && fp > 0) ? (100 - fp) * fe / fp : 1e18
    wf = (we > 0 && wp > 0) ? (100 - wp) * we / wp : 1e18
    print (wf < ff) ? "week" : "five"
  }')
fi

# Render one gauge (five|week) at degradation level N onto stdout.
gauge() {
  eval "_i=\$${1}_icon; _l=\$${1}_label; _b=\$${1}_bar; _p=\$${1}_pctstr; _r=\$${1}_resetstr; _h=\$${1}_hl; _hr=\$${1}_hlr"
  _tail="$_p"
  [ "$2" -le 2 ] && [ -n "$_r" ] && _tail="$_tail $_r"
  _g="$_i"
  [ "$2" -le 3 ] && _g="$_g $_l"
  [ "$2" -le 1 ] && _g="$_g $_b"
  printf '%s %s' "$_g" "${_h}${_tail}${_hr}"
}

# Build the line at degradation level N into LEFT/RIGHT (+ their emoji bonuses).
# As the terminal narrows, the richest level that still fits is chosen; features
# drop in this order (N = drops applied):
#   1 the less urgent gauge · 2 its bar · 3 its "resets …" · 4 its label
#   5 model effort · 6 model · 7 the gauge itself
# 🧠 context % is never dropped; the compact "NN%" gauge outlives model/effort.
build_level() {  # $1 = N
  _n=$1
  LEFT="$ctx"; LB=0; [ -n "$ctx" ] && LB=1
  if [ -n "$model" ] && [ "$_n" -le 5 ]; then
    _m="${C_MODEL}${model}${C_RESET}"
    [ -n "$effort" ] && [ "$_n" -le 4 ] && _m="$_m ${C_EFFORT}[$effort]${C_RESET}"
    if [ -n "$LEFT" ]; then LEFT="$LEFT$SEP$_m"; else LEFT="$_m"; fi
  fi
  RIGHT=""; RB=0
  if [ -n "$primary" ] && [ "$_n" -le 6 ]; then
    if [ "$_n" -eq 0 ] && [ -n "$five_pctstr" ] && [ -n "$week_pctstr" ]; then
      # Full width: weekly leads, 5h follows.
      RIGHT="$(gauge week 0)$SEP$(gauge five 0)"; RB=1
    else
      RIGHT="$(gauge "$primary" "$_n")"
      [ "$primary" = week ] && RB=1
    fi
  fi
}

# Claude Code exports COLUMNS and renders a few columns narrower than it, so keep
# a 5-col right margin; degrade rather than let it truncate (need ≥1 filler col).
cols=${COLUMNS:-$(tput cols 2>/dev/null)}
[ -z "$cols" ] && cols=80
n=0
while [ "$n" -le 7 ]; do
  build_level "$n"
  lw=$(dwidth "$LEFT" "$LB"); rw=$(dwidth "$RIGHT" "$RB")
  if [ -n "$RIGHT" ]; then
    [ "$(( cols - lw - rw - 5 ))" -ge 1 ] && break
  else
    [ "$(( cols - lw - 5 ))" -ge 0 ] && break
  fi
  n=$((n + 1))
done
[ "$n" -gt 7 ] && build_level 7   # nothing fit — fall back to the minimum

# Render: left, then right right-aligned into the remaining space.
lw=$(dwidth "$LEFT" "$LB")
if [ -n "$RIGHT" ]; then
  rw=$(dwidth "$RIGHT" "$RB")
  gap=$(( cols - lw - rw - 5 )); [ "$gap" -lt 1 ] && gap=1
  printf '%s%*s%s' "$LEFT" "$gap" '' "$RIGHT"
else
  printf '%s' "$LEFT"
fi
