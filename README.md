# shell-setup

My personal macOS bootstrap, packaged as a Claude Code slash command so a fresh laptop can be brought up to my baseline by handing the instructions to Claude.

## Usage

Clone this repo, `cd` into it, then in Claude Code run:

```
/shell-setup
```

The command lives at [`.claude/commands/shell-setup.md`](.claude/commands/shell-setup.md). Claude runs each section in order and pauses for verification between sections.

## What it does

An 18-section provisioning checklist:

1. **Homebrew** — installer + PATH wiring for the current session.
2. **Taps** — `auth0/auth0-cli`.
3. **Formulae** — `autojump`, `auth0`, `bfg`, `gh`, `git-plus`, `go`, `libpq`, `nvm`, `pipx`, `railway`, `tmux`, `yt-dlp`.
4. **Casks** — `codex`, `gcloud-cli`, `ghostty`, `sanesidebuttons`, `session-manager-plugin`. Opens the Full Disk Access pane so Ghostty can be granted access.
5. **Oh My Zsh** — installer.
6. **NVM** — point `NVM_DIR` at `~/.nvm` so `brew upgrade nvm` can't wipe node installs.
7. **Node** — install latest LTS via nvm, alias `default`.
8. **Global npm packages** — `vercel`.
9. **`~/.zshrc`** — Oh My Zsh theme/plugins, NVM dir, Homebrew completions, user site-functions on `fpath`, PATH, AWS SSO alias, `claude` alias.
10. **AWS CLI** — official macOS installer.
11. **AWS SSO profiles** — interactive `prod` / `prod-admin` / `dev` setup.
12. **Git** — `git up` alias for `pull --rebase --autostash`.
13. **`_git-multi` zsh completion** — custom completion that delegates to git's own subcommand completion so `git multi sw<TAB>` expands.
14. **`~/.zprofile`** — pipx PATH.
15. **Restore Claude Code config** — copies this repo's `.claude/` into `~/.claude/`. Uses `jq -s '.[0] * .[1]'` to deep-merge `settings.json` (this repo wins on key conflicts, untouched keys preserved) and `rsync -av` (no `--delete`) for everything else so runtime files in `~/.claude/` are left intact.
16. **Restore Ghostty config** — copies this repo's `ghostty/config` to `~/.config/ghostty/config` (iTerm2-style quick terminal, splits, Natural Text Editing).
17. **Restore tmux config** — copies this repo's `tmux/tmux.conf` to `~/.tmux.conf` (mouse support on).
18. **Verification** — sources the new shell, prints versions, confirms node was installed under `~/.nvm/versions/node/`.

## Repo layout

```
.claude/
├── commands/
│   └── shell-setup.md       # the /shell-setup slash command
├── settings.json            # Claude Code settings (statusline, plugins, prefs)
└── statusline-command.sh    # 2-line statusline: cwd/worktree/branch + ctx % + 5h usage
ghostty/
└── config                   # Ghostty terminal config (quick terminal, splits, NTE)
tmux/
└── tmux.conf                # tmux config (mouse support on)
```

`settings.local.json` is intentionally excluded — Claude Code treats it as machine-local and the standard global gitignore drops it.
