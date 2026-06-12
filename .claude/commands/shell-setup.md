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
  codex \
  gcloud-cli \
  ghostty \
  sanesidebuttons \
  session-manager-plugin
```

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

## 8. Install Global npm Packages

```bash
npm install -g vercel
```

(corepack and npm ship with node)

## 9. Append the managed block to ~/.zshrc

The `~/.zshrc` template lives in this repo at `zsh/zshrc`. Rather than
overwriting `~/.zshrc` (which would clobber whatever Oh My Zsh's installer just
wrote, plus any machine-local additions), append the template as a **managed
block** delimited by marker comments. On re-run, the old block is stripped and
the current template re-appended — so running this section multiple times
leaves the file in the same state as running it once (idempotent).

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

# Append the current template, wrapped in markers.
{
  printf '\n# >>> shell-setup managed >>>\n'
  cat zsh/zshrc
  printf '# <<< shell-setup managed <<<\n'
} >> ~/.zshrc
```

The managed block sets up Oh My Zsh (theme + shell-setup's required plugins),
points `NVM_DIR` at `~/.nvm`, wires Homebrew + user site-functions completions
onto `fpath`, the PATH, the `awsenv <profile>` AWS SSO helper, the
`claude` alias, and the `tm` session helper (`tm <name>` attaches/creates a
session; plain `tm` is a numbered picker marking sessions attached/detached
— inside tmux, Alt+Shift+S opens the equivalent choose-tree, see §17). Keyboard tweaks: `^U` → `backward-kill-line` (macOS
Cmd+Backspace semantics), Shift+Enter / Shift+Space re-encoded via the
Ghostty/tmux CSI 27 plumbing, Cmd+Opt+arrow edge-fallthrough no-ops, and a
precmd that re-asserts a blinking thin-bar cursor inside tmux. It ends with a
tmux auto-start for interactive Ghostty shells: the quick terminal (detected
via `GHOSTTY_QUICK_TERMINAL=1`, Ghostty ≥1.3; splits inside it inherit the
var only on builds newer than 1.3.1) owns
the `quick`/`quick-N` session namespace — each quick-terminal surface adopts
the lowest-numbered detached `quick*` session or mints the next free
`quick-N`; regular windows/tabs/panes do the same outside the namespace —
adopt the first detached non-quick session, else create `main`, else a fresh
auto-numbered session — so surfaces get distinct sessions instead of
mirroring one. Pairs with §17's resurrect/continuum persistence so all
sessions survive Ghostty quits and reboots.

Because the managed block lives at the end of `~/.zshrc`, its scalar
assignments (theme, `DISABLE_AUTO_TITLE`, etc.) win over anything earlier in
the file (zsh reads top-to-bottom, last assignment wins). The `plugins` array
is treated specially: the block uses `plugins+=(git nvm autojump golang)` plus
`typeset -U plugins` so any plugins the user enabled earlier in their zshrc
are preserved and merged with shell-setup's required ones (de-duplicated). The
re-`source $ZSH/oh-my-zsh.sh` inside the block re-runs OMZ with the merged
plugin list so the additions actually load.

> **Note:** if you tweak `zsh/zshrc` in the repo, re-run just the three
> commands above to refresh the managed block in `~/.zshrc`. If you edit the
> managed block in `~/.zshrc` directly (between the markers), copy the same
> change back into `zsh/zshrc` so a fresh laptop gets it. See `AGENTS.md`.

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

[`git-mux`](https://github.com/poislagarde/git-mux) runs a git command across every repo in a directory **serially with per-host SSH connection multiplexing** (one shared connection per server), so a bulk `git mux pull` doesn't trip a host's connection-rate throttle the way many parallel pulls do. Works for any SSH git host, not just GitHub. (It supersedes `git multi`, which is no longer installed.)

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

## 14. Write ~/.zprofile

```bash
# pipx
export PATH="$PATH:$HOME/.local/bin"
```

## 15. Restore Claude Code Configuration

Deep-copy this repo's `.claude/` into `~/.claude/`. For `settings.json` specifically, recursively merge so existing keys are preserved and this repo's values win on conflict (everything else is overwritten by this repo's copy; files already in `~/.claude/` that don't exist in the repo are left alone).

The merged `settings.json` includes SessionStart/SessionEnd hooks pointing at `~/.tmux/assistant-resurrect/` — the assistant session persistence scripts symlinked there by §17. Until §17 runs, Claude Code skips the missing hook scripts harmlessly.

Run from the root of this repo:

```bash
mkdir -p ~/.claude

# 1. Deep-merge settings.json: existing ⨯ repo (repo wins on conflict).
#    `jq -s '.[0] * .[1]'` recursively merges two JSON objects; the right
#    operand wins on leaf collisions and arrays are replaced (not concatenated).
if [ -f .claude/settings.json ]; then
  if [ -f ~/.claude/settings.json ]; then
    tmp=$(mktemp)
    jq -s '.[0] * .[1]' ~/.claude/settings.json .claude/settings.json > "$tmp" \
      && mv "$tmp" ~/.claude/settings.json
  else
    cp .claude/settings.json ~/.claude/settings.json
  fi
fi

# 2. Copy everything else, overwriting on conflict but preserving files in
#    ~/.claude that aren't in the repo (no --delete).
rsync -av --exclude='settings.json' .claude/ ~/.claude/

# 3. Make the statusline script executable.
[ -f ~/.claude/statusline-command.sh ] && chmod +x ~/.claude/statusline-command.sh
```

## 16. Restore Ghostty Configuration

Drop this repo's Ghostty config into `~/.config/ghostty/`. The file is a flat key=value config (no merging logic needed); overwrite if a prior config exists.

Run from the root of this repo:

```bash
mkdir -p ~/.config/ghostty
cp ghostty/config ~/.config/ghostty/config
```

Verify it parses:

```bash
/Applications/Ghostty.app/Contents/MacOS/ghostty +validate-config --config-file=~/.config/ghostty/config
```

Reload a running Ghostty with `⌘⇧,` to pick up the new config.

## 17. Restore tmux Configuration

Drop this repo's tmux config at `~/.tmux.conf`. Enables mouse support (scroll + click-to-select-pane) and session persistence across reboots (tmux-resurrect + tmux-continuum via TPM).

Run from the root of this repo:

```bash
cp tmux/tmux.conf ~/.tmux.conf

# Bootstrap TPM (tmux plugin manager) and install the plugins declared in
# tmux.conf (tmux-resurrect + tmux-continuum). install_plugins needs a running
# tmux server that has already sourced the config (TPM's `run` line exports
# TMUX_PLUGIN_MANAGER_PATH into it) — hence the start-server + source first.
git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm
tmux start-server
tmux source-file ~/.tmux.conf
~/.tmux/plugins/tpm/bin/install_plugins

# Assistant session persistence: symlink the resurrect hook scripts to the
# fixed path referenced by tmux.conf and ~/.claude/settings.json.
ln -sfn "$(pwd)/tmux/assistant-resurrect" ~/.tmux/assistant-resurrect
```

Reload any running tmux session with `tmux source-file ~/.tmux.conf` (or `prefix + :source ~/.tmux.conf`).

Session persistence: continuum auto-saves the environment (sessions, windows, panes, layouts, per-pane cwd, visible pane contents) to `~/.local/share/tmux/resurrect/` every 15 minutes, a `client-detached` hook additionally saves the moment Ghostty quits (including the automatic quit during macOS shutdown), and the environment auto-restores when the tmux server starts. Combined with the zshrc auto-start (§9: quick-terminal surfaces own the `quick`/`quick-N` session namespace, regular surfaces adopt/create the rest), quitting Ghostty or rebooting restores every session — each surface opened after a restart re-attaches one. Manual save/restore: `prefix + Ctrl-s` / `prefix + Ctrl-r`.

Panes whose command starts with `npm start` are relaunched verbatim on restore (`@resurrect-processes`, additive to resurrect's default whitelist of vim/less/top/…). On top of the layout, panes running **Claude Code or Codex CLI get their conversations resumed**: `tmux/assistant-resurrect/` (a trimmed-down take on [timvw/tmux-assistant-resurrect](https://github.com/timvw/tmux-assistant-resurrect)) hooks resurrect's save to record each pane's assistant session ID (Claude via a SessionStart hook registered in `.claude/settings.json` — see §15; Codex via its `~/.codex/state_*.sqlite` thread DB), and hooks resurrect's restore to type `claude --resume <id>` / `codex resume <id>` into the restored panes. Sessions started before the Claude hook existed fall back to a per-cwd newest-transcript lookup (same semantics as `claude --continue`).

## 18. Post-Setup Verification

Run these checks and report results:

```bash
zsh -c 'source ~/.zshrc && echo "zsh: OK"'
brew --version
nvm --version
node --version
npm --version
go version
gh --version
```

Confirm that `~/.nvm/versions/node/` contains the installed node version (not empty).
