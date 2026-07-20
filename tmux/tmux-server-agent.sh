#!/bin/sh
# launchd agent entry point (local.shell-setup.tmux-server): run the tmux server in the
# foreground (`tmux -D`) so launchd owns its lifetime — no terminal app's
# death can take it down, and KeepAlive restarts it after a kill, where config
# load + continuum auto-restore rebuild every session. `-D` also turns
# exit-empty off, so the server survives having zero sessions.
#
# If a server this agent didn't start already owns the default socket (e.g.
# one booted by a shell before the agent was installed), wait for it to exit
# instead of crash-looping against the bound socket, then take over.
TMUX=/opt/homebrew/bin/tmux
exec >>"$HOME/Library/Logs/tmux-server-agent.log" 2>&1
while "$TMUX" has-session 2>/dev/null; do
	sleep 30
done
echo "[$(date)] starting tmux server"
exec "$TMUX" -D
