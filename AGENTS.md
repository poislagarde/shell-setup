# AGENTS.md

## Applying shell-setup changes

When the user asks to change their shell setup in this directory, the change must
land in **two places**:

1. The tracked copy in **this repository** (the source of truth, restored on a
   fresh laptop by `/shell-setup`).
2. The corresponding **live file in the user's home directory**, so the change
   takes effect immediately.

Editing only the repo copy leaves the running machine unchanged; editing only the
home copy means the change is lost on the next bootstrap. Always do both, then
tell the user how to reload (e.g. reload Ghostty config, `tmux source-file
~/.tmux.conf`, `source ~/.zshrc`).

> **Note:** some home files may be **symlinks** back into this repo — in that
> case editing the repo file *is* editing the home file, so there's only one
> place to change. Always check first with `ls -l` / `readlink` before editing,
> since the wiring differs per machine and per file.
>
> Example setup:
>
> - `~/.config/ghostty/config` → symlink to `ghostty/config` (edit either; one file).
> - `~/.tmux.conf` → symlink to `tmux/tmux.conf` (edit either; one file).
> - `~/.zshrc` → **regular file**, not symlinked — edit both the home file and
>   the repo template `zsh/zshrc`.
> - `~/.zprofile` → **regular file**, not symlinked — edit both the home file and
>   the `shell-setup.md` instructions (still inlined there).
> - `~/.claude/` → **regular directory**, not symlinked — edit both the repo
>   `.claude/` and `~/.claude/`.

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
| Claude Code | `.claude/` (settings.json, commands, statusline) | `~/.claude/` |
| zsh (`~/.zshrc`) | `zsh/zshrc` | `~/.zshrc` |
| zsh (`~/.zprofile`) | described in `.claude/commands/shell-setup.md` | `~/.zprofile` |
