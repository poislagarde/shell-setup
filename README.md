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
├── statusline-command.sh    # statusline: ctx % + model[effort] (left), weekly + 5h usage (right); degrades to fit width, keeping the limit that runs out first
└── tests/                   # statusline reset-format and gauge-priority regression test
.codex/
├── config-defaults.toml     # Codex default model and reasoning effort
├── config-tui.toml          # Codex TUI: statusline (context, model, PR, limits) + whimsy off
├── config-features.toml     # Codex [features].hooks — hooks.json is inert without it
└── hooks.json               # Codex lifecycle hooks (session tracking, activity, worktree registration)
ghostty/
└── config                   # Ghostty terminal config (quick terminal, splits, NTE)
karabiner/
├── hyper.json               # Karabiner rule: Caps Lock → Hyper (merged into ~/.config/karabiner/karabiner.json)
└── merge-hyper.sh           # idempotent upsert of that rule into the selected profile
herdr/
├── PLUGIN-LANGUAGE.md       # workload-based criteria for choosing a plugin's language
├── tests/                  # private keyboard-history regression test
├── config.toml              # herdr config: tmux-compatible keybinds (symlinked to ~/.config/herdr/)
├── branch-labels.json       # personal sidebar regex (symlinked into the plugin's config directory)
├── branch-labels.ref        # pinned commit of the regex-based sidebar-label plugin
├── last-workspace.ref        # pinned commit of the workspace-history plugin
├── worktree-cleanup.ref      # pinned commit of the automatic worktree-cleanup plugin
├── worktree-cleanup-disposable.gitignore # optional rules permitting deletion of ignored files
├── pr-worktree.ref          # pinned commit of the GitHub PR worktree plugin
├── worktree-setup.ref        # pinned commit of the per-project worktree setup plugin
├── worktree-setup.example.toml # generic seed for local-only project setup commands
├── worktree-register.py      # Git creation hook installer + deferred ownership registration adapter
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

tmux is an alternative to herdr: use one or the other, never together or nested. Nothing auto-attaches; start or join a tmux session with `tm` (below). Prefix is the default **`Ctrl-b`** ("prefix, X" = press Ctrl-b, release, then X). The custom chords are **no-prefix** and share muscle memory with herdr (**tmux windows ↔ herdr spaces**, **tmux panes ↔ herdr tabs**). The two multiplexers' bindings are independent. tmux reads Cmd as Alt, so a Cmd chord lands on the matching Alt binding. If a chord fails, run `cat -v` in the pane, press it, and rebind what shows.

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

> The `Ctrl+Alt+…` chords add `Ctrl` to their plain counterparts and launch the `claude` alias (truecolor + `--chrome`) in the new window/pane — which closes when Claude exits. `Ctrl+Alt+p` opens in `$PROJECTS_DIR`, configured in the local-only `~/.config/shell-setup/local-env.sh`; it defaults to `$HOME`.

### Sessions

| Keys | Action |
| --- | --- |
| `Alt+Shift+S` | **Session picker** — `choose-tree`, each marked (attached)/(detached) |
| `Backspace` (in any of the three pickers) | Kill the highlighted session (asks y/n) |
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

herdr (`herdr/config.toml`) is the daily multiplexer. Use herdr or tmux, never together or nested. Some chords share muscle memory with tmux (**tmux windows ↔ herdr spaces**, **tmux panes ↔ herdr tabs**), but tmux bindings place no restrictions on herdr bindings. Check herdr shortcuts against herdr, Ghostty, and OS-level shortcuts. herdr's own defaults stay active alongside the custom bindings (`prefix+?` lists everything). Prefix is `Ctrl+B`.

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
| `Alt+Backtick` | Back through space history |
| `Alt+Shift+Backtick` | Forward through space history |
| `Alt+~` | Forward through space history (shifted-character alternate) |
| `Alt+Shift+S` / prefix, `s` / prefix, `w` | **Space picker** |
| prefix, `$` / prefix, `Shift+W` | Rename space |
| prefix, `Shift+D` | Close space |
| prefix, `Shift+G` | New space on a new git worktree |
| prefix, `Alt+G` | New worktree space from a GitHub PR URL |
| prefix, `d` / prefix, `q` | Detach (everything keeps running) |
| prefix, `b` | Toggle sidebar |
| prefix, `Shift+R` | Reload `config.toml` |
| prefix, `Shift+S` | herdr settings (moved off prefix, `s`) |
| prefix, `?` | List all key bindings |

