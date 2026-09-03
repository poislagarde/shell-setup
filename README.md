# shell-setup

My personal macOS bootstrap, packaged as a Claude Code slash command so any fresh macOS machine can be brought up to my baseline by handing the instructions to Claude.

## Usage

Clone this repo, `cd` into it, then in Claude Code run:

```
/shell-setup
```

The command lives at [`.claude/commands/shell-setup.md`](.claude/commands/shell-setup.md). Claude runs each section in order and pauses for verification between sections.

## What it does

Claude runs a 20-section checklist top to bottom, pausing for verification between sections. At a high level:

- **Packages** — Homebrew, taps, CLI formulae (`gh`, `go`, `nvm`, `tmux`, `pipx`, `auth0`, …), and casks (`ghostty`, `gcloud-cli`, …).
- **Node** — nvm pinned to `~/.nvm` (survives `brew upgrade`), latest LTS as `default`.
- **Shell** — Oh My Zsh plus an idempotent **managed block** appended to `~/.zshrc` that sources this repo's `zsh/zshrc` (theme, plugins, PATH, completions, the `awsenv` / `tm` helpers, and keyboard tweaks) — so `git pull` updates the live shell. tmux no longer auto-starts; `tm` attaches on demand.
- **AWS** — official CLI installer + interactive SSO profile setup (`prod` / `prod-admin` / `dev`).
- **Git** — a `git up` alias and [`git-mux`](https://github.com/poislagarde/git-mux) for running a command across many repos with per-host SSH multiplexing.
- **Dotfiles** — Claude Code (`.claude/`), Ghostty, herdr, and tmux configs; tmux-resurrect plus a guarded persistence coordinator keep sessions, layouts, scrollback, and Claude/Codex conversations across Ghostty quits and reboots.

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
├── config-features.toml     # Codex [features].hooks — hooks.json is inert without it
└── hooks.json               # Codex lifecycle hooks (session tracking + activity indicator)
ghostty/
└── config                   # Ghostty terminal config (quick terminal, splits, NTE)
karabiner/
├── hyper.json               # Karabiner rule: Caps Lock → Hyper (merged into ~/.config/karabiner/karabiner.json)
└── merge-hyper.sh           # idempotent upsert of that rule into the selected profile
herdr/
├── config.toml              # herdr config: tmux-compatible keybinds (symlinked to ~/.config/herdr/)
└── claude-pane.sh           # opens a herdr tab/split running Claude Code (symlinked to ~/.shell-setup/)
tmux/
├── tmux.conf                            # tmux config (mouse support, guarded Resurrect persistence)
├── build-pane-border-format.sh          # generates the responsive pane-border-format (run after edits)
├── pane-border-format.conf              # generated; source-file'd by tmux.conf (symlinked to ~/.shell-setup/)
├── local.shell-setup.tmux-server.plist  # LaunchAgent: launchd owns the tmux server (copied to ~/Library/LaunchAgents/)
├── tmux-server-agent.sh                 # launchd supervisor for the server, startup restore, and save timer
├── tmux-persistence.sh                  # serialized generations, restore verification, readiness, and retention
├── tests/
│   ├── tmux-persistence-test.sh         # isolated coordinator integration suite
│   └── tmux-resurrect-contract-test.sh  # contract against the installed Resurrect plugin
├── assistant-resurrect/                 # coordinator helpers: save/resume Claude Code + Codex sessions
└── assistant-activity/                  # assistant hooks: window-label activity states + pane auto-focus
zsh/
└── zshrc                    # sourced by ~/.zshrc's managed block (theme/plugins, PATH, keybinds, awsenv)
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
| `codex` *(alias)* | OpenAI Codex CLI, aliased to force `model_reasoning_effort=ultra` on every launch (Codex rewrites the value in `~/.codex/config.toml`, so the config alone doesn't stick). `codex` to start; `codex resume <id>`. Installed via its native installer (§8) — update with `codex update`. |
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

tmux stays installed but nothing auto-attaches: start or join a session with `tm` (below). Prefix is the default **`Ctrl-b`** ("prefix, X" = press Ctrl-b, release, then X). The custom chords are **no-prefix** and mirror the herdr ones (**tmux windows ↔ herdr spaces**, **tmux panes ↔ herdr tabs**); they fire only when tmux owns the keyboard. tmux reads Cmd as Alt, so a Cmd chord lands on the matching Alt binding. If a chord fails, run `cat -v` in the pane, press it, and rebind what shows.

### Windows (tabs)

| Keys | Action |
| --- | --- |
| `Alt+=` | New window |
| `Ctrl+Alt+=` | New window running **Claude Code** (at `$HOME`) |
| `Ctrl+Alt+p` | New window running **Claude Code** in `$PROJECTS_DIR` |
| `Alt+]` | Next window |
| `Alt+[` | Previous window |
| `Alt+1` … `Alt+9` | Jump to window 1–9 (`Cmd+N` does the same: tmux reads Cmd as Alt) |
| `Alt+0` | Jump to window 10 |
| `Ctrl` + left-drag window tab | Move the dragged window; intervening tabs shift |
| prefix, `,` | Rename current window |
| prefix, `&` | Kill current window |

### Panes (splits)

| Keys | Action |
| --- | --- |
| `Cmd+Shift+=` | Split right (side-by-side), then rebalance pane sizes |
| `Cmd+Shift+-` | Split down (stacked), then rebalance pane sizes |
| `Ctrl+Alt+Shift+=` | Split right running **Claude Code** |
| `Ctrl+Alt+Shift+-` | Split down running **Claude Code** |
| Double-click pane border | Rebalance neighboring pane sizes |
| Right-click pane border / status strip | Pane context menu (paste, split, swap, kill, zoom) — works even when the pane's program captures the mouse |
| `Ctrl` + left-drag pane | Drag onto another pane to swap them |
| `Cmd+Opt+←/→/↑/↓` | Move focus between panes (spatial) |
| `Alt+Shift+1` … `Alt+Shift+9` | Jump to pane 1–9 (mirrors herdr tab N) |
| `Alt+Shift+]` / `Alt+Shift+[` | Next / previous pane (mirrors herdr tab cycling; `Cmd+Shift` does the same) |
| `Alt+Shift+Enter` | Zoom / unzoom active pane (fullscreen) |
| prefix, `z` | Zoom / unzoom (default alias) |
| prefix, `{` / `}` | Swap pane with previous / next |
| prefix, `x` | Kill current pane |
| prefix, `Space` | Cycle pane layouts |

> The `Ctrl+Alt+…` chords add `Ctrl` to their plain counterparts and launch the `claude` alias (truecolor + `--chrome`) in the new window/pane — which closes when Claude exits. `Ctrl+Alt+p` opens in `$PROJECTS_DIR`, set in `~/.zshrc` (the projects root you mostly work in).

### Sessions

| Keys | Action |
| --- | --- |
| `Alt+Shift+S` | **Session picker** — `choose-tree`, each marked (attached)/(detached) |
| `Backspace` (in picker) | Kill the highlighted session (asks y/n) |
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

> Sessions outlive the shell that created them; the launchd server keeps them (see Session persistence).

### Screen / scrollback

| Keys | Action |
| --- | --- |
| `Cmd+K` / `Ctrl-L` | Clear screen **and** tmux scrollback |
| Mouse wheel | Scroll into copy-mode (2 lines/notch) |
| prefix, `[` | Enter copy-mode (arrows/PgUp to scroll, `q` to quit) |
| prefix, `]` | Paste most recent buffer |

Copy-mode is vi-style: `Space` (or `Shift+Space`) start selection, `Enter` copy (also to the macOS clipboard), `/` search forward, `?` search back.

### Text input

| Keys | Action |
| --- | --- |
| `Shift+Space` | Insert a regular space |

### Session persistence

| Keys | Action |
| --- | --- |
| prefix, `Ctrl-s` | Save environment now |
| prefix, `Ctrl-r` | Restore last saved environment |

The launchd-owned server auto-saves every 15 minutes and on every Ghostty detach. Each new save publishes one timestamped layout, pane-content archive, and assistant-session map under `~/.local/share/tmux/resurrect/`; the newest 96 complete generations are retained. Legacy unkeyed layouts older than 30 days are pruned after the newest five, except any current or transaction-protected target. Startup uses a complete managed generation and enables later saves only after exact session/window/pane identity verifies. Pane cwd differences remain visible diagnostics without disabling saves. Claude Code / Codex panes then resume their conversations. If Codex updates during a restored launch, the same conversation resumes with the new binary.

The tmux server itself runs under launchd (`local.shell-setup.tmux-server`): it starts at login, lives outside any terminal app's process tree, and is restarted after any kill. Ghostty shells wait up to 10 seconds for an attachable server, then up to 60 seconds to reserve a session when a persistence operation holds the lock. They fall back to a plain shell when either bounded wait expires, the agent is unavailable, or persistence needs review. A completed degraded restore remains attachable while its save gate stays closed. `tmux kill-server` therefore acts as a full restart; to actually stop the server: `launchctl bootout gui/$(id -u)/local.shell-setup.tmux-server`.

Run `~/.shell-setup/tmux-persistence.sh status` for persistence health. A red status warning means saves are not silently advancing. For `needs-review`, choose another snapshot or run `restore --accept-risk`; for `degraded`, inspect `~/.local/state/tmux-persistence/last-restore.diff`, then run `acknowledge` to accept the live state and re-enable saves. A save failure keeps the prior generation current and remains visible until a later save succeeds; details are in `~/.local/state/tmux-persistence/persistence.log`.

To restore an older managed generation, repoint `last` at its `tmux_resurrect_*.txt` file and use `prefix + Ctrl-r`; the matching pane archive and assistant map are staged automatically. Unkeyed snapshots predating the coordinator are not restorable, because their singleton sidecars cannot be paired with a generation; they are pruned by age instead.

After changing the coordinator or its tmux wiring, run `tmux/tests/tmux-persistence-test.sh` and `tmux/tests/tmux-resurrect-contract-test.sh`. Both use private tmux sockets; the contract test reports `SKIP` when Resurrect is not installed.

### Assistant activity indicator

Window tabs color themselves by what the assistant running in them is doing, so a glance at the status line says which window needs you:

| Tab | Meaning |
| --- | --- |
| Grey text (or the plain orange slab, if current) | Idle, or no assistant — deliberately indistinguishable from a normal window |
| Text breathing green (current window: peach-orange) | Working |
| Text breathing magenta, twice as fast | Waiting on **you** — a permission prompt, a question, a plan to approve |

Switching to a window also selects the pane that wants you: the pane most recently blocked on input, or failing that the one that most recently finished a turn. The mark is consumed on arrival, so going back to a window later restores whichever pane you last used there.

State comes from lifecycle hooks both assistants fire (`tmux/assistant-activity/set-state.sh`, registered in `.claude/settings.json` and `.codex/hooks.json`), which record it in per-pane tmux options. A pane whose assistant reports nothing falls back to the spinner glyph in its title, and that glyph also overrules a "waiting on you" mark the assistant never resolved — Codex reports the request but not its outcome. A "working" claim expires after 5 minutes with no hook event unless the assistant still has a tool running, and any state clears when the assistant process goes away. `tmux/tests/status-refresh-test.sh` covers the aggregation on a private socket.

### Misc defaults worth knowing

| Keys | Action |
| --- | --- |
| prefix, `?` | List all key bindings |
| prefix, `:` | tmux command prompt |
| prefix, `c` | New window (default; `Alt+=` is the custom shortcut) |

## herdr keybinds

herdr (`herdr/config.toml`) is the daily multiplexer; tmux stays installed but no longer auto-starts. The chords mirror the tmux ones with **tmux windows ↔ herdr spaces** and **tmux panes ↔ herdr tabs**, so muscle memory carries over; herdr's own defaults stay active alongside (`prefix+?` lists everything). Prefix is `Ctrl+B`. tmux reads Cmd as Alt, so a Cmd chord inside tmux lands on the matching Alt binding.

### Tabs (tmux panes)

| Keys | Action |
| --- | --- |
| `Alt+Shift+=` / prefix, `c` | New tab |
| `Alt+Shift+]` / `Cmd+Shift+]` / prefix, `n` | Next tab |
| `Alt+Shift+[` / `Cmd+Shift+[` / prefix, `p` | Previous tab |
| `Alt+Shift+1` … `Alt+Shift+9` / prefix, `1` … `9` | Jump to tab 1–9 |
| prefix, `,` / prefix, `Shift+T` | Rename tab |
| prefix, `&` / prefix, `Shift+X` | Close tab |

### Panes (splits)

| Keys | Action |
| --- | --- |
| `Cmd+Shift+=` / prefix, `v` | Split right (side-by-side) |
| `Cmd+Shift+-` / prefix, `-` | Split down (stacked) |
| `Ctrl+Alt+Shift+=` | Split right running **Claude Code** |
| `Ctrl+Alt+Shift+-` | Split down running **Claude Code** |
| `Cmd+Opt+←/→/↑/↓` / prefix, `h`/`j`/`k`/`l` | Move focus between panes (spatial) |
| `Alt+Shift+Enter` / prefix, `z` | Zoom / unzoom active pane |
| prefix, `Tab` / prefix, `Shift+Tab` | Next / previous pane |
| prefix, `Shift+H`/`J`/`K`/`L` | Swap pane left/down/up/right |
| prefix, `r` | Resize mode (arrows, `Esc` to leave) |
| prefix, `Shift+P` | Rename pane |
| prefix, `x` | Close pane |
| prefix, `[` | Copy mode (`q` to quit) |
| prefix, `e` | Open scrollback in `$EDITOR` |

### Spaces (tmux windows)

| Keys | Action |
| --- | --- |
| `Alt+=` / prefix, `Shift+N` | New space |
| `Ctrl+Alt+=` | New space running **Claude Code** (at `$HOME`) |
| `Ctrl+Alt+p` | New space running **Claude Code** in `$PROJECTS_DIR` |
| `Alt+1` … `Alt+9` / prefix, `Shift+1` … `Shift+9` | Jump to space 1–9 |
| `Alt+]` / prefix, `)` | Next space |
| `Alt+[` / prefix, `(` | Previous space |
| `Alt+Shift+S` / prefix, `s` / prefix, `w` | **Space picker** |
| prefix, `$` / prefix, `Shift+W` | Rename space |
| prefix, `Shift+D` | Close space |
| prefix, `Shift+G` | New space on a new git worktree |
| prefix, `d` / prefix, `q` | Detach (everything keeps running) |
| prefix, `b` | Toggle sidebar |
| prefix, `Shift+R` | Reload `config.toml` |
| prefix, `Shift+S` | herdr settings (moved off prefix, `s`) |
| prefix, `?` | List all key bindings |

### Agents

| Keys | Action |
| --- | --- |
| `Alt+Tab` | Next agent (agent-panel order: attention-needing first) |
| `Alt+Shift+Tab` | Previous agent |
| prefix, `o` | Jump to the agent behind the visible notification |

## Ghostty keybinds

These act on Ghostty surfaces directly. Inside herdr or tmux, the Alt-based tab/pane chords above take over; the Cmd-based ones below stay with Ghostty.

### Quick terminal & splits

| Keys | Action |
| --- | --- |
| `Alt+Space` | Toggle the quick terminal (global — works from any app) |
| `Cmd+D` / `Cmd+Shift+D` | New native split right / down |
| `Cmd+]` / `Cmd+[` | Next / previous split |
| `Cmd+Shift+[` / `]`, `Cmd+Shift+=` / `-` | Forwarded to the terminal — herdr tab cycling and splits, tmux pane cycling and splits |
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
| `Shift+Enter` | Insert a literal newline in shells and Codex-style TUIs |
