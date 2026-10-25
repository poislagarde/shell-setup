#!/bin/sh
# Write herdr's local Claude detection override: the cached remote manifest
# plus this repo's extra rules. A local override replaces the whole manifest,
# so the LaunchAgent reruns this whenever herdr refreshes the remote copy.
# Idempotent; reloads herdr only when the override changes.
set -eu
PATH="$HOME/.local/bin:$PATH"

remote="$HOME/.local/state/herdr/agent-detection/remote/claude.toml"
override="$HOME/.config/herdr/agent-detection/claude.toml"

# Without a remote cache herdr runs its bundled manifest; leave it alone.
[ -f "$remote" ] || exit 0
mkdir -p "$(dirname "$override")"
tmp=$(mktemp "$override.XXXXXX")
trap 'rm -f "$tmp"' EXIT

{
  cat "$remote"
  cat <<'EOF'

# --- shell-setup additions (herdr/claude-detection-overlay.sh) ---

# Idle at the prompt with a background shell or Monitor still running reads as
# working, so the sidebar circle stays yellow until the job exits. Ranks above
# live_prompt_box (idle) and below the live blocked forms.
[[rules]]
id = "shell_setup_background_shell_working"
state = "working"
priority = 965
region = "bottom_non_empty_lines(12)"
visible_working = true
line_regex = ['^\s*[⏸⏵].*·\s+[1-9]\d*\s+(?:shells?|monitors?)(?:[\s,]|$)']
not = [
  { contains = ["do you want to proceed?"] },
  { contains = ["esc to cancel"] },
  { contains = ["waiting for permission"] },
  { contains = ["do you want to allow this connection?"] },
  { contains = ["tab to amend"] },
  { contains = ["ctrl+e to explain"] },
]
EOF
} >"$tmp"

cmp -s "$tmp" "$override" 2>/dev/null && exit 0
mv "$tmp" "$override"
herdr server reload-agent-manifests >/dev/null 2>&1 || true
