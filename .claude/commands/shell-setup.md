# Shell Setup

Set up a fresh macOS machine with my shell environment.

Run each section in order. Pause and report after each section completes so I can verify before continuing.

## 1. Install Homebrew

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

After install, add Homebrew to PATH for the current session:

```bash
eval "$(/opt/homebrew/bin/brew shellenv)"
```

## 2. Add Homebrew Taps

```bash
brew tap auth0/auth0-cli
```

## 3. Install Homebrew Formulae

Install the core tools I use (skip transitive dependencies — Homebrew resolves those):

```bash
brew install \
  autojump \
  auth0 \
  bfg \
  gh \
  go \
  jq \
  libpq \
  nvm \
  pipx \
  railway \
  tmux \
  yt-dlp
```

## 4. Install Homebrew Casks

```bash
brew install --cask \
  font-symbols-only-nerd-font \
  gcloud-cli \
  ghostty \
  sanesidebuttons \
  session-manager-plugin
```

`font-symbols-only-nerd-font` provides the Nerd Font icon glyphs (e.g. the
Octicons folder in the tmux pane border); `ghostty/config` lists it as a
`font-family` fallback after JetBrains Mono, so those glyphs render at
single-cell width without changing the text font. (The git-branch glyph is
drawn by Ghostty natively and needs no font.)

Ghostty needs Full Disk Access to read history files under protected directories. Open the pane and let the user add `/Applications/Ghostty.app`:

```bash
open "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
```

## 5. Install Oh My Zsh

```bash
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
```

## 6. Set Up NVM with ~/.nvm

This is critical: NVM must store node versions in `~/.nvm` (not the Homebrew cellar) so that `brew upgrade nvm` does not wipe installed node versions or global packages.

```bash
mkdir -p ~/.nvm
```

The Oh My Zsh `nvm` plugin handles sourcing `nvm.sh` automatically. Symlinks from `~/.nvm/nvm.sh` and `~/.nvm/nvm-exec` into the Homebrew cellar are created by the `nvm` formula — verify they exist:

```bash
ls -la ~/.nvm/nvm.sh ~/.nvm/nvm-exec
```

If the symlinks are missing, create them:

```bash
ln -sf "$(brew --prefix nvm)/nvm.sh" ~/.nvm/nvm.sh
ln -sf "$(brew --prefix nvm)/nvm-exec" ~/.nvm/nvm-exec
```

## 7. Install Node via NVM

```bash
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"

nvm install --lts
nvm alias default lts/*
```

## 8. Install Global CLI Packages

Claude Code, via the **native installer** (not npm):

```bash
curl -fsSL https://claude.ai/install.sh | bash
```

It installs to `~/.local/bin/claude` (a symlink into
`~/.local/share/claude/versions/`), which lands on PATH via the zshrc managed
block (§9) and `~/.zprofile` (§14). If a fresh machine somehow has an npm copy, remove it
(`npm uninstall -g @anthropic-ai/claude-code`) so PATH can't pick it up.

Codex CLI, likewise via its **native installer** (not the Homebrew cask):

```bash
curl -fsSL https://chatgpt.com/codex/install.sh | sh
```

It installs to `~/.codex/packages/standalone/` with a `~/.local/bin/codex`
symlink — which §14's PATH line already covers — and self-updates via
`codex update`.
The package is self-contained (it bundles its own `rg` search binary). If
the machine has a Homebrew cask or npm copy, remove it
(`brew uninstall --cask codex` / `npm uninstall -g @openai/codex`) so PATH
can't pick it up.

npm globals:

```bash
npm install -g vercel
```

(corepack and npm ship with node)

pipx tools (pipx itself comes from Homebrew in §3):

```bash
pipx install claude-swap   # provides `cswap` — switch between logged-in Claude Code accounts
```

After install, register accounts once: log into Claude Code, then run `cswap --add-account` (repeat per account). Switch with `cswap --switch` / `cswap --switch-to <n|email>` or the `cswap --tui` menu; `cswap --list` shows registered accounts. The account credentials live in cswap's own machine-local vault (not in this repo), so they must be re-registered on a fresh machine — restart Claude Code after switching to pick up the new token.

## 9. Append the managed block to ~/.zshrc

The `~/.zshrc` content lives in this repo at `zsh/zshrc`. Rather than
overwriting `~/.zshrc` (which would clobber whatever Oh My Zsh's installer just
wrote, plus any machine-local additions), append a **managed block** delimited
by marker comments whose sole content is a `source` line pointing at this
checkout's `zsh/zshrc` — so a later `git pull` of this repo updates the live
shell with no reinstall. The absolute checkout path is rendered into
`~/.zshrc` at bootstrap time; it must never be hardcoded in this repo. On
re-run, the old block is stripped and re-appended — so running this section
multiple times leaves the file in the same state as running it once
(idempotent).

Run from the root of this repo:

