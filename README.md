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
9. **`~/.zshrc`** — appends this repo's `zsh/zshrc` to `~/.zshrc` as a **managed block** delimited by `# >>> shell-setup managed >>>` / `# <<< shell-setup managed <<<` markers. Re-runs strip the old block and re-append the current template, so the section is idempotent — the OMZ-installer-default zshrc and any machine-local additions are preserved. First run also stashes the pre-shell-setup file at `~/.zshrc.pre-shell-setup`. The block extends scalar OMZ opinions (theme, autotitle, update mode) but **adds** to the OMZ `plugins` array via `plugins+=(...)` + `typeset -U plugins`, so any plugins the user enabled in their own zshrc survive the merge (de-duplicated). The block re-sources OMZ so the merged plugin list takes effect. Block contents: Oh My Zsh theme + required plugins, NVM dir, Homebrew completions, user site-functions on `fpath`, PATH, `awsenv <profile>` AWS SSO helper, `claude` alias, a `tm` session helper (`tm <name>` attaches/creates; plain `tm` shows a numbered picker marking each session attached/detached — Alt+Shift+S inside tmux opens the equivalent choose-tree), and a tmux auto-start (the quick terminal — detected via `GHOSTTY_QUICK_TERMINAL`, Ghostty ≥1.3; splits inside it inherit the var only on builds newer than 1.3.1 — owns the `quick`/`quick-N` session namespace, each quick-terminal surface adopting the lowest detached one or minting the next free `quick-N`; regular Ghostty windows/tabs/panes adopt the first detached non-quick session or create `main` / an auto-numbered one — so surfaces get distinct sessions instead of mirroring, and after a reboot each new surface re-adopts a restored session in order — pairs with §17's session persistence). Keyboard tweaks: `^U` → `backward-kill-line` (macOS Cmd+Backspace semantics), Shift+Enter inserts a literal newline (paired with the Ghostty/tmux CSI 27 plumbing), and a precmd that re-asserts a blinking thin-bar cursor (so inside tmux matches outside).
10. **AWS CLI** — official macOS installer.
11. **AWS SSO profiles** — interactive `prod` / `prod-admin` / `dev` setup.
12. **Git** — `git up` alias for `pull --rebase --autostash`.
13. **`git-mux`** — clones [`poislagarde/git-mux`](https://github.com/poislagarde/git-mux) into `~/repos/git-mux`, runs its `install.sh` (symlinks the script to `~/.local/bin/git-mux`), and symlinks the shipped `_git-mux` zsh completion into site-functions. `git mux <cmd>` then runs a git command across repos **serially with per-host SSH connection multiplexing** (avoids tripping a host's connection-rate throttle); it supersedes `git multi`.
14. **`~/.zprofile`** — pipx PATH.
15. **Restore Claude Code config** — copies this repo's `.claude/` into `~/.claude/`. Uses `jq -s '.[0] * .[1]'` to deep-merge `settings.json` (this repo wins on key conflicts, untouched keys preserved) and `rsync -av` (no `--delete`) for everything else so runtime files in `~/.claude/` are left intact.
16. **Restore Ghostty config** — copies this repo's `ghostty/config` to `~/.config/ghostty/config` (quick terminal, splits, natural text editing keybinds, `window-save-state = always` so window/tab/split layout survives quits).
17. **Restore tmux config** — copies this repo's `tmux/tmux.conf` to `~/.tmux.conf` (mouse support on), bootstraps [TPM](https://github.com/tmux-plugins/tpm) into `~/.tmux/plugins/`, and installs tmux-resurrect + tmux-continuum: the tmux environment (sessions, windows, panes, layouts, cwds, visible pane contents) auto-saves every 15 min **and on every client detach** (so quitting Ghostty — including the automatic quit during a macOS restart — snapshots the latest state) and auto-restores when the server starts, so every tmux session survives Ghostty quits and reboots (paired with §9's auto-attach, surfaces opened after a restart re-adopt the restored sessions). `npm start` panes are relaunched on restore (`@resurrect-processes`). Also symlinks `tmux/assistant-resurrect/` to `~/.tmux/assistant-resurrect`: resurrect hook scripts (a trimmed-down take on [timvw/tmux-assistant-resurrect](https://github.com/timvw/tmux-assistant-resurrect)) that save each pane's **Claude Code / Codex CLI session ID** (Claude via a SessionStart hook in `.claude/settings.json`, Codex via its `~/.codex/state_*.sqlite` thread DB) and resume the conversations in the restored panes with `claude --resume <id>` / `codex resume <id>`.
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
├── tmux.conf                # tmux config (mouse support, resurrect/continuum persistence)
└── assistant-resurrect/     # resurrect hooks: save/resume Claude Code + Codex sessions
zsh/
└── zshrc                    # ~/.zshrc template (theme/plugins, PATH, keybinds, awsenv)
```

`settings.local.json` is intentionally excluded — Claude Code treats it as machine-local and the standard global gitignore drops it.
