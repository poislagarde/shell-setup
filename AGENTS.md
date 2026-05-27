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
> - `~/.zshrc`, `~/.zprofile` → **regular files**, not symlinked — edit both the
>   home file and the `shell-setup.md` instructions.
> - `~/.claude/` → **regular directory**, not symlinked — edit both the repo
>   `.claude/` and `~/.claude/`.

### Where each file maps

| Tool | Repo file | Home file |
| --- | --- | --- |
| Ghostty | `ghostty/config` | `~/.config/ghostty/config` |
| tmux | `tmux/tmux.conf` | `~/.tmux.conf` |
| Claude Code | `.claude/` (settings.json, commands, statusline) | `~/.claude/` |
| zsh (`~/.zshrc`, `~/.zprofile`) | described in `.claude/commands/shell-setup.md` | `~/.zshrc`, `~/.zprofile` |
