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

> **Keep the README keybind cheatsheets in sync.** `README.md` has "tmux
> keybinds" and "Ghostty keybinds" tables. Whenever you add, remove, or change a
> binding in `tmux/tmux.conf` (`bind` / `bind -n` lines) or `ghostty/config`
> (`keybind = …` lines), update the matching README table in the same change —
> it's a third place the edit has to land. Skip the pure CSI-forwarding Ghostty
> keybinds (e.g. `keybind = alt+shift+s=csi:27;4;115~`): those are plumbing that
> *implements* a tmux chord, not user-facing shortcuts, so they belong in the
> tmux table (as the chord they produce), not the Ghostty one.

> **Note:** some home files may be **symlinks** back into this repo — in that
> case editing the repo file *is* editing the home file, so there's only one
> place to change. Always check first with `ls -l` / `readlink` before editing,
> since the wiring differs per machine and per file.
>
> Example setup:
>
> - `~/.config/ghostty/config` → symlink to `ghostty/config` (created by §16;
>   edit either; one file). If you find a regular file here instead, that's
>   drift — reconcile any differences into the repo, then re-symlink.
> - `~/.tmux.conf` → symlink to `tmux/tmux.conf` (created by §17; same rule).
> - `~/.zshrc` → **regular file**, not symlinked — edit both the home file and
>   the repo template `zsh/zshrc`.
> - `~/.zprofile` → **regular file**, not symlinked — edit both the home file and
>   the `shell-setup.md` instructions (still inlined there).
> - `~/.claude/` → **regular directory**, not symlinked — edit both the repo
>   `.claude/` and `~/.claude/`. Exception: `commands/shell-setup.md` (this
>   bootstrap command) lives **only** in the repo and is run one-time from here
>   — §15 deliberately excludes it from the `~/.claude/` copy, so it has just
>   one home: don't recreate it under `~/.claude/commands/`.

## Testing tmux changes

**Never run mutating tmux commands (`new-session`, `kill-session`, `kill-server`,
`send-keys`, …) against the default server.** The user's entire working
environment lives in it — the zshrc auto-attach puts every Ghostty surface in
tmux, so session names used in tests can collide with real ones. (This has
happened: a test `new-session -s quick` failed with "duplicate session" because
the real quick-terminal session had that name, and the cleanup `kill-session`
destroyed the user's whole environment, including the running assistant panes.)

Run experiments on a throwaway server on a separate socket instead:

```bash
tmux -L cc-test -f /dev/null new-session -d -s whatever   # isolated server
tmux -L cc-test ...                                       # more test commands
tmux -L cc-test kill-server                               # clean up everything
```

Against the default server, stick to read-only commands (`list-sessions`,
`list-panes`, `list-keys`, `display-message -p`, `show-options`). Reloading
config (`tmux source-file ~/.tmux.conf`) and `unbind`ing a stale binding are
fine. Don't kill real sessions unless the user explicitly asks — and even then,
check what's running in them first (`list-panes` + child processes).

If real state does get damaged: tmux-resurrect keeps timestamped snapshots in
`~/.local/share/tmux/resurrect/` — repoint the `last` symlink at a pre-damage
snapshot and run resurrect's restore (`prefix + Ctrl-r` or the plugin's
`scripts/restore.sh`).

### Where each file maps

| Tool | Repo file | Home file |
| --- | --- | --- |
| Ghostty | `ghostty/config` | `~/.config/ghostty/config` |
| tmux | `tmux/tmux.conf` | `~/.tmux.conf` |
| tmux assistant-resurrect | `tmux/assistant-resurrect/` | `~/.tmux/assistant-resurrect` (symlink to the repo dir; edit either; one place) |
| tmux pane border | `tmux/pane-border-format.conf` (generated — edit `tmux/build-pane-border-format.sh` and re-run) | `~/.tmux/pane-border-format.conf` (symlink to the repo file; `source-file`d by `tmux.conf`) |
| tmux status refresh | `tmux/status-refresh.sh` | `~/.tmux/status-refresh.sh` (symlink to the repo file; `run-shell`'d by `tmux.conf`; the running loop survives reloads, so restart the tmux server to pick up edits) |
| Claude Code | `.claude/` (settings.json, commands, statusline) | `~/.claude/` |
| Codex CLI | `.codex/hooks.json` | `~/.codex/hooks.json` (copy; Codex must be told to *trust* the hook on first run) |
| Codex defaults | `.codex/config-defaults.toml` | the top-level `model` and `model_reasoning_effort` keys of `~/.codex/config.toml` (merge those keys only; preserve the rest) |
| Codex TUI | `.codex/config-tui.toml` | the `[tui]` block of `~/.codex/config.toml` (merge that block only; preserve every other section) |
| zsh (`~/.zshrc`) | `zsh/zshrc` | `~/.zshrc` |
| zsh (`~/.zprofile`) | described in `.claude/commands/shell-setup.md` | `~/.zprofile` |
