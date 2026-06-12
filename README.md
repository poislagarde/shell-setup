# shell-setup

My personal macOS bootstrap, packaged as a Claude Code slash command so a fresh laptop can be brought up to my baseline by handing the instructions to Claude.

## Usage

Clone this repo, `cd` into it, then in Claude Code run:

```
/shell-setup
```

The command lives at [`.claude/commands/shell-setup.md`](.claude/commands/shell-setup.md). Claude runs each section in order and pauses for verification between sections.

## What it does

Claude runs an 18-section checklist top to bottom, pausing for verification between sections. At a high level:

- **Packages** — Homebrew, taps, CLI formulae (`gh`, `go`, `nvm`, `tmux`, `pipx`, `auth0`, …), and casks (`ghostty`, `codex`, `gcloud-cli`, …).
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

## tmux keybinds

Every Ghostty surface runs inside tmux, so this is where you mostly live. Prefix is the default **`Ctrl-b`** ("prefix, X" = press Ctrl-b, release, then X). The custom chords are **no-prefix** — Ghostty forwards Alt / Cmd+Opt keys into tmux, so they fire only when tmux owns the keyboard.

### Windows (tabs)

| Keys | Action |
| --- | --- |
| `Alt+=` | New window |
| `Alt+` `` ` `` | Next window |
| `Alt+Shift+` `` ` `` | Previous window |
| `Alt+1` … `Alt+9` | Jump to window 1–9 |
| `Alt+0` | Jump to window 0 |
| prefix, `,` | Rename current window |
| prefix, `&` | Kill current window |

### Panes (splits)

| Keys | Action |
| --- | --- |
| `Alt+Shift+=` | Split right (side-by-side) |
| `Alt+Shift+-` | Split down (stacked) |
| `Cmd+Opt+←/→/↑/↓` | Move focus between panes (spatial) |
| `Alt+Shift+Enter` | Zoom / unzoom active pane (fullscreen) |
| prefix, `z` | Zoom / unzoom (default alias) |
| prefix, `{` / `}` | Swap pane with previous / next |
| prefix, `x` | Kill current pane |
| prefix, `Space` | Cycle pane layouts |

> `Cmd+Opt+arrow` and `Alt+Shift+Enter` also drive Ghostty's own splits when you're *not* inside tmux — same keys, both layers.

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

Auto-saves every 15 min and on every Ghostty quit; auto-restores when the tmux server starts. Claude Code / Codex panes resume their conversations on restore.

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
| `Shift+Enter` | Insert a literal newline (multi-line editing) |
