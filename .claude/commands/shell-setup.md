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
  git-plus \
  go \
  libpq \
  nvm \
  pipx \
  railway \
  yt-dlp
```

## 4. Install Homebrew Casks

```bash
brew install --cask \
  codex \
  gcloud-cli \
  sanesidebuttons \
  session-manager-plugin
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

## 9. Write ~/.zshrc

Write the following to `~/.zshrc` (back up any existing one first):

```bash
# Oh My Zsh
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="refined"
zstyle ':omz:update' mode auto
DISABLE_AUTO_TITLE="true"
plugins=(git nvm autojump golang)

# NVM: use ~/.nvm so brew upgrades don't wipe node installations
export NVM_DIR="$HOME/.nvm"

# Homebrew Shell Completion
FPATH="$(brew --prefix)/share/zsh/site-functions:${FPATH}"

source $ZSH/oh-my-zsh.sh

# Editor
export EDITOR="zed --wait"

# User-installed zsh completions (must come BEFORE compinit so it picks them up)
fpath=("$HOME/.local/share/zsh/site-functions" $fpath)

# Fix for Docker & AWS plugin completions
autoload bashcompinit && bashcompinit
autoload -Uz compinit && compinit -i

# PATH
export PATH="$HOME/bin:$PATH"
export PATH="$PATH:$HOME/.local/bin"
export PATH="/opt/homebrew/opt/libpq/bin:$PATH"

# AWS SSO
alias awsdarwin-dev='export AWS_PROFILE=darwin-dev && aws sso login --profile darwin-dev && eval $(aws configure export-credentials --profile darwin-dev --format env)'

# Claude Code
alias claude='claude --effort max --enable-auto-mode --chrome'
```

## 10. Configure Git

```bash
git config --global alias.up 'pull --rebase --autostash'
```

## 11. Install `git multi` Completion

`git multi` (from `git-plus`) runs a git command in every subdirectory but ships with no zsh completion. Install one that delegates to git's own subcommand completion so `git multi sw<TAB>` expands to `git multi switch`, etc.

```bash
mkdir -p ~/.local/share/zsh/site-functions
cat > ~/.local/share/zsh/site-functions/_git-multi <<'EOF'
#compdef git-multi

# git-multi (from git-plus) runs a git command in every subdirectory.
# Complete its arguments as a regular git command line — same pattern
# zsh uses for `_git-for-each-repo`.
_git-multi() {
  _arguments -S \
    ':git command:_git_commands' \
    '*:: := _git'
}

_git-multi "$@"
EOF
rm -f ~/.zcompdump*
```

Open a fresh shell to pick up the regenerated completion cache.

> **Note:** The `~/.local/share/zsh/site-functions` line in `~/.zshrc` must come **before** `compinit` for any completions in that directory to be loaded. Section 9 already places it correctly.

## 12. Write ~/.zprofile

```bash
# pipx
export PATH="$PATH:$HOME/.local/bin"
```

## 13. Restore Claude Code Configuration

Deep-copy this repo's `.claude/` into `~/.claude/`. For `settings.json` specifically, recursively merge so existing keys are preserved and this repo's values win on conflict (everything else is overwritten by this repo's copy; files already in `~/.claude/` that don't exist in the repo are left alone).

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

## 14. Post-Setup Verification

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
