# shell-setup

My personal macOS bootstrap, packaged as a Claude Code slash command so a fresh laptop can be brought up to my baseline by handing the instructions to Claude.

## Usage

Clone this repo, `cd` into it, then in Claude Code run:

```
/shell-setup
```

The command lives at [`.claude/commands/shell-setup.md`](.claude/commands/shell-setup.md). Claude runs each section in order and pauses for verification between sections.

## What it does

A 14-section provisioning checklist:

1. **Homebrew** — installer + PATH wiring for the current session.
2. **Taps** — `auth0/auth0-cli`.
3. **Formulae** — `autojump`, `auth0`, `bfg`, `gh`, `git-plus`, `go`, `libpq`, `nvm`, `pipx`, `railway`, `yt-dlp`.
4. **Casks** — `codex`, `gcloud-cli`, `sanesidebuttons`, `session-manager-plugin`.
5. **Oh My Zsh** — installer.
6. **NVM** — point `NVM_DIR` at `~/.nvm` so `brew upgrade nvm` can't wipe node installs.
7. **Node** — install latest LTS via nvm, alias `default`.
8. **Global npm packages** — `vercel`.
9. **`~/.zshrc`** — Oh My Zsh theme/plugins, NVM dir, Homebrew completions, user site-functions on `fpath`, PATH, AWS SSO alias, `claude` alias.
10. **Git** — `git up` alias for `pull --rebase --autostash`.
11. **`_git-multi` zsh completion** — custom completion that delegates to git's own subcommand completion so `git multi sw<TAB>` expands.
12. **`~/.zprofile`** — pipx PATH.
13. **Restore Claude Code config** — copies this repo's `.claude/` into `~/.claude/`. Uses `jq -s '.[0] * .[1]'` to deep-merge `settings.json` (this repo wins on key conflicts, untouched keys preserved) and `rsync -av` (no `--delete`) for everything else so runtime files in `~/.claude/` are left intact.
14. **Verification** — sources the new shell, prints versions, confirms node was installed under `~/.nvm/versions/node/`.

## Repo layout

```
.claude/
├── commands/
│   └── shell-setup.md       # the /shell-setup slash command
├── settings.json            # Claude Code settings (statusline, plugins, prefs)
└── statusline-command.sh    # 2-line statusline: cwd/worktree/branch + ctx % + 5h usage
```

`settings.local.json` is intentionally excluded — Claude Code treats it as machine-local and the standard global gitignore drops it.
