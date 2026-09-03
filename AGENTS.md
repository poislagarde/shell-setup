# AGENTS.md

## Write instructions, not history

Files in this repo (configs, bootstrap steps, README) say **what to do**, not
the story of how the decision was reached. The bug that motivated a switch, the
alternative that was rejected, what the old behavior looked like — that's
commit-message material, not doc content. A terse constraint is fine ("use the
native installer, not npm"); a parenthetical recounting what went wrong with
the other option is not. If a *why* is genuinely needed to stop a future edit
from undoing the decision, keep it to one short clause.

## Applying shell-setup changes

When the user asks to change their shell setup in this directory, the change must
land in **two places**:

1. The tracked copy in **this repository** (the source of truth, restored on a
   fresh machine by `/shell-setup`).
2. The corresponding **live file in the user's home directory**, so the change
   takes effect immediately.

Editing only the repo copy leaves the running machine unchanged; editing only the
home copy means the change is lost on the next bootstrap. Always do both, then
tell the user how to reload (e.g. reload Ghostty config, `tmux source-file
~/.tmux.conf`, `source ~/.zshrc`).

> **Keep the README keybind cheatsheets in sync.** `README.md` has "herdr
> keybinds", "tmux keybinds" and "Ghostty keybinds" tables. Whenever you add,
> remove, or change a binding in `herdr/config.toml` (`[keys]` /
> `[[keys.command]]`), `tmux/tmux.conf` (`bind` / `bind -n` lines) or
> `ghostty/config` (`keybind = …` lines), update the matching README table in
> the same change — it's a third place the edit has to land. Skip the pure
> CSI-forwarding Ghostty keybinds (e.g. `keybind = super+alt+left=csi:1;11D`):
> those are plumbing that *implements* a herdr/tmux chord, not user-facing
> shortcuts, so they belong in those tables (as the chord they produce), not the
> Ghostty one. herdr's input parser does not decode `csi:27;<mod>;<key>~`
> forwarders, so don't add any.

> **Note:** most home files are **symlinks** back into this repo (or source it),
> so editing the repo file *is* editing the home file — there's only one place
> to change. Always check first with `ls -l` / `readlink` before editing, since
> the wiring differs per machine and per file.
>
> The wiring rule: link (symlink or a `source` stub) wherever possible, so a
> `git pull` of this checkout updates the live machine with no reinstall. A
> home file gets a copy/merge instead only when it accumulates state outside
> this repo during daily use, or when its consumer can't follow symlinks
> (launchd plists). Linking makes the checkout path load-bearing — it's baked
> into every symlink and the `~/.zshrc` stub, so don't move the checkout — and
> a pull updates files, not running processes: reload as usual. Repo files must
> never hardcode a machine path; anything path-specific is rendered into the
> home file at bootstrap time.
>
> Example setup:
>
> - `~/.config/ghostty/config` → symlink to `ghostty/config` (created by §16;
>   edit either; one file). If you find a regular file here instead, that's
>   drift — reconcile any differences into the repo, then re-symlink.
> - `~/.tmux.conf` → symlink to `tmux/tmux.conf` (created by §17; same rule).
> - `~/.zshrc` → **regular file**: machine-local lines plus a managed block
>   (created by §9) that just `source`s the repo's `zsh/zshrc` — edit the repo
>   file only; local additions stay outside the markers, never between them.
> - `~/.zprofile` → **regular file**, not linked (installer-owned,
>   machine-specific) — edit both the home file and the `shell-setup.md`
>   instructions (still inlined there).
> - `~/.claude/` → **regular directory**, not symlinked. `settings.json` is a
>   **merge** (Claude Code writes runtime state into the home copy) — edit both.
>   `~/.claude/statusline-command.sh` is a **symlink** to the repo file (created
>   by §15; edit either; one file). And `commands/shell-setup.md` (this
>   bootstrap command) lives **only** in the repo and is run one-time from here
>   — §15 deliberately excludes it from the `~/.claude/` copy, so it has just
>   one home: don't recreate it under `~/.claude/commands/`.
> - `~/.codex/hooks.json` → **merge**, not symlinked (the user may add hooks
>   there that this repo doesn't track, so §15 upserts only the entries whose
>   command lives under `~/.shell-setup` and leaves the rest alone) — edit both.
> - `~/.shell-setup/` → **regular directory of symlinks** into this repo (created
>   by §17), the home for every script and generated config this repo installs
>   outside a tool's own config dir. Scripts referenced from a config or a hook
>   go here, never into a tool's directory (`~/.tmux/` also holds TPM's
>   `plugins/` and resurrect's legacy `resurrect/`, so a path under it can't
>   identify a file as ours — which the `settings.json` hook merge relies on).

## Testing tmux changes

**Never run mutating tmux commands (`new-session`, `kill-session`, `kill-server`,
`send-keys`, …) against the default server.** The user's entire working
environment lives in it, so session names used in tests can collide with real
ones. (This has happened: a test `new-session -s quick` failed with "duplicate
session" because the real quick-terminal session had that name, and the cleanup
`kill-session` destroyed the user's whole environment, including the running
assistant panes.)

Run experiments on a throwaway server on a separate socket instead:

```bash
tmux -L cc-test -f /dev/null new-session -d -s whatever   # isolated server
tmux -L cc-test ...                                       # more test commands
tmux -L cc-test kill-server                               # clean up everything
```

After changing the persistence coordinator, its hooks, or its launchd wiring,
run both isolated suites:

```bash
tmux/tests/tmux-persistence-test.sh
tmux/tests/tmux-resurrect-contract-test.sh
```

