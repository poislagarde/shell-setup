#!/usr/bin/env python3
"""Install a Git creation hook and forward registration to Herdr's cleanup plugin."""

import argparse
import fcntl
import json
import os
from pathlib import Path
import re
import shlex
import subprocess
import sys
import tempfile


PLUGIN_ID = "poislagarde.worktree-cleanup"
MARKER = "# shell-setup: herdr worktree registration v1"
BACKUP = "post-checkout.shell-setup-original"


def git(checkout, *args):
    result = subprocess.run(
        ["git", "-C", str(checkout), *args],
        text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        timeout=10, check=False,
    )
    if result.returncode:
        raise RuntimeError("Git could not inspect the checkout")
    return result.stdout.rstrip("\n")


def hook_directory(checkout):
    root = Path(git(checkout, "rev-parse", "--show-toplevel")).resolve()
    configured = subprocess.run(
        ["git", "-C", str(root), "config", "--path", "--get", "core.hooksPath"],
        text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False,
    )
    if configured.returncode not in (0, 1):
        raise RuntimeError("Git could not read core.hooksPath")
    if configured.returncode == 0:
        directory = Path(configured.stdout.rstrip("\n"))
        if not directory.is_absolute():
            raise RuntimeError(
                "Relative core.hooksPath is unsupported: it points into each checkout. "
                "Keep its existing hook manager and add the registration adapter there explicitly."
            )
    else:
        directory = Path(git(root, "rev-parse", "--path-format=absolute", "--git-common-dir")) / "hooks"
    return directory


