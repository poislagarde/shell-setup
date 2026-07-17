# shell-setup

My personal macOS bootstrap, packaged as a Claude Code slash command so any fresh macOS machine can be brought up to my baseline by handing the instructions to Claude.

## Usage

Clone this repo, `cd` into it, then in Claude Code run:

```
/shell-setup
```

The command lives at [`.claude/commands/shell-setup.md`](.claude/commands/shell-setup.md). Claude runs each section in order and pauses for verification between sections.

## What it does

Claude runs an 18-section checklist top to bottom, pausing for verification between sections. At a high level:

- **Packages** — Homebrew, taps, CLI formulae (`gh`, `go`, `nvm`, `tmux`, `pipx`, `auth0`, …), and casks (`ghostty`, `gcloud-cli`, …).
- **Node** — nvm pinned to `~/.nvm` (survives `brew upgrade`), latest LTS as `default`.
- **Shell** — Oh My Zsh plus an idempotent **managed block** appended to `~/.zshrc` (theme, plugins, PATH, completions, the `awsenv` / `tm` helpers, keyboard tweaks, and a tmux auto-start that gives each Ghostty surface its own session).
- **AWS** — official CLI installer + interactive SSO profile setup (`prod` / `prod-admin` / `dev`).
- **Git** — a `git up` alias and [`git-mux`](https://github.com/poislagarde/git-mux) for running a command across many repos with per-host SSH multiplexing.
- **Dotfiles** — Claude Code (`.claude/`), Ghostty, and tmux configs; the latter two are wired with tmux-resurrect/continuum so sessions, layouts, and even Claude/Codex conversations survive Ghostty quits and reboots.

This list is deliberately non-exhaustive. The authoritative source — exact commands, idempotency rules, managed-block markers, and per-section verification — is **[`.claude/commands/shell-setup.md`](.claude/commands/shell-setup.md)**, the file Claude actually executes.

## Repo layout

```
.claude/
├── commands/
│   └── shell-setup.md       # the /shell-setup slash command
├── settings.json            # Claude Code settings (statusline, plugins, prefs)
└── statusline-command.sh    # statusline: ctx % + model[effort] (left), weekly + 5h usage (right); degrades to fit width
.codex/
├── config-defaults.toml     # Codex default model and reasoning effort
├── config-tui.toml          # Codex TUI statusline: context used + model/reasoning + PR + weekly/5h limits
└── hooks.json               # Codex SessionStart hook (assistant-resurrect session tracking)
ghostty/
└── config                   # Ghostty terminal config (quick terminal, splits, NTE)
tmux/
├── tmux.conf                    # tmux config (mouse support, resurrect/continuum persistence)
├── build-pane-border-format.sh  # generates the responsive pane-border-format (run after edits)
├── pane-border-format.conf      # generated; source-file'd by tmux.conf (symlinked to ~/.tmux/)
└── assistant-resurrect/         # resurrect hooks: save/resume Claude Code + Codex sessions
zsh/
└── zshrc                    # ~/.zshrc template (theme/plugins, PATH, keybinds, awsenv)
```

`settings.local.json` is intentionally excluded — Claude Code treats it as machine-local and the standard global gitignore drops it.

## Tools

What the setup puts on your PATH, plus the shell helpers and aliases it defines (marked *helper* / *alias* — these live in `~/.zshrc`, §9). Standard third-party CLIs get a one-liner; the custom and less-obvious tools get fuller usage. Listed alphabetically by command.

| Tool | What it does & how to use |
| --- | --- |
| `auth0` | Auth0 CLI. `auth0 login`, then e.g. `auth0 apps list`, `auth0 logs tail`. |
| `autojump` | Jump to a frequently-visited directory by partial name: `j repos`, `j shell`. Learns from your `cd` history (exposed as `j` via the OMZ plugin). |
| `awsenv` *(helper)* | Log into an AWS SSO profile and export its credentials into the current shell: `awsenv dev` / `awsenv prod` / `awsenv prod-admin` (the three profiles from §11). |
| `bfg` | BFG Repo-Cleaner — strip large files or secrets from git history. `bfg --delete-files secrets.txt` or `bfg --replace-text passwords.txt`, then `git reflog expire --expire=now --all && git gc --prune=now --aggressive`. |
| `claude` *(alias)* | Claude Code, aliased to `claude --chrome` with tmux truecolor forced on. `claude` to start, `claude --resume` / `claude --continue` to pick up a conversation. Installed via the native installer (§8) — update with `claude update`. |
| `codex` | OpenAI Codex CLI. `codex` to start; `codex resume <id>`. Installed via its native installer (§8) — update with `codex update`. |
| `cswap` | Switch between logged-in Claude Code accounts. Register once per account (log in first, then `cswap --add-account`); switch with `cswap --switch`, `cswap --switch-to <n\|email>`, or the `cswap --tui` menu; `cswap --list` shows registered accounts. Restart Claude Code after switching to pick up the new token. |
| `gcloud` | Google Cloud CLI. `gcloud auth login`, `gcloud config set project <id>`. |
| `gh` | GitHub CLI. `gh pr create`, `gh pr view --web`, `gh repo clone <repo>`. |
| `git mux` | Run a git command across every repo in a directory, serially with per-host SSH connection multiplexing. `git mux -n pull` (dry-run plan), `git mux pull`, `git mux switch <branch>`. Use `git-mux --help` directly — git intercepts `git mux --help`. |
| `git up` *(alias)* | `git pull --rebase --autostash`. |
| `go` | Go toolchain. `go build`, `go run .`, `go test ./...`. |
| `nvm` | Node version manager, pinned to `~/.nvm` so `brew upgrade` won't wipe it. `nvm install --lts`, `nvm use <version>`, `nvm ls`; latest LTS is the `default`. |
| `pipx` | Install Python CLI apps in isolated venvs. `pipx install <pkg>`, `pipx list`, `pipx upgrade-all`. |
| `psql` | Postgres client tools from `libpq`, put on PATH (`psql`, `pg_dump`, `pg_restore`). `psql <connection-string>`. |
| `railway` | Railway CLI. `railway login`, `railway link`, `railway run <cmd>`, `railway logs`. |
| `tm` *(helper)* | tmux session helper. `tm <name>` attaches to (or creates) a session; plain `tm` is a numbered picker. See [Sessions](#sessions) below. |
| `vercel` | Vercel CLI. `vercel` (preview deploy), `vercel --prod`, `vercel link`, `vercel env pull`. |
| `yt-dlp` | Download video/audio from YouTube and many other sites. `yt-dlp <url>`; `yt-dlp -x --audio-format mp3 <url>` for audio only. |

Also installed but used indirectly, not via their own command: **sanesidebuttons** (background app, runs at login — maps the mouse's side buttons to back/forward) and **session-manager-plugin** (lets the AWS CLI open a shell into EC2 without SSH: `aws ssm start-session --target <instance-id>`).

## tmux keybinds

Every Ghostty surface runs inside tmux, so this is where you mostly live. Prefix is the default **`Ctrl-b`** ("prefix, X" = press Ctrl-b, release, then X). The custom chords are **no-prefix** — Ghostty forwards Alt / Cmd+Opt keys into tmux, so they fire only when tmux owns the keyboard.

### Windows (tabs)

| Keys | Action |
| --- | --- |
| `Alt+=` | New window |
| `Ctrl+Alt+=` | New window running **Claude Code** (at `$HOME`) |
| `Ctrl+Alt+p` | New window running **Claude Code** in `$PROJECTS_DIR` |
| `Alt+` `` ` `` | Next window |
| `Alt+Shift+` `` ` `` | Previous window |
| `Alt+1` … `Alt+9` | Jump to window 1–9 |
| `Alt+0` | Jump to window 10 |
| `Ctrl` + left-drag window tab | Move the dragged window; intervening tabs shift |
| prefix, `,` | Rename current window |
| prefix, `&` | Kill current window |

### Panes (splits)

| Keys | Action |
| --- | --- |
| `Alt+Shift+=` | Split right (side-by-side), then rebalance pane sizes |
| `Alt+Shift+-` | Split down (stacked), then rebalance pane sizes |
| `Ctrl+Alt+Shift+=` | Split right running **Claude Code** |
| `Ctrl+Alt+Shift+-` | Split down running **Claude Code** |
| Double-click pane border | Rebalance neighboring pane sizes |
| `Ctrl` + left-drag pane | Drag onto another pane to swap them |
| `Cmd+Opt+←/→/↑/↓` | Move focus between panes (spatial) |
| `Alt+Shift+Enter` | Zoom / unzoom active pane (fullscreen) |
| prefix, `z` | Zoom / unzoom (default alias) |
| prefix, `{` / `}` | Swap pane with previous / next |
| prefix, `x` | Kill current pane |
| prefix, `Space` | Cycle pane layouts |

> `Cmd+Opt+arrow` and `Alt+Shift+Enter` also drive Ghostty's own splits when you're *not* inside tmux — same keys, both layers.

> The `Ctrl+Alt+…` chords add `Ctrl` to their plain counterparts and launch the `claude` alias (truecolor + `--chrome`) in the new window/pane — which closes when Claude exits. `Ctrl+Alt+p` opens in `$PROJECTS_DIR`, set in `~/.zshrc` (the projects root you mostly work in).

### Sessions

| Keys | Action |
| --- | --- |
| `Alt+Shift+S` | **Session picker** — `choose-tree`, each marked (attached)/(detached) |
| prefix, `s` | Session/window tree (default picker) |
| prefix, `w` | Window picker across sessions |
| prefix, `$` | Rename current session |
| prefix, `d` | Detach (drops to a plain shell; surface stays open) |

In a shell (inside or outside tmux):

| Command | Action |
| --- | --- |
| `tm` | Numbered session picker (attached/detached marked) |
| `tm <name>` | Attach to — or create — session `<name>` |
| `tmux kill-session -t <name>` | Kill a session (stops resurrect persisting it) |

> Session names are special: **`quick`** / `quick-N` are owned by the Ghostty quick terminal; regular windows/tabs auto-adopt any other detached session or create `main`.

### Screen / scrollback

| Keys | Action |
| --- | --- |
| `Cmd+K` / `Ctrl-L` | Clear screen **and** tmux scrollback |
| Mouse wheel | Scroll into copy-mode (2 lines/notch) |
| prefix, `[` | Enter copy-mode (arrows/PgUp to scroll, `q` to quit) |
| prefix, `]` | Paste most recent buffer |

Copy-mode is vi-style: `Space` start selection, `Enter` copy (also to the macOS clipboard), `/` search forward, `?` search back.

### Session persistence (resurrect + continuum)

| Keys | Action |
| --- | --- |
| prefix, `Ctrl-s` | Save environment now |
| prefix, `Ctrl-r` | Restore last saved environment |

Auto-saves every 15 min and on every Ghostty quit; auto-restores when the tmux server starts. Claude Code / Codex panes resume their conversations on restore. If Codex updates during a restored launch, the same conversation resumes with the new binary.

### Misc defaults worth knowing

| Keys | Action |
| --- | --- |
| prefix, `?` | List all key bindings |
| prefix, `:` | tmux command prompt |
| prefix, `c` | New window (default; `Alt+=` is the custom shortcut) |

## Ghostty keybinds

These act on Ghostty surfaces directly. Inside tmux, the Alt-based window/pane chords above take over (Ghostty forwards them); the Cmd-based ones below stay with Ghostty.

### Quick terminal & splits

| Keys | Action |
| --- | --- |
| `Alt+Space` | Toggle the quick terminal (global — works from any app) |
| `Ctrl+Shift+=` | Split right (side-by-side) |
| `Ctrl+Shift+-` | Split down (stacked) |
| `Cmd+Opt+←/→/↑/↓` | Move focus between splits (spatial) |
| `Alt+Shift+Enter` | Toggle split zoom |
| `Cmd+]` / `Cmd+[` | Next / previous split |
| `Cmd+W` | Close the split / surface |

### Screen / scrollback

| Keys | Action |
| --- | --- |
| `Cmd+K` | Clear screen (sends `Ctrl-L`; clears tmux scrollback too) |
| `Cmd+Shift+K` | Clear Ghostty's own scrollback buffer |

### Text editing at the prompt

The gaps Ghostty doesn't bind out of the box:

| Keys | Action |
| --- | --- |
| `Cmd+←` / `Cmd+→` | Start / end of line |
| `Cmd+Backspace` | Delete to line start |
| `Alt+←` / `Alt+→` | Word back / forward |
| `Alt+Backspace` | Delete word backward |
| `Alt+Delete` (`fn+Alt+Backspace`) | Delete word forward |
| `fn+Backspace` (`⌦`) | Forward-delete a character |
| `Shift+Space` | Insert a regular space |
| `Shift+Enter` | Insert a literal newline in shells and Codex-style TUIs |
