#!/bin/bash
# Omarchy theme-set hook (bootstrap §20). While the theme is dark, give the top
# bar the text color of ghostty/linux-dark.conf; on a light theme, remove it so
# the theme's own color shows. The color goes in a managed block in
# ~/.config/omarchy/shell.toml, which the bar watches and layers over the theme.
set -eu

shell_config="$HOME/.config/omarchy/shell.toml"

color=""
if [[ $(omarchy-theme-color mode 2>/dev/null) == dark ]]; then
  color=$(sed -n 's/^foreground *= *//p' "$HOME/.shell-setup/ghostty-dark.conf" 2>/dev/null | tail -n 1)
fi

[[ -f $shell_config || -n $color ]] || exit 0
mkdir -p "$(dirname "$shell_config")"
touch "$shell_config"

tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT
sed '/^# >>> shell-setup managed >>>$/,/^# <<< shell-setup managed <<<$/d' "$shell_config" >"$tmp"
if [[ -n $color ]]; then
  [[ ! -s $tmp || -z $(tail -c 1 "$tmp") ]] || echo >>"$tmp"
  printf '# >>> shell-setup managed >>>\n[bar]\ntext = "%s"\n# <<< shell-setup managed <<<\n' "$color" >>"$tmp"
fi

# Rewrite in place, and only on a change, so the bar's file watch keeps working.
cmp -s "$tmp" "$shell_config" || cat "$tmp" >"$shell_config"