```bash
touch ~/.zshrc

# First-run backup: preserve the pre-shell-setup zshrc once. Subsequent runs
# (which already have the marker) are a no-op and won't overwrite the backup.
if ! grep -q '^# >>> shell-setup managed >>>$' ~/.zshrc \
   && [ ! -f ~/.zshrc.pre-shell-setup ]; then
  cp ~/.zshrc ~/.zshrc.pre-shell-setup
fi

# Strip any prior managed block (no-op if absent). BSD sed (`-i ''`).
sed -i '' '/^# >>> shell-setup managed >>>$/,/^# <<< shell-setup managed <<<$/d' ~/.zshrc

# Trim any trailing blank lines left behind by the strip (or pre-existing in
# the file). Keeps the separator below at exactly one blank line across reruns.
while [ -s ~/.zshrc ] && [ -z "$(tail -n 1 ~/.zshrc)" ]; do
  sed -i '' -e '$d' ~/.zshrc
done

# Append the managed block: a single source line pointing at this checkout.
{
  printf '\n# >>> shell-setup managed >>>\n'
  printf '# Sourced from the shell-setup checkout so `git pull` there updates this shell.\n'
  printf 'source "%s/zsh/zshrc"\n' "$PWD"
  printf '# <<< shell-setup managed <<<\n'
} >> ~/.zshrc
```

