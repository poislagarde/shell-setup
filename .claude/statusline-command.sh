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
ctx=""
[ -n "$used" ] && ctx="${C_CTX}🧠 $(printf '%.0f' "$used")%${C_RESET}"

five_bar=""; five_pctstr=""; five_resetstr=""; five_hl=""; five_hlr=""
if [ -n "$five_pct" ]; then
  five_bar=$(make_bar "$five_pct")
  five_pctstr="$(printf '%.0f' "$five_pct")%"
  [ -n "$five_resets" ] && { t=$(date -r "$five_resets" '+%H:%M' 2>/dev/null); [ -n "$t" ] && five_resetstr="resets $t"; }
  # Past 80% usage the "x% resets y" tail turns red; otherwise it stays default.
  awk -v p="$five_pct" 'BEGIN{exit !(p+0>80)}' && { five_hl="$C_HOT"; five_hlr="$C_RESET"; }
fi

week_seg=""
if [ -n "$week_pct" ]; then
  week_tail="$(printf '%.0f' "$week_pct")%"
  [ -n "$week_resets" ] && { t=$(date -r "$week_resets" '+%a' 2>/dev/null); [ -n "$t" ] && week_tail="$week_tail resets $t"; }
  week_hl=""; week_hlr=""
  awk -v p="$week_pct" 'BEGIN{exit !(p+0>80)}' && { week_hl="$C_HOT"; week_hlr="$C_RESET"; }
  week_seg="📅 7d $(make_bar "$week_pct") ${week_hl}${week_tail}${week_hlr}"
fi

# Build the line at degradation level N into LEFT/RIGHT (+ their emoji bonuses).
# As the terminal narrows, the richest level that still fits is chosen; features
# drop in this order (N = drops applied):
#   1 weekly · 2 5h bar · 3 5h "resets …" · 4 the "5h" label · 5 model effort
#   6 model · 7 the whole 5h gauge
# 🧠 context % is never dropped; the compact "⏱️ NN%" gauge outlives model/effort.
build_level() {  # $1 = N
  _n=$1
  LEFT="$ctx"; LB=0; [ -n "$ctx" ] && LB=1
  if [ -n "$model" ] && [ "$_n" -le 5 ]; then
    _m="${C_MODEL}${model}${C_RESET}"
    [ -n "$effort" ] && [ "$_n" -le 4 ] && _m="$_m ${C_EFFORT}[$effort]${C_RESET}"
    if [ -n "$LEFT" ]; then LEFT="$LEFT$SEP$_m"; else LEFT="$_m"; fi
  fi
  RIGHT=""; RB=0
  if [ -n "$five_pctstr" ] && [ "$_n" -le 6 ]; then
    _ftail="$five_pctstr"
    [ "$_n" -le 2 ] && [ -n "$five_resetstr" ] && _ftail="$_ftail $five_resetstr"
    _five="⏱️"
    [ "$_n" -le 3 ] && _five="$_five 5h"
    [ "$_n" -le 1 ] && _five="$_five $five_bar"
    _five="$_five ${five_hl}${_ftail}${five_hlr}"
    # At the full level weekly leads (📅 7d … · ⏱️ 5h …); it is still the first
    # segment to drop, leaving the 5h gauge alone at every narrower level.
    if [ "$_n" -eq 0 ] && [ -n "$week_seg" ]; then RIGHT="$week_seg$SEP$_five"; RB=1; else RIGHT="$_five"; fi
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