def install(checkout, adapter):
    adapter = Path(adapter).expanduser().absolute()
    if not adapter.is_file():
        raise RuntimeError("Link the registration adapter into ~/.shell-setup before installing hooks")
    directory = hook_directory(checkout)
    directory.mkdir(parents=True, exist_ok=True)
    hook = directory / "post-checkout"
    original = directory / BACKUP
    wrapper = "\n".join([
        "#!/bin/sh", MARKER,
        "# Keep the repository's original checkout hook and exit status.",
        "original=" + shlex.quote(str(original)),
        "status=0",
        'if [ -x "$original" ]; then',
        '  "$original" "$@"',
        "  status=$?",
        "fi",
        "python3 " + shlex.quote(str(adapter)) + ' post-checkout "$@" </dev/null || :',
        'exit "$status"', "",
    ])
    with (directory / ".shell-setup-post-checkout.lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        exists = os.path.lexists(hook)
        managed = exists and not hook.is_symlink() and hook.is_file() and MARKER in hook.read_text().splitlines()[:2]
        if exists and not managed and os.path.lexists(original):
            raise RuntimeError("An original checkout-hook backup already exists; reconcile it before installing")
        if exists and not managed and not (hook.is_file() or hook.is_symlink()):
            raise RuntimeError("The existing post-checkout hook is not a file or symlink")
        if exists and not managed and os.access(hook, os.X_OK):
            try:
                source = hook.read_text()
            except UnicodeError:
                raise RuntimeError("Cannot chain a binary post-checkout hook; configure its hook manager explicitly")
            if re.search(
                r"\$0|\$\{0\}|BASH_SOURCE|__file__|__filename|import\.meta|argv\s*\[\s*0\s*\]|husky|lefthook|pre-commit",
                source, re.IGNORECASE,
            ):
                raise RuntimeError(
                    "The existing post-checkout hook uses its own filename or a hook manager. "
                    "Add the registration adapter through that hook manager; this installer will not rename it."
                )
        temporary = None
        moved = False
        try:
            with tempfile.NamedTemporaryFile(mode="w", dir=directory, delete=False) as output:
                temporary = Path(output.name)
                output.write(wrapper)
            temporary.chmod(0o755)
            if exists and not managed:
                hook.rename(original)
                moved = True
            temporary.replace(hook)
        except BaseException:
            if moved and not os.path.lexists(hook):
                original.rename(hook)
            raise
        finally:
            if temporary and temporary.exists():
                temporary.unlink()
    print(f"Installed {hook}; prior post-checkout runs from {original}; core.hooksPath unchanged")


def installed_plugin():
    config_home = Path(os.environ.get("XDG_CONFIG_HOME") or Path.home() / ".config")
    registry = config_home / "herdr" / "plugins.json"
    try:
        data = json.loads(registry.read_text())
    except (OSError, ValueError):
        result = subprocess.run(
            [os.environ.get("HERDR_BIN_PATH") or "herdr", "plugin", "list", "--plugin", PLUGIN_ID, "--json"],
            text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=5, check=False,
        )
        if result.returncode:
            return None
        data = json.loads(result.stdout)
    if isinstance(data, dict):
        data = data.get("result", data)
    if isinstance(data, dict):
        data = data.get("plugins", [])
    if not isinstance(data, list):
        return None
    matches = [item for item in data if isinstance(item, dict) and item.get("plugin_id") == PLUGIN_ID]
    if len(matches) != 1 or matches[0].get("enabled") is not True:
        return None
    entry = matches[0]
    root = Path(entry.get("plugin_root", ""))
    manifest = Path(entry.get("manifest_path", ""))
    if not root.is_absolute() or not manifest.is_absolute():
        return None
    root = root.resolve()
    if manifest.resolve() != root / "herdr-plugin.toml":
        return None
    script = root / "plugin.py"
    if not script.is_file() or script.resolve().parent != root:
        return None
    if not re.search(r"(?m)^id\s*=\s*(['\"])" + re.escape(PLUGIN_ID) + r"\1\s*(?:#.*)?$", manifest.read_text()):
        return None
    return script


def delegate(arguments, required=False):
    plugin = installed_plugin()
    if plugin is None:
        if required:
            raise RuntimeError("Enable the installed worktree-cleanup plugin before registering this checkout")
        return True
    environment = os.environ.copy()
    environment["HERDR_PLUGIN_STATE_DIR"] = str(state_directory())
    config_home = Path(os.environ.get("XDG_CONFIG_HOME") or Path.home() / ".config")
    environment["HERDR_PLUGIN_CONFIG_DIR"] = str(config_home / "herdr" / "plugins" / "config" / PLUGIN_ID)
    result = subprocess.run(
        [sys.executable, str(plugin), *arguments],
        env=environment, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, text=True, check=False,
    )
    if result.stderr:
        print(result.stderr[:2000], end="", file=sys.stderr)
    if result.returncode:
        raise RuntimeError(f"Cleanup plugin registration returned exit {result.returncode}")
    response = json.loads(result.stdout)
    if not isinstance(response, dict):
        raise RuntimeError("Cleanup plugin returned an invalid registration result")
    results = [response] + (response.get("results") or [])
    accepted = True
    for item in results:
        if isinstance(item, dict) and item.get("outcome") in ("kept", "failed", "rejected"):
            accepted = False
            reason = str(item.get("reason") or "registration was not accepted")
            print(f"Herdr worktree registration: {reason[:1000]}", file=sys.stderr)
    return accepted


def state_directory():
    state_home = Path(os.environ.get("XDG_STATE_HOME") or Path.home() / ".local" / "state")
    return state_home / "herdr" / "plugins" / PLUGIN_ID


def drain():
    try:
        state = json.loads((state_directory() / "worktrees.json").read_text())
    except FileNotFoundError:
        return
    if isinstance(state, dict) and not state.get("pending"):
        return
    delegate(["drain"])


def post_checkout(arguments):
    if len(arguments) != 3 or arguments[2] != "1" or not re.fullmatch(r"(?:0{40}|0{64})", arguments[0]):
        return
    socket = os.environ.get("HERDR_SOCKET_PATH", "")
    if not socket or not Path(socket).is_absolute() or not os.environ.get("HERDR_PANE_ID"):
        return
    checkout = Path(git(Path.cwd(), "rev-parse", "--show-toplevel")).resolve()
    git_dir = Path(git(checkout, "rev-parse", "--path-format=absolute", "--git-dir")).resolve()
    common = Path(git(checkout, "rev-parse", "--path-format=absolute", "--git-common-dir")).resolve()
    if git_dir == common or not (checkout / ".git").is_file():
        return
    delegate(["register", "--checkout", str(checkout), "--defer-on-unavailable"])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    installer = commands.add_parser("install", help="chain a creation hook in this repository's current hook directory")
    installer.add_argument("checkout", type=Path)
    installer.add_argument("--adapter", type=Path, default=Path.home() / ".shell-setup" / "worktree-register.py")
    hook = commands.add_parser("post-checkout", help="Git hook entry point")
    hook.add_argument("arguments", nargs="*")
    registration = commands.add_parser("register", help="register an existing linked checkout, including --no-checkout worktrees")
    registration.add_argument("checkout", type=Path)
    commands.add_parser("drain", help="retry exact registrations deferred by a sandboxed Git hook")
    arguments = parser.parse_args()
    try:
        if arguments.command == "install":
            install(arguments.checkout, arguments.adapter)
        elif arguments.command == "post-checkout":
            post_checkout(arguments.arguments)
        elif arguments.command == "register":
            if not delegate(["register", "--checkout", str(arguments.checkout.resolve()), "--defer-on-unavailable"], required=True):
                return 1
        else:
            drain()
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        print(f"Herdr worktree registration: {error}", file=sys.stderr)
        return 1 if arguments.command in ("install", "register") else 0
    return 0


if __name__ == "__main__":
    sys.exit(main())