The sourced `zsh/zshrc` sets up Oh My Zsh (theme + shell-setup's required plugins),
points `NVM_DIR` at `~/.nvm`, wires Homebrew + user site-functions completions
onto `fpath`, the PATH, the `awsenv <profile>` AWS SSO helper, the
`claude` alias, and the `tm` session helper (`tm <name>` attaches/creates a
tmux session; plain `tm` is a numbered picker marking sessions attached/detached).
Keyboard tweaks: `^U` → `backward-kill-line` (macOS Cmd+Backspace semantics),
Shift+Enter as Codex-compatible Esc+Enter, Shift+Space via the CSI 27 plumbing,
Cmd+Opt+arrow no-ops for bare shells, and a precmd that re-asserts a blinking
thin-bar cursor inside tmux. tmux does not auto-start: Ghostty shells stay plain
until `herdr` or `tm` is run.

Because the managed block lives at the end of `~/.zshrc`, the sourced file's
scalar assignments (theme, `DISABLE_AUTO_TITLE`, etc.) win over anything
earlier in the file (zsh reads top-to-bottom, last assignment wins). The
`plugins` array is treated specially: `zsh/zshrc` uses
`plugins+=(git nvm autojump golang)` plus `typeset -U plugins` so any plugins
the user enabled earlier in their zshrc are preserved and merged with
shell-setup's required ones (de-duplicated). The re-`source $ZSH/oh-my-zsh.sh`
inside it re-runs OMZ with the merged plugin list so the additions actually
load.

> **Note:** edit zsh config only in the repo's `zsh/zshrc` — `~/.zshrc`
> sources it, so changes take effect on the next shell (or `source ~/.zshrc`).
> Machine-local additions belong in `~/.zshrc` outside the markers, never
> between them. See `AGENTS.md`.

## 10. Install AWS CLI

Use the official macOS installer (not Homebrew — AWS does not maintain third-party repositories). Reference: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html

```bash
curl "https://awscli.amazonaws.com/AWSCLIV2.pkg" -o "AWSCLIV2.pkg"
sudo installer -pkg AWSCLIV2.pkg -target /
rm AWSCLIV2.pkg
```

Verify:

```bash
which aws    # expect /usr/local/bin/aws
aws --version
```

## 11. Configure AWS CLI Profiles

Set up three SSO profiles sharing one SSO session:

- `prod` — read-only role on the production account
- `prod-admin` — admin role on the production account (used explicitly via `--profile prod-admin`)
- `dev` — admin role on the development account

Use the AWS CLI's built-in interactive commands rather than constructing `~/.aws/config` directly. `aws configure sso-session` creates the shared session; `aws configure sso --profile <name>` opens the browser, lets the user pick the actual account and role from what their SSO directory exposes, and writes the profile.

Because the flow is interactive and opens a browser, run it in a separate Terminal window. The wrapper script signals completion by touching `/tmp/aws-sso-setup-done` only on success (any earlier failure leaves the marker absent, so the agent will not proceed).

### Step 1: Write the wrapper script

```bash
cat > /tmp/aws-sso-setup.sh <<'SCRIPT'
#!/bin/bash
set -e
MARKER=/tmp/aws-sso-setup-done
rm -f "$MARKER"

echo "==============================================="
echo " AWS SSO Setup"
echo "==============================================="
echo
echo "This will configure three SSO profiles sharing one SSO session:"
echo "  - prod       (read-only role on the prod account)"
echo "  - prod-admin (admin role on the prod account)"
echo "  - dev        (admin role on the dev account)"
echo
echo "You will be prompted for the SSO start URL and region, then the"
echo "browser will open three times — once per profile — so you can pick"
echo "the account and role for each."
echo
read -r -p "Press Enter to start... "

echo
echo "--- Step 1/4: Configure the shared SSO session ---"
echo "Suggested session name: darwin"
aws configure sso-session

echo
echo "--- Step 2/4: Configure profile 'prod' (read-only role on prod account) ---"
aws configure sso --profile prod

echo
echo "--- Step 3/4: Configure profile 'prod-admin' (admin role on prod account) ---"
aws configure sso --profile prod-admin

echo
echo "--- Step 4/4: Configure profile 'dev' (admin role on dev account) ---"
aws configure sso --profile dev

echo
echo "All three profiles configured successfully."
touch "$MARKER"
echo "(You can close this window.)"
sleep 3
SCRIPT
chmod +x /tmp/aws-sso-setup.sh
```

### Step 2: Launch the script in a new Terminal window

```bash
rm -f /tmp/aws-sso-setup-done
osascript \
  -e 'tell application "Terminal" to do script "/tmp/aws-sso-setup.sh"' \
  -e 'tell application "Terminal" to activate'
```

### Step 3: Wait for the completion marker

The user will be answering CLI prompts and completing browser-based SSO logins for each profile — this typically takes 5–15 minutes. Run the wait in the background (do not use a foreground Bash call — its 2-minute default and 10-minute max timeout are both too short).

```bash
until [ -f /tmp/aws-sso-setup-done ]; do sleep 2; done && echo "AWS SSO setup completed"
```

If no completion notification arrives after ~20 minutes, check in with the user about whether they hit an error in the other window.

### Step 4: Verify and clean up

```bash
aws configure list-profiles
rm -f /tmp/aws-sso-setup.sh /tmp/aws-sso-setup-done
```

`aws configure list-profiles` should show `prod`, `prod-admin`, and `dev` (plus any pre-existing profiles).

> **Note:** The `awsenv` function in `~/.zshrc` (section 9) takes a profile name as its argument (`awsenv dev`, `awsenv prod`, `awsenv prod-admin`). The wrapper script creates those three profile names, so the function works with any of them as long as the script ran cleanly.

## 12. Configure Git

```bash
git config --global alias.up 'pull --rebase --autostash'
```

## 13. Install `git-mux`

[`git-mux`](https://github.com/poislagarde/git-mux) runs a git command across every repo in a directory **serially with per-host SSH connection multiplexing** (one shared connection per server), so a bulk `git mux pull` doesn't trip a host's connection-rate throttle the way many parallel pulls do. Works for any SSH git host, not just GitHub.

Clone the repo and run its installer (symlinks the script to `~/.local/bin/git-mux`, already on PATH from section 9). The installer ships but does not auto-install the zsh completion, so symlink it into the site-functions dir (on `fpath` from section 9) to enable it:

```bash
mkdir -p ~/repos
[ -d ~/repos/git-mux ] || git clone git@github.com:poislagarde/git-mux.git ~/repos/git-mux
~/repos/git-mux/install.sh
ln -sf ~/repos/git-mux/completions/_git-mux ~/.local/share/zsh/site-functions/_git-mux
rm -f ~/.zcompdump*
```

The `_git-mux` completion delegates to git's own command completion (so `git mux sw<TAB>` expands to `git mux switch`) and additionally completes git-mux's own flags. Open a fresh shell to pick it up.

> **Note:** The `~/.local/share/zsh/site-functions` line in `~/.zshrc` must come **before** `compinit` for the `_git-mux` completion to load. Section 9 already places it correctly.

Verify from a directory of repos: `git mux -n pull` lists the repos and the plan. (`git mux --help` won't work — git intercepts `--help` to look for a man page — so use `git-mux --help` directly.)

## 14. Ensure the ~/.zprofile PATH line

This is what puts `~/.local/bin` on PATH for login shells, covering the pipx
tools plus `claude`, `codex`, and `git-mux`. `~/.zprofile` is installer-owned
territory — pipx writes its own PATH line there, and other installers may add
marker-delimited blocks of their own — so append only if the line isn't already
present, and never overwrite the file. pipx's own line usually has the same
effect already; if a login shell (`zsh -l`) puts `~/.local/bin` on PATH, skip
this step rather than adding a duplicate.

```bash
# pipx
export PATH="$PATH:$HOME/.local/bin"
```

## 15. Restore Claude Code Configuration

Deep-copy this repo's `.claude/` into `~/.claude/` — except this bootstrap command itself (`commands/shell-setup.md`), which is run one-time from this repo (a project-scoped `/shell-setup`) and is never needed as a global command. For `settings.json` specifically, recursively merge so existing keys are preserved and this repo's values win on conflict (everything else is overwritten by this repo's copy; files already in `~/.claude/` that don't exist in the repo are left alone).

The merged `settings.json` includes hooks pointing at `~/.shell-setup/` — `assistant-resurrect/` for session persistence, and `assistant-activity/` for the window-label activity indicator — both symlinked there by §17. Until §17 runs, Claude Code skips the missing hook scripts harmlessly.

Run from the root of this repo:

```bash
mkdir -p ~/.claude ~/.codex

# Both assistants' hook files may hold hooks this repo doesn't track (a local
# integration registering its own PostToolUse, say), so neither may be copied
# over wholesale — and `jq -s '.[0] * .[1]'` is no better, since it merges
# objects recursively but REPLACES arrays, dropping those hooks the moment this
# repo registers the same event. Upsert per event instead: entries whose command
# runs out of ~/.shell-setup are this repo's and get replaced, all other entries
# are kept, and events the repo says nothing about are left alone. Every other
# key merges with the repo winning. Re-running replaces the same entries again,
# so it stays idempotent.
merge_hooks() {   # merge_hooks <live file> <repo file>
  [ -f "$2" ] || return 0
  if [ ! -f "$1" ]; then cp "$2" "$1"; return 0; fi
  tmp=$(mktemp)
  jq -s '
    def ours: (.command // "") | test("shell-setup");
    def drop_ours: map(.hooks |= map(select(ours | not)))
                 | map(select((.hooks | length) > 0));
    .[0] as $live | .[1] as $repo |
    ($live * ($repo | del(.hooks)))
    + { hooks: (($live.hooks // {}) + (($repo.hooks // {}) | with_entries(
          .key as $event
          | .value = ((($live.hooks[$event] // []) | drop_ours) + .value)
        ))) }
  ' "$1" "$2" > "$tmp" && mv "$tmp" "$1"
}

# 1. Claude Code settings.
merge_hooks ~/.claude/settings.json .claude/settings.json

# 2. Copy everything else, overwriting on conflict but preserving files in
#    ~/.claude that aren't in the repo (no --delete). Exclude the bootstrap
#    command itself — `shell-setup.md` runs one-time from this repo, so it
#    must not be installed as a global ~/.claude command — and the statusline
#    script, which is symlinked below instead of copied.
rsync -av --exclude='settings.json' --exclude='commands/shell-setup.md' \
  --exclude='statusline-command.sh' .claude/ ~/.claude/

# 3. Symlink the statusline script into place (one file, no repo/home drift).
ln -sf "$PWD/.claude/statusline-command.sh" ~/.claude/statusline-command.sh

# 4. Codex CLI counterpart: install the hooks (the Codex-side equivalent of the
#    Claude hooks above; both point at scripts symlinked by §17). Codex requires
#    you to TRUST each hook before it runs, keyed by a hash of the entry — so
#    approve the trust prompts on your first `codex` run after this, and again
#    after any change to this file (or run once with
#    --dangerously-bypass-hook-trust).
merge_hooks ~/.codex/hooks.json .codex/hooks.json

# 5. Codex settings: merge the tracked top-level defaults and [tui] block into
#    ~/.codex/config.toml. Preserve all other machine-local settings.
touch ~/.codex/config.toml

# Replace or add each tracked root-level scalar before the first TOML table.
while IFS= read -r assignment; do
  case "$assignment" in
    ''|'#'*) continue ;;
  esac
  key=${assignment%% *}
  tmp=$(mktemp)
  awk -v key="$key" -v assignment="$assignment" '
    BEGIN { in_root = 1; replaced = 0 }
    in_root && /^[[:space:]]*\[/ {
      if (!replaced) print assignment
      in_root = 0
    }
    in_root && $0 ~ ("^" key "[[:space:]]*=") {
      if (!replaced) print assignment
      replaced = 1
      next
    }
    { print }
    END {
      if (in_root && !replaced) print assignment
    }
  ' ~/.codex/config.toml > "$tmp" && mv "$tmp" ~/.codex/config.toml
done < .codex/config-defaults.toml

# The native footer shows context used, model/reasoning, PR number, weekly
# limit, and 5h limit.
if ! grep -q '^\[tui\]' ~/.codex/config.toml; then
  cat .codex/config-tui.toml >> ~/.codex/config.toml
else
  echo "~/.codex/config.toml already has a [tui] section — reconcile it with .codex/config-tui.toml by hand."
fi

# 6. Codex feature flag: hooks.json is inert unless [features].hooks is on.
#    Set the key inside an existing [features] table (replacing the deprecated
#    `codex_hooks` spelling of it), or append the tracked block. Every other
#    feature flag in that table is left as it is.
if grep -q '^\[features\]' ~/.codex/config.toml; then
  tmp=$(mktemp)
  awk '
    /^\[features\]/ { in_f = 1; print; next }
    in_f && /^[[:space:]]*\[/ {
      if (!done) { print "hooks = true"; done = 1 }
      in_f = 0
    }
    in_f && /^[[:space:]]*(codex_)?hooks[[:space:]]*=/ {
      if (!done) { print "hooks = true"; done = 1 }
      next
    }
    { print }
    END { if (in_f && !done) print "hooks = true" }
  ' ~/.codex/config.toml > "$tmp" && mv "$tmp" ~/.codex/config.toml
else
  cat .codex/config-features.toml >> ~/.codex/config.toml
fi
```

## 16. Restore Ghostty Configuration

Symlink this repo's Ghostty config into `~/.config/ghostty/` — a **symlink,
not a copy**, so the live file and the repo file are one file and can never
drift (see AGENTS.md). Replaces any prior config.

Run from the root of this repo:

```bash
mkdir -p ~/.config/ghostty
ln -sfn "$(pwd)/ghostty/config" ~/.config/ghostty/config
```

Verify it parses:

```bash
/Applications/Ghostty.app/Contents/MacOS/ghostty +validate-config --config-file=~/.config/ghostty/config
```

Reload a running Ghostty with `⌘⇧,` to pick up the new config.

## 17. Restore tmux Configuration

Symlink this repo's tmux config at `~/.tmux.conf` — a **symlink, not a
copy**, same reasoning as the Ghostty config in §16. Enables mouse support
(scroll + click-to-select-pane) and session persistence across reboots
(tmux-resurrect plus the repo-owned persistence coordinator).

Run from the root of this repo. The block inspects any live default server
before changing tmux wiring. An uncoordinated server requires explicit
topology approval and a second run.

```bash
# Preflight the live server before replacing its config, hooks, helpers, or
# scheduler. `-N` guarantees these checks cannot start a server.
_tmux_default() {
  env -u TMUX -u TMUX_PANE -u TMUX_TMPDIR tmux -N -L default "$@"
}
_tmux_inventory() {
  local rows
  rows=$(
    _tmux_default list-sessions -F 'S|#{session_id}|#{session_name}|#{session_windows}|#{session_attached}' &&
    _tmux_default list-windows -a -F 'W|#{session_id}|#{window_id}|#{window_index}|#{window_name}|#{window_layout}' &&
    _tmux_default list-panes -a -F 'P|#{window_id}|#{pane_id}|#{pane_index}|#{pane_current_path}|#{pane_current_command}'
  ) || return 1
  printf '%s\n' "$rows" | LC_ALL=C sort
}
_tmux_make_review_token() {
  local pid=$1 inventory=$2 digest
  digest=$(printf '%s\n' "$inventory" | /usr/bin/shasum -a 256 | awk '{print $1}') || return 1
  [ -n "$digest" ] || return 1
  printf '%s:%s\n' "$pid" "$digest"
}
_tmux_validated_pid=$(_tmux_default display-message -p '#{pid}' 2>/dev/null || true)
_tmux_initial_phase=
_tmux_reviewed_inventory=
_tmux_review_token=
if [ -n "$_tmux_validated_pid" ]; then
  [ -z "${TMUX:-}" ] || {
    echo "Transfer tmux ownership from a plain non-tmux shell; no tmux files were changed." >&2
    exit 1
  }
  [ -z "$(_tmux_default list-clients -F '#{client_name}' 2>/dev/null || true)" ] || {
    echo "Detach every tmux client before transfer; no tmux files were changed." >&2
    exit 1
  }
  _tmux_initial_phase=$(_tmux_default show-option -gqv @shell-setup-persistence-state 2>/dev/null || true)
  _tmux_reviewed_inventory=$(_tmux_inventory) || {
    echo "Could not inspect the live tmux topology; no tmux files were changed." >&2
    exit 1
  }
  _tmux_review_token=$(_tmux_make_review_token "$_tmux_validated_pid" "$_tmux_reviewed_inventory") || exit 1
  if [ "$_tmux_initial_phase" != ready ] && \
     [ "${TMUX_PERSISTENCE_MIGRATION_APPROVAL:-}" != "$_tmux_review_token" ]; then
    echo "Live uncoordinated tmux topology:" >&2
    printf '%s\n' "$_tmux_reviewed_inventory" >&2
    printf 'windows=%s panes=%s\n' \
      "$(_tmux_default list-windows -a -F '#{session_name}:#{window_index}' | wc -l | tr -d ' ')" \
      "$(_tmux_default list-panes -a -F '#{session_name}:#{window_index}.#{pane_index}' | wc -l | tr -d ' ')" >&2
    printf "After confirmation, run: export TMUX_PERSISTENCE_MIGRATION_APPROVAL='%s'\n" \
      "$_tmux_review_token" >&2
    echo "Then rerun §17 from the same plain, detached shell." >&2
    exit 1
  fi
fi

# Everything tmux.conf and the assistant hooks reference by a fixed path lives
# in ~/.shell-setup/ — this repo's own home directory, not a tool's config dir
# (see AGENTS.md).
mkdir -p ~/.shell-setup

# The pane-border-format is generated (tmux/build-pane-border-format.sh) and
# source-file'd by tmux.conf from a fixed ~/.shell-setup path — link it before
# the `tmux source-file` below, which parses (and so needs) it.
ln -sfn "$(pwd)/tmux/pane-border-format.conf" ~/.shell-setup/pane-border-format.conf

# Background loop tmux.conf launches (run-shell) to tick the @pulse option while
# any window is working, animating the window-label "breathe". Linked from a
# fixed ~/.shell-setup path; harmless if missing (the run-shell just fails quietly).
ln -sfn "$(pwd)/tmux/status-refresh.sh" ~/.shell-setup/status-refresh.sh

# Persistence coordinator: the only path used for periodic, detach, and manual
# saves; startup restore; readiness; verification; and retained sidecars.
command -v python3 >/dev/null || {
  echo "python3 is required for durable tmux save barriers." >&2
  exit 1
}
command -v jq >/dev/null || {
  echo "jq is required for assistant-session persistence." >&2
  exit 1
}
command -v sqlite3 >/dev/null || {
  echo "sqlite3 is required for Codex session discovery." >&2
  exit 1
}
ln -sfn "$(pwd)/tmux/tmux-persistence.sh" ~/.shell-setup/tmux-persistence.sh

# Assistant session persistence: symlink the resurrect hook scripts to the
# fixed path referenced by tmux.conf and ~/.claude/settings.json.
ln -sfn "$(pwd)/tmux/assistant-resurrect" ~/.shell-setup/assistant-resurrect

# Assistant activity indicator: the hooks that report what each assistant is
# doing (§15 registers them in ~/.claude/settings.json and ~/.codex/hooks.json)
# and the pane-focus script tmux.conf hooks onto session-window-changed.
ln -sfn "$(pwd)/tmux/assistant-activity" ~/.shell-setup/assistant-activity

# Install TPM and Resurrect without starting the default tmux server. The
# launchd agent below must remain the sole automatic server owner.
mkdir -p ~/.tmux/plugins
if [ ! -d ~/.tmux/plugins/tpm/.git ]; then
  git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm || exit 1
fi
if [ ! -d ~/.tmux/plugins/tmux-resurrect/.git ]; then
  git clone https://github.com/tmux-plugins/tmux-resurrect ~/.tmux/plugins/tmux-resurrect || exit 1
fi
# launchd owns both `tmux -D` and the save scheduler. The supervisor restores
# and verifies before Ghostty clients may attach. It waits without mutating a
# foreign server if one already owns the default socket.
ln -sfn "$(pwd)/tmux/tmux-server-agent.sh" ~/.shell-setup/tmux-server-agent.sh
cp tmux/local.shell-setup.tmux-server.plist ~/Library/LaunchAgents/

# Activate the coordinated hooks only after the preflight and any required
# migration approval. Seed an uncoordinated topology in the same uninterrupted
# handoff; an already coordinated server takes an ordinary save.
_tmux_current_pid=$(_tmux_default display-message -p '#{pid}' 2>/dev/null || true)
if [ -n "$_tmux_validated_pid" ]; then
  [ "$_tmux_current_pid" = "$_tmux_validated_pid" ] || {
    echo "tmux changed after preflight; refusing activation." >&2
    exit 1
  }
  [ -z "$(_tmux_default list-clients -F '#{client_name}' 2>/dev/null || true)" ] || {
    echo "A tmux client attached after preflight; refusing activation." >&2
    exit 1
  }
  if [ "$_tmux_initial_phase" != ready ]; then
    _tmux_activation_inventory=$(_tmux_inventory) || exit 1
    _tmux_activation_token=$(_tmux_make_review_token "$_tmux_current_pid" "$_tmux_activation_inventory") || exit 1
    [ "${TMUX_PERSISTENCE_MIGRATION_APPROVAL:-}" = "$_tmux_review_token" ] && \
      [ "$_tmux_activation_token" = "$_tmux_review_token" ] || {
      echo "The approved tmux topology changed before activation; review it again." >&2
      exit 1
    }
  fi
elif [ -n "$_tmux_current_pid" ]; then
  echo "A tmux server appeared after preflight; refusing activation." >&2
  exit 1
fi
ln -sfn "$(pwd)/tmux/tmux.conf" ~/.tmux.conf
if [ -n "$_tmux_validated_pid" ]; then
  _tmux_default source-file ~/.tmux.conf || {
    echo "tmux config reload failed; leaving the live server running." >&2
    exit 1
  }
  if [ "$_tmux_initial_phase" = ready ]; then
    ~/.shell-setup/tmux-persistence.sh save || {
      echo "Coordinated tmux save failed; leaving the live server running." >&2
      exit 1
    }
  else
    ~/.shell-setup/tmux-persistence.sh save --seed || {
      echo "Approved migration seed failed; leaving the live server running." >&2
      exit 1
    }
  fi
  ~/.shell-setup/tmux-persistence.sh validate-current || {
    echo "The managed generation is incomplete or differs from live tmux; leaving the server running." >&2
    exit 1
  }
fi

# Pin the validated server through the handoff. Never kill a process that
# appeared after validation, and never replace a server while clients exist.
_tmux_current_pid=$(_tmux_default display-message -p '#{pid}' 2>/dev/null || true)
if [ -n "$_tmux_validated_pid" ]; then
  [ "$_tmux_current_pid" = "$_tmux_validated_pid" ] || {
    echo "tmux changed after validation; refusing ownership transfer." >&2
    exit 1
  }
  [ -z "$(_tmux_default list-clients -F '#{client_name}' 2>/dev/null || true)" ] || {
    echo "A tmux client attached after validation; refusing ownership transfer." >&2
    exit 1
  }
elif [ -n "$_tmux_current_pid" ]; then
  echo "A tmux server appeared after the initial check; refusing ownership transfer." >&2
  exit 1
fi

if launchctl print gui/$(id -u)/local.shell-setup.tmux-server >/dev/null 2>&1; then
  launchctl bootout gui/$(id -u)/local.shell-setup.tmux-server || exit 1
fi
# Stop a manually owned default server only after its managed generation has
# validated and only from the plain shell required above.
_tmux_current_pid=$(_tmux_default display-message -p '#{pid}' 2>/dev/null || true)
if [ -n "$_tmux_current_pid" ]; then
  [ -n "$_tmux_validated_pid" ] && [ "$_tmux_current_pid" = "$_tmux_validated_pid" ] || {
    echo "An unvalidated tmux server owns the socket; refusing to kill it." >&2
    exit 1
  }
  [ -z "$(_tmux_default list-clients -F '#{client_name}' 2>/dev/null || true)" ] || {
    echo "A tmux client is attached; refusing to kill the server." >&2
    exit 1
  }
  _tmux_default kill-server || exit 1
fi
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/local.shell-setup.tmux-server.plist || exit 1
~/.shell-setup/tmux-persistence.sh wait-ready || exit 1
~/.shell-setup/tmux-persistence.sh status
# Retire the unused plugin only after its coordinated replacement is healthy.
if [ -d ~/.tmux/plugins/tmux-continuum ]; then
  mkdir -p "$HOME/.Trash" || exit 1
  mv ~/.tmux/plugins/tmux-continuum \
    "$HOME/.Trash/tmux-continuum.$(date +%Y%m%dT%H%M%S)" || exit 1
fi
unset TMUX_PERSISTENCE_MIGRATION_APPROVAL
unset _tmux_validated_pid _tmux_current_pid _tmux_initial_phase
unset _tmux_reviewed_inventory _tmux_review_token
unset _tmux_activation_inventory _tmux_activation_token
unset -f _tmux_default _tmux_inventory _tmux_make_review_token
```

When the block stops on a live server that predates the coordinator, report
the displayed session, window, and pane inventory and wait for confirmation.
Only after the user confirms that topology may be adopted, export
the exact `TMUX_PERSISTENCE_MIGRATION_APPROVAL` token printed by the preflight
and rerun all of §17 from the same plain, detached shell. The token binds the
approval to that server PID and topology. The second run rechecks both before
activating the new config, then publishes and validates the migration seed and
transfers ownership without another pause.

The plist is a copy, so editing `tmux/local.shell-setup.tmux-server.plist` needs
the `cp` above plus a reload for launchd to see it. From a plain non-tmux
shell, save first, then reload:

```bash
[ -z "${TMUX:-}" ] || {
  echo "Run this ownership transfer from a plain non-tmux shell." >&2
  exit 1
}
_tmux_default() {
  env -u TMUX -u TMUX_PANE -u TMUX_TMPDIR tmux -N -L default "$@"
}
_tmux_validated_pid=$(_tmux_default display-message -p '#{pid}' 2>/dev/null || true)
[ -n "$_tmux_validated_pid" ] || {
  echo "No tmux server is available to save; refusing ownership transfer." >&2
  exit 1
}
[ -z "$(_tmux_default list-clients -F '#{client_name}' 2>/dev/null || true)" ] || {
  echo "Detach every tmux client before transferring server ownership." >&2
  exit 1
}
~/.shell-setup/tmux-persistence.sh save || exit 1
~/.shell-setup/tmux-persistence.sh validate-current || exit 1
_tmux_current_pid=$(_tmux_default display-message -p '#{pid}' 2>/dev/null || true)
[ "$_tmux_current_pid" = "$_tmux_validated_pid" ] || {
  echo "tmux changed after validation; refusing ownership transfer." >&2
  exit 1
}
if launchctl print gui/$(id -u)/local.shell-setup.tmux-server >/dev/null 2>&1; then
  launchctl bootout gui/$(id -u)/local.shell-setup.tmux-server || exit 1
fi
_tmux_current_pid=$(_tmux_default display-message -p '#{pid}' 2>/dev/null || true)
if [ -n "$_tmux_current_pid" ]; then
  [ "$_tmux_current_pid" = "$_tmux_validated_pid" ] || {
    echo "An unvalidated tmux server owns the socket; refusing to kill it." >&2
    exit 1
  }
  [ -z "$(_tmux_default list-clients -F '#{client_name}' 2>/dev/null || true)" ] || {
    echo "A tmux client is attached; refusing to kill the server." >&2
    exit 1
  }
  _tmux_default kill-server || exit 1
fi
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/local.shell-setup.tmux-server.plist || exit 1
~/.shell-setup/tmux-persistence.sh wait-ready || exit 1
~/.shell-setup/tmux-persistence.sh status
unset _tmux_validated_pid _tmux_current_pid
unset -f _tmux_default
```

Reload any running tmux session with `tmux source-file ~/.tmux.conf` (or `prefix + :source ~/.tmux.conf`).

Session persistence: the coordinator serializes every save under a full-duration kernel lock and publishes a timestamped layout, pane-content archive, and assistant-session map as one generation in `~/.local/share/tmux/resurrect/`. It saves every 15 minutes and on client detach, retains the newest 96 complete generations, ages unkeyed legacy layouts after 30 days while preserving the newest five, and repairs interrupted publications. Saves remain paused until startup restore verifies exact session/window/pane identity; pane cwd differences are recorded as non-gating diagnostics. Ghostty waits up to 10 seconds for an attachable server and, when a persistence operation holds the lock, up to another 60 seconds to reserve a session; expiry falls back to a plain shell. A completed degraded restore remains attachable while saves stay paused. Manual save/restore: `prefix + Ctrl-s` / `prefix + Ctrl-r`.

Health and recovery: `~/.shell-setup/tmux-persistence.sh status` reports the current gate and log path. A red tmux status warning means saves are paused or the last save failed. For an intentional topology collapse, use `~/.shell-setup/tmux-persistence.sh restore --accept-risk`; after inspecting a degraded live restore, use `~/.shell-setup/tmux-persistence.sh acknowledge`. To roll back, repoint `~/.local/share/tmux/resurrect/last` at an older managed `tmux_resurrect_*.txt` and restore normally; its keyed sidecars are staged automatically. Unkeyed layouts predating the coordinator are not restorable and are pruned by age.

Panes whose command starts with `npm start` are relaunched verbatim on restore (`@resurrect-processes`, additive to resurrect's default whitelist of vim/less/top/…). On top of the layout, panes running **Claude Code or Codex CLI get their conversations resumed**: the coordinator invokes `tmux/assistant-resurrect/` (a trimmed-down take on [timvw/tmux-assistant-resurrect](https://github.com/timvw/tmux-assistant-resurrect)) to record each pane's assistant session ID and relaunch that ID in the restored pane. SessionStart tracking uses one `session-track.sh <tool>` hook registered in `.claude/settings.json` for Claude and `.codex/hooks.json` for Codex (see §15). Codex uses `resume-codex.sh <id>` so a successful startup update retries the same ID with the new binary. When no hook record exists, save falls back per assistant: Claude to the newest transcript for the cwd (same semantics as `claude --continue`), Codex to its `~/.codex/state_*.sqlite` thread DB (opened `immutable` since the running Codex app-server holds the file).

## 18. Restore herdr Configuration

Install herdr with its native installer (`~/.local/bin/herdr`, updated with
`herdr update`), then symlink the config and the Claude launcher — symlinks,
not copies, same reasoning as §16. The keybinds mirror the tmux chords so the
same muscle memory works in both.

```bash
command -v herdr >/dev/null || curl -fsSL https://herdr.dev/install.sh | sh
mkdir -p ~/.config/herdr ~/.shell-setup
ln -sfn "$(pwd)/herdr/config.toml" ~/.config/herdr/config.toml
ln -sfn "$(pwd)/herdr/claude-pane.sh" ~/.shell-setup/claude-pane.sh
herdr config check
herdr status server >/dev/null 2>&1 && herdr server reload-config
```

The launcher needs `jq` (§3). If `~/.config/herdr/config.toml` is a regular
file, reconcile its differences into the repo first, then re-symlink.

## 19. Post-Setup Verification

Run these checks and report results:

```bash
zsh -c 'source ~/.zshrc && echo "zsh: OK"'
brew --version
nvm --version
node --version
npm --version
go version
gh --version
claude --version
codex --version
```

Confirm that `~/.nvm/versions/node/` contains the installed node version (not empty).

Confirm `claude` resolves to the native install (`which claude` →
`~/.local/bin/claude`, a symlink into `~/.local/share/claude/versions/`), not
an npm global. Likewise `codex` → `~/.local/bin/codex` (a symlink into
`~/.codex/packages/standalone/`), not a Homebrew cask or npm global.

Confirm `~/.tmux.conf`, `~/.config/ghostty/config`, `~/.config/herdr/config.toml`,
and `~/.shell-setup/tmux-persistence.sh` are **symlinks into this repo** (`ls -l`
shows `->`), not copies — a copy silently drifts from the repo on the next edit.

Confirm the tmux server agent is loaded and running:

```bash
launchctl print gui/$(id -u)/local.shell-setup.tmux-server | grep -E "state|pid"
command -v python3
command -v jq
command -v sqlite3
~/.shell-setup/tmux-persistence.sh wait-ready
~/.shell-setup/tmux-persistence.sh status
```
