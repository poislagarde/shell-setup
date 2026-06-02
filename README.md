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
3. **Formulae** — `autojump`, `auth0`, `bfg`, `gh`, `go`, `libpq`, `nvm`, `pipx`, `railway`, `tmux`, `yt-dlp`.
4. **Casks** — `codex`, `gcloud-cli`, `ghostty`, `sanesidebuttons`, `session-manager-plugin`. Opens the Full Disk Access pane so Ghostty can be granted access.
5. **Oh My Zsh** — installer.
6. **NVM** — point `NVM_DIR` at `~/.nvm` so `brew upgrade nvm` can't wipe node installs.
7. **Node** — install latest LTS via nvm, alias `default`.
8. **Global npm packages** — `vercel`.
9. **`~/.zshrc`** — appends this repo's `zsh/zshrc` to `~/.zshrc` as a **managed block** delimited by `# >>> shell-setup managed >>>` / `# <<< shell-setup managed <<<` markers. Re-runs strip the old block and re-append the current template, so the section is idempotent — the OMZ-installer-default zshrc and any machine-local additions are preserved. First run also stashes the pre-shell-setup file at `~/.zshrc.pre-shell-setup`. The block extends scalar OMZ opinions (theme, autotitle, update mode) but **adds** to the OMZ `plugins` array via `plugins+=(...)` + `typeset -U plugins`, so any plugins the user enabled in their own zshrc survive the merge (de-duplicated). The block re-sources OMZ so the merged plugin list takes effect. Block contents: Oh My Zsh theme + required plugins, NVM dir, Homebrew completions, user site-functions on `fpath`, PATH, `awsenv <profile>` AWS SSO helper, `claude` alias. Keyboard tweaks: `^U` → `backward-kill-line` (macOS Cmd+Backspace semantics), Shift+Enter inserts a literal newline (paired with the Ghostty/tmux CSI 27 plumbing), and a precmd that re-asserts a blinking thin-bar cursor (so inside tmux matches outside).
10. **AWS CLI** — official macOS installer.
11. **AWS SSO profiles** — interactive `prod` / `prod-admin` / `dev` setup.
12. **Git** — `git up` alias for `pull --rebase --autostash`.
13. **`git-mux`** — clones [`poislagarde/git-mux`](https://github.com/poislagarde/git-mux) into `~/repos/git-mux` and runs its `install.sh`, which symlinks the script to `~/bin/git-mux` and installs the `_git-mux` zsh completion. `git mux <cmd>` then runs a git command across repos **serially with per-host SSH connection multiplexing** (avoids tripping a host's connection-rate throttle); it supersedes `git multi`.
14. **`~/.zprofile`** — pipx PATH.
15. **Restore Claude Code config** — copies this repo's `.claude/` into `~/.claude/`. Uses `jq -s '.[0] * .[1]'` to deep-merge `settings.json` (this repo wins on key conflicts, untouched keys preserved) and `rsync -av` (no `--delete`) for everything else so runtime files in `~/.claude/` are left intact.
16. **Restore Ghostty config** — copies this repo's `ghostty/config` to `~/.config/ghostty/config` (quick terminal, splits, natural text editing keybinds).
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
zsh/
└── zshrc                    # ~/.zshrc template (theme/plugins, PATH, keybinds, awsenv)
```

`settings.local.json` is intentionally excluded — Claude Code treats it as machine-local and the standard global gitignore drops it.