The contract suite reports `SKIP` when the installed Resurrect plugin is absent.

After changing `tmux/status-refresh.sh` or the activity hooks, run
`tmux/tests/status-refresh-test.sh` — also confined to a private socket.

Against the default server, stick to read-only commands (`list-sessions`,
`list-panes`, `list-keys`, `display-message -p`, `show-options`). Reloading
config (`tmux source-file ~/.tmux.conf`) and `unbind`ing a stale binding are
fine. Don't kill real sessions unless the user explicitly asks — and even then,
check what's running in them first (`list-panes` + child processes). Target a
numerically-named session by its id (`-t '$5'`), never by name (`-t '=5'`):
the name form resolves to the current session, so the check inspects the
wrong session's panes.

The default server runs under launchd (`local.shell-setup.tmux-server`, KeepAlive), so
`kill-server` is a restart: launchd relaunches the server and the persistence
coordinator restores the latest verified generation. To actually stop it, use
`launchctl bootout gui/$(id -u)/local.shell-setup.tmux-server`; re-enable with
`launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/local.shell-setup.tmux-server.plist`.

If real state does get damaged: tmux-resurrect keeps timestamped snapshots in
`~/.local/share/tmux/resurrect/` — repoint the `last` symlink at a pre-damage
snapshot and run the guarded restore (`prefix + Ctrl-r` or
`~/.shell-setup/tmux-persistence.sh restore`). Managed snapshots stage their
matching pane-content and assistant-session companions automatically. Unkeyed
snapshots predating the coordinator are not restorable — they have no
companions that can be paired safely — so they are sent to review and pruned
by age. Never invoke the plugin's upstream `scripts/restore.sh` directly; that
bypasses locking, companion staging, and restore verification.

For a red persistence warning, run
`~/.shell-setup/tmux-persistence.sh status`. A `needs-review` state requires
choosing another snapshot or `restore --accept-risk`; a `degraded` state
requires inspecting `~/.local/state/tmux-persistence/last-restore.diff` before
`~/.shell-setup/tmux-persistence.sh acknowledge`. Completed degraded restores
remain attachable, but saves stay paused. A save failure leaves the prior
generation current; inspect the reported log and retry the save.

### Where each file maps

| Tool | Repo file | Home file |
| --- | --- | --- |
| Ghostty | `ghostty/config` | `~/.config/ghostty/config` |
| herdr | `herdr/config.toml` | `~/.config/herdr/config.toml` (symlink to the repo file; edit either; `herdr server reload-config`) |
| herdr Claude launcher | `herdr/claude-pane.sh` | `~/.shell-setup/claude-pane.sh` (symlink to the repo file; run by the `[[keys.command]]` bindings) |
| tmux | `tmux/tmux.conf` | `~/.tmux.conf` |
| tmux assistant-resurrect | `tmux/assistant-resurrect/` | `~/.shell-setup/assistant-resurrect` (symlink to the repo dir; edit either; one place) |
| tmux assistant-activity | `tmux/assistant-activity/` | `~/.shell-setup/assistant-activity` (symlink to the repo dir; edit either; one place) |
| tmux pane border | `tmux/pane-border-format.conf` (generated — edit `tmux/build-pane-border-format.sh` and re-run) | `~/.shell-setup/pane-border-format.conf` (symlink to the repo file; `source-file`d by `tmux.conf`) |
| tmux status refresh | `tmux/status-refresh.sh` | `~/.shell-setup/status-refresh.sh` (symlink to the repo file; `run-shell`'d by `tmux.conf`; the running loop survives reloads, so restart the tmux server to pick up edits) |
| tmux persistence | `tmux/tmux-persistence.sh` | `~/.shell-setup/tmux-persistence.sh` (symlink to the repo file; used by tmux hooks, keybindings, zsh readiness, and the launchd agent) |
| tmux server agent | `tmux/tmux-server-agent.sh` | `~/.shell-setup/tmux-server-agent.sh` (symlink to the repo file; run by the launchd agent) |
| tmux server LaunchAgent | `tmux/local.shell-setup.tmux-server.plist` | `~/Library/LaunchAgents/local.shell-setup.tmux-server.plist` (copy — launchd is unreliable with symlinked plists; after edits re-`cp`, then `launchctl bootout` + `bootstrap`) |
| Claude Code | `.claude/` (settings.json, commands) | `~/.claude/` |
| Claude Code statusline | `.claude/statusline-command.sh` | `~/.claude/statusline-command.sh` (symlink to the repo file) |
| Codex CLI | `.codex/hooks.json` | `~/.codex/hooks.json` (merge — may hold user hooks this repo doesn't track, so only the `~/.shell-setup` entries are upserted; Codex must be told to *trust* each hook on first run and after every change to it) |
| Codex features | `.codex/config-features.toml` | the `[features].hooks` key of `~/.codex/config.toml` (merge that key only; preserve every other flag) |
| Codex defaults | `.codex/config-defaults.toml` | the top-level `model` and `model_reasoning_effort` keys of `~/.codex/config.toml` (merge those keys only; preserve the rest) |
| Codex TUI | `.codex/config-tui.toml` | the `[tui]` block of `~/.codex/config.toml` (merge that block only; preserve every other section) |
| zsh (`~/.zshrc`) | `zsh/zshrc` | `~/.zshrc` (managed block `source`s the repo file — edit the repo file only) |
| zsh (`~/.zprofile`) | described in `.claude/commands/shell-setup.md` | `~/.zprofile` |