PR worktrees use [herdr-pr-worktree](https://github.com/poislagarde/herdr-pr-worktree),
installed at the commit in `herdr/pr-worktree.ref` by bootstrap §18. From any
space, press `Ctrl+B`, then `Alt+G`, paste the PR's GitHub URL, and press Enter.
You can also run `herdr plugin action invoke poislagarde.pr-worktree.open`.
The plugin finds a matching repository in the current directory or another open
space in this herdr session, then opens the PR branch beneath that repository's
space. The current directory's repository is preferred; otherwise the first
matching open repository is used. Invoking from a linked worktree still opens
the PR beneath the repository's parent space. New worktrees use the fetched PR
head, including fork PRs. Existing worktrees are reused as-is, preserving local commits
and uncommitted changes. If the branch has different commits and no worktree,
update or rename it before retrying. Existing upstream settings are preserved;
new branches have no upstream.

Missing, unlocked checkouts are recreated when the local branch matches the PR
and the retained Git index is clean. The plugin backs up their metadata before
removing only the stale registration. Locked checkouts, staged changes, and
unavailable parent directories require manual repair. Remove temporary checkouts
with `git worktree remove /path/to/checkout`; use `git worktree move` to relocate
them, and lock checkouts on removable storage before disconnecting it.

Requires Python 3.9+, Git, and authenticated `gh` (`gh auth status`). The
repository needs a remote matching the URL's GitHub repository. If no matching
repository is open, open it in a space first.

New worktrees use [herdr-worktree-setup](https://github.com/tdi/herdr-worktree-setup),
installed at the commit in `herdr/worktree-setup.ref` by bootstrap §18.
Bootstrap seeds local `config.toml` in `herdr plugin config-dir tdi.worktree-setup`
from `herdr/worktree-setup.example.toml` only if no config exists. Store private
project paths and setup commands in that regular local file, outside this public
repository. Configure a main-checkout path and commands to run inside its new
worktrees. Keep setup scripts independent of Herdr: the configured command passes
`$HERDR_MAIN_REPO` as `--source` and `$HERDR_WORKTREE` as `--target`, as shown in
the example config. Config changes apply to the next worktree creation. The
plugin needs Node 18+ and npm to install; configured scripts may require their
own runtimes.
Inspect failures with `herdr plugin log list --plugin tdi.worktree-setup`; output is also
saved as `setup-*.log` in the plugin's state directory.

Sidebar branch labels use [herdr-branch-labels](https://github.com/poislagarde/herdr-branch-labels),
installed at the commit in `herdr/branch-labels.ref` by bootstrap §18.
`herdr/branch-labels.json` supplies this checkout's `type/YYYY-MM-DD-` stripping
rule and is symlinked into the plugin's configuration directory as `config.json`.
The standalone plugin leaves branch names unchanged until configured. Custom
space names are preserved. Patterns use `fancy-regex` syntax; replacements use
`$1` or `${name}` for captures. Labels refresh on server startup, space/worktree
lifecycle events, and space or pane focus. After editing the regex or switching
branches in the focused pane, change focus or run
`herdr plugin action invoke poislagarde.branch-labels.refresh`.

Space history uses [herdr-last-workspace](https://github.com/poislagarde/herdr-last-workspace),
installed at the commit in `herdr/last-workspace.ref` by bootstrap §18. It keeps
up to 256 visits per herdr session. Pane and tab changes within a space leave
the history alone. Going back and then choosing another space starts a new
branch; closed spaces are skipped. History begins when the plugin is installed.

### Worktree cleanup

Worktree cleanup uses [herdr-worktree-cleanup](https://github.com/poislagarde/herdr-worktree-cleanup),
installed at the commit in `herdr/worktree-cleanup.ref` by bootstrap §18. Closing
a linked worktree's last tab (including exiting its last shell) removes a clean
checkout when its remaining files are disposable. Unpushed commits, an open PR,
or no PR keep the local branch without blocking checkout removal. A branch is
deleted only when its PRs are closed or merged, its current tip is verified
recoverable from GitHub, and no other worktree uses it. GitHub failures retain
the branch.

#### Enroll repositories

After running `/shell-setup`, enroll each repository once to automatically
register worktrees created by ordinary `git worktree add`:

```sh
python3 ~/.shell-setup/worktree-register.py install /path/to/main-checkout
```

Repeat for each repository. The command is safe to rerun and takes effect
immediately. Bootstrap §18 restores paths from the local-only
`~/.config/herdr/worktree-repositories.txt` (or under `$XDG_CONFIG_HOME`), one
absolute checkout path per line. Blank lines and `#` comments are ignored.
Transfer that file separately between machines; keep repository inventories out
of this public checkout.

Create worktrees from the Herdr pane whose space should own them:

```sh
git -C /path/to/main-checkout worktree add -b my-feature /path/to/new-worktree
```

Closing that space checks its registered worktrees across enrolled repositories.
Worktrees created or opened through Herdr's own worktree commands are already
observed and need no Git-hook enrollment. Enrollment does not register existing
worktrees or run cleanup.

For an existing worktree or one created with `--no-checkout`, register it from
each Herdr space that will use it:

```sh
python3 ~/.shell-setup/worktree-register.py register /path/to/linked-checkout
```

All registered owner spaces must close before the worktree can be cleaned.
If a sandbox blocks access to Herdr, registration can queue a request when the
plugin's state directory is writable. The Claude/Codex tool-completion hooks
retry queued registrations; review and trust the Codex hook with `/hooks`.
To retry due requests manually:

```sh
python3 ~/.shell-setup/worktree-register.py drain
```

Registration and retry do not clean files. If a command reports an error,
fix the reported issue and rerun `register` from the owning Herdr pane.

The installer preserves `core.hooksPath` and other hooks. If it refuses a
repository's hook manager or relative hook path, use the
[manual hook-manager integration instructions](.claude/commands/shell-setup.md#18-restore-herdr-configuration).

#### Cleanup rules

Tracked changes, non-ignored untracked files, and unapproved ignored files keep
the checkout. Cleanup can still remove approved ignored files to reclaim space.
Use `herdr/worktree-cleanup-disposable.gitignore` for gitignore-style disposal
rules; bootstrap links this optional file into the plugin's config directory as
`disposable.gitignore`. Patterns apply only to ignored files; `!` exceptions
protect files. Ignored symlinks can be unlinked without following their targets;
hardlinks require another link outside the deletion set. Missing disposal rules
protect ordinary ignored files. Partial or skipped cleanup reports its blockers.

Worktrees used by another local herdr space or pane, locked worktrees, protected
branches, and active Git operations are protected. Inspection failures keep the
affected data. Worktree deletion runs without a timeout. Inspect decisions with
`herdr plugin log list --plugin poislagarde.worktree-cleanup`; disable automatic
checks with `herdr plugin disable poislagarde.worktree-cleanup`.

For accumulated worktrees, preview with
`herdr plugin action invoke poislagarde.worktree-cleanup.check-unused`, then run
`herdr plugin action invoke poislagarde.worktree-cleanup.clean-unused` to clean
unused recorded worktrees. The plugin records provenance at startup and when
spaces are opened or created; there are no periodic or startup cleanup runs.
Open an older unrecorded worktree in herdr once before including it in a sweep.

Primary checkouts are protected even when switched to a PR branch. Cleanup
requires herdr's linked-worktree provenance and Git's matching linked-worktree
registration and metadata; directory names alone do not establish eligibility.

### Agents

| Keys | Action |
| --- | --- |
| `Alt+Tab` | Next agent (agent-panel order: attention-needing first) |
| `Alt+Shift+Tab` | Previous agent |
| prefix, `o` | Jump to the agent behind the visible notification |

## herdr plugin development

Choose each plugin's language from its workload and maintenance cost. Use the
[plugin language criteria](herdr/PLUGIN-LANGUAGE.md) for new plugins and ports:
Rust where recurring execution or resource costs matter, and simple scripting
for occasional tool orchestration. Python is a deliberate choice, not a default.

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
| `Cmd+Q`, then `Cmd+Q` | Quit Ghostty |

Quitting by keyboard requires pressing `Cmd+Q` twice. Close confirmations are disabled, including for individual surfaces, menu quits, and system restarts.

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

## License

[MIT](LICENSE) © 2026 Pablo Ois Lagarde.
