#!/bin/sh
input=$(cat)

cwd=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // empty')
used=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
five_pct=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
five_resets=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // empty')

# Build progress bar: 10 chars of filled (█) and empty (░) blocks
# $1 = percentage (0-100, may be a float)
make_bar() {
  pct="$1"
  filled=$(awk -v p="$pct" 'BEGIN { v = p * 10 / 100; printf "%d", (v < 0 ? 0 : (v > 10 ? 10 : v + 0.5)) }')
  [ -z "$filled" ] && filled=0
  bar=""
  i=0
  while [ "$i" -lt "$filled" ]; do bar="${bar}█"; i=$((i+1)); done
  while [ "$i" -lt 10 ];        do bar="${bar}░"; i=$((i+1)); done
  printf '%s' "$bar"
}

# Resolve git worktree + branch from the cwd (silently no-op if not a repo)
worktree=""
branch=""
if [ -n "$cwd" ] && [ -d "$cwd" ]; then
  worktree_root=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null)
  if [ -n "$worktree_root" ]; then
    worktree=$(basename "$worktree_root")
    branch=$(git -C "$cwd" symbolic-ref --short HEAD 2>/dev/null)
    if [ -z "$branch" ]; then
      # Detached HEAD: show short SHA instead
      branch=$(git -C "$cwd" rev-parse --short HEAD 2>/dev/null)
      [ -n "$branch" ] && branch="@${branch}"
    fi
  fi
fi

# Replace $HOME prefix with ~ for a shorter display
display_cwd="$cwd"
case "$display_cwd" in
  "$HOME")   display_cwd="~" ;;
  "$HOME"/*) display_cwd="~${display_cwd#"$HOME"}" ;;
esac

# Line 1: cwd + worktree + branch
line1="📁 $display_cwd"
[ -n "$worktree" ] && line1="${line1} | 🌳 ${worktree}"
[ -n "$branch" ]   && line1="${line1} | 🌿 ${branch}"

# Line 2: context % + 5h usage
line2=""
if [ -n "$used" ]; then
  used_int=$(printf '%.0f' "$used")
  line2="🧠 ${used_int} %"
fi

if [ -n "$five_pct" ]; then
  bar=$(make_bar "$five_pct")
  five_int=$(printf '%.0f' "$five_pct")
  segment="⏱️ 5h ${bar} ${five_int}%"
  if [ -n "$five_resets" ]; then
    reset_time=$(date -r "$five_resets" '+%H:%M' 2>/dev/null)
    [ -n "$reset_time" ] && segment="${segment} resets ${reset_time}"
  fi
  if [ -n "$line2" ]; then
    line2="${line2} | ${segment}"
  else
    line2="${segment}"
  fi
fi

if [ -n "$line2" ]; then
  printf '%s\n%s' "$line1" "$line2"
else
  printf '%s' "$line1"
fi
