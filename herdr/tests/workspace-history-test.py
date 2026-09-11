#!/usr/bin/env python3
"""Exercise the plugin against private, headless Herdr servers.

Run with --herdr CANDIDATE --plugin-dir INSTALLED_HISTORY_PLUGIN_ROOT.
Requires a built workspace-history plugin. No live session is read or modified.
"""

import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import struct
import subprocess
import sys
import tempfile
import threading
import time

if os.name == "posix":
    import fcntl
    import pty
    import termios


PLUGIN_ID = "poislagarde.last-workspace"
TIMEOUT = 10


def wait_for(description, predicate):
    deadline = time.monotonic() + TIMEOUT
    last_error = None
    while time.monotonic() < deadline:
        try:
            value = predicate()
            if value:
                return value
        except (OSError, ValueError, KeyError) as error:
            last_error = error
        time.sleep(0.05)
    raise AssertionError(f"Timed out waiting for {description}; last error: {last_error}")


class Server:
    def __init__(self, root, name, herdr, plugin_dir):
        self.root = root / name
        self.root.mkdir()
        self.herdr = herdr
        self.plugin_dir = plugin_dir
        self.socket = self.root / "runtime" / "api.sock"
        config_home = self.root / "config"
        config_path = config_home / "herdr" / "config.toml"
        config_path.parent.mkdir(parents=True)
        self.socket.parent.mkdir(mode=0o700)
        config_path.write_text(
            'onboarding = false\n'
            '[terminal]\ndefault_shell = "/bin/sh"\nshell_mode = "non_login"\n'
            '[update]\nversion_check = false\nmanifest_check = false\n'
            '[ui.toast]\ndelivery = "off"\n'
            '[ui.sound]\nenabled = false\n'
        )
        self.env = {
            key: value for key, value in os.environ.items()
            if not key.startswith("HERDR_")
            and key not in {"TMUX", "TMUX_PANE", "ENV", "BASH_ENV", "ZDOTDIR"}
        }
        self.env.update({
            "XDG_CONFIG_HOME": str(config_home),
            "XDG_STATE_HOME": str(root / "shared-state"),
            "XDG_DATA_HOME": str(self.root / "data"),
            "XDG_RUNTIME_DIR": str(self.socket.parent),
            "HERDR_CONFIG_PATH": str(config_path),
            "HERDR_SOCKET_PATH": str(self.socket),
            "SHELL": "/bin/sh",
        })
        session_key = hashlib.sha256(os.fsencode(self.socket)).hexdigest()
        self.state_path = (
            root / "shared-state" / "herdr" / "plugins" / PLUGIN_ID
            / "sessions" / session_key / "state.json"
        )
        self.log_path = self.root / "server.log"
        self.log_file = self.log_path.open("w")
        self.process = subprocess.Popen(
            [herdr, "server"], cwd=self.root, env=self.env,
            stdin=subprocess.DEVNULL, stdout=self.log_file,
            stderr=subprocess.STDOUT, start_new_session=True,
        )

    def run(self, *args):
        # Every command, including cleanup, targets this server's private socket.
        assert self.socket.is_relative_to(self.root)
        output = subprocess.run(
            [self.herdr, *args], cwd=self.root, env=self.env,
            stdin=subprocess.DEVNULL, capture_output=True, text=True,
            timeout=TIMEOUT,
        )
        if output.returncode:
            raise AssertionError(
                f"herdr {' '.join(args)} failed ({output.returncode})\n"
                f"{output.stdout}\n{output.stderr}"
            )
        data = json.loads(output.stdout)
        if data.get("error"):
            raise AssertionError(f"herdr {' '.join(args)}: {data['error']}")
        return data["result"]

    def ready(self):
        def check():
            if self.process.poll() is not None:
                raise AssertionError(f"Private server exited: {self.log_path.read_text()}")
            if not self.socket.exists():
                return False
            try:
                return self.run("workspace", "list")
            except AssertionError:
                return False
        wait_for("private server startup", check)

    def create(self, label, focus=False):
        result = self.run(
            "workspace", "create", "--label", label, "--cwd", str(self.root),
            "--focus" if focus else "--no-focus",
        )
        return result["workspace"]["workspace_id"]

    def current(self):
        return next(
            item["workspace_id"] for item in self.run("workspace", "list")["workspaces"]
            if item["focused"]
        )

    def state_current(self):
        state = json.loads(self.state_path.read_text())
        cursor = state.get("cursor")
        return state["entries"][cursor] if cursor is not None else None

    def logs(self):
        return self.run("plugin", "log", "list", "--plugin", PLUGIN_ID, "--limit", "200")["logs"]

    def settled(self):
        def complete():
            logs = self.logs()
            failures = [log for log in logs if log["status"] == "failed"]
            if failures:
                raise AssertionError(f"Plugin command failed: {json.dumps(failures, indent=2)}")
            return not any(log["status"] == "running" for log in logs)
        wait_for("plugin event completion", complete)

    def expect(self, workspace):
        wait_for(
            f"workspace and recorded focus {workspace}",
            lambda: self.current() == workspace and self.state_current() == workspace,
        )
        self.settled()

    def focus(self, workspace):
        self.run("workspace", "focus", workspace)
        self.expect(workspace)

    def action(self, action, workspace):
        invoked = self.run("plugin", "action", "invoke", action, "--plugin", PLUGIN_ID)
        log_id = invoked["log"]["log_id"]

        def completed():
            log = next((log for log in self.logs() if log["log_id"] == log_id), None)
            if log and log["status"] == "failed":
                raise AssertionError(f"Plugin action failed: {json.dumps(log, indent=2)}")
            return log and log["status"] == "succeeded"

        wait_for(f"{action} action completion", completed)
        self.expect(workspace)

    def link(self, workspace):
        self.run("plugin", "link", str(self.plugin_dir), "--enabled")
        self.action("init", workspace)

    def close_workspace(self, workspace):
        self.run("workspace", "close", workspace)
        wait_for(
            f"closed destination {workspace} removed from history",
            lambda: workspace not in json.loads(self.state_path.read_text())["entries"],
        )
        self.settled()

    def diagnostic(self):
        print(f"Private server diagnostics ({self.socket}):", file=sys.stderr)
        print(self.log_path.read_text()[-12000:], file=sys.stderr)
        if self.state_path.exists():
            print(self.state_path.read_text(), file=sys.stderr)
        if self.process.poll() is None and self.socket.exists():
            try:
                print(json.dumps(self.logs(), indent=2)[-16000:], file=sys.stderr)
            except Exception as error:
                print(f"Could not read private plugin logs: {error}", file=sys.stderr)

    def stop(self):
        if self.process.poll() is None:
            try:
                # Stop only the process started above, through its private API.
                subprocess.run(
                    [self.herdr, "server", "stop"], cwd=self.root, env=self.env,
                    stdin=subprocess.DEVNULL, capture_output=True, timeout=TIMEOUT,
                )
                self.process.wait(timeout=TIMEOUT)
            except (OSError, subprocess.TimeoutExpired):
                self.process.terminate()
                try:
                    self.process.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    self.process.kill()
                    self.process.wait(timeout=3)
        self.log_file.close()


class HeadlessClient:
    """Drive real terminal keys in a private PTY, without opening any window."""

    def __init__(self, server):
        assert server.socket.is_relative_to(server.root)
        self.master, slave = pty.openpty()
        fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 40, 120, 0, 0))

        def establish_terminal():
            os.setsid()
            fcntl.ioctl(0, termios.TIOCSCTTY, 0)

        self.output = bytearray()
        self.process = subprocess.Popen(
            [server.herdr, "client"], cwd=server.root,
            env=dict(server.env, TERM="xterm-256color"),
            stdin=slave, stdout=slave, stderr=slave,
            preexec_fn=establish_terminal,
        )
        os.close(slave)
        self.reader = threading.Thread(target=self.drain, daemon=True)
        self.reader.start()
        try:
            wait_for("private client initial frame", self.ready)
        except Exception:
            self.stop()
            raise

    def drain(self):
        while True:
            try:
                data = os.read(self.master, 65536)
                if not data:
                    return
                self.output.extend(data)
            except OSError:
                return

    def ready(self):
        if self.process.poll() is not None:
            raise AssertionError(f"Private client exited: {bytes(self.output)!r}")
        return b"\x1b[?2026l" in self.output

    def key(self, encoded):
        if self.process.poll() is not None:
            raise AssertionError(f"Private client exited: {bytes(self.output)!r}")
        os.write(self.master, encoded)

    def stop(self):
        if self.process.poll() is None:
            self.process.terminate()
            try:
                self.process.wait(timeout=3)
            except subprocess.TimeoutExpired:
                self.process.kill()
                self.process.wait(timeout=3)
        os.close(self.master)
        self.reader.join(timeout=3)


def keyboard_smoke(root, herdr, plugin_dir, servers):
    server = Server(root, "keys", herdr, plugin_dir)
    servers.append(server)
    server.ready()
    config = Path(server.env["HERDR_CONFIG_PATH"])
    bindings = [
        ("alt+backtick", "back"),
        ("alt+~", "forward"),
    ]
    config.write_text(config.read_text() +
        '\n[keys]\n'
        'switch_workspace = ["prefix+shift+1..9", "alt+1..9"]\n'
        'next_workspace = ["prefix+)", "alt+]"]\n'
        'previous_workspace = ["prefix+(", "alt+["]\n' + "".join(
        '\n[[keys.command]]\n'
        f'key = "{key}"\ntype = "plugin_action"\n'
        f'command = "{PLUGIN_ID}.{action}"\n'
        for key, action in bindings
    ))
    server.run("server", "reload-config")
    a = server.create("A")
    b = server.create("B", focus=True)
    c = server.create("C")
    server.link(b)
    client = None
    try:
        client = HeadlessClient(server)

        def press(encoded, workspace):
            client.key(encoded)
            server.expect(workspace)

        # ESC-prefixed digits and punctuation follow the actual Alt shortcut path.
        press(b"\x1b3", c)
        press(b"\x1b1", a)
        press(b"\x1b`", c)
        press(b"\x1b`", b)
        press(b"\x1b~", c)
        press(b"\x1b~", a)
        print("PASS: Alt+digits and Alt+backtick preserve every workspace visit")

        # CSI-u expresses Shift+digit and ambiguous Alt+[ / Alt+] unambiguously.
        press(b"\x02\x1b[50;2u", b)
        press(b"\x1b`", a)
        press(b"\x1b[93;3u", b)
        press(b"\x1b`", a)
        press(b"\x1b[91;3u", c)
        press(b"\x1b`", a)
        press(b"\x02)", b)
        press(b"\x1b`", a)
        press(b"\x02(", c)
        press(b"\x1b`", a)
        print("PASS: prefix number and relative workspace shortcuts preserve history")
    finally:
        if client is not None:
            client.stop()


def smoke(root, herdr, plugin_dir, servers):
    first = Server(root, "one", herdr, plugin_dir)
    servers.append(first)
    first.ready()
    a = first.create("A", focus=True)
    b = first.create("B")
    c = first.create("C")
    d = first.create("D")
    first.link(a)
    first.focus(b)
    first.focus(c)

    panes = first.run("pane", "list")["panes"]
    pane = next(item["pane_id"] for item in panes if item["workspace_id"] == c)
    first.run("pane", "split", "--pane", pane, "--direction", "right", "--focus")
    split_pane = next(
        item["pane_id"] for item in first.run("pane", "list")["panes"]
        if item["workspace_id"] == c and item["pane_id"] != pane
    )
    for _ in range(3):
        first.run("pane", "focus", "--pane", split_pane, "--direction", "left")
        first.run("pane", "focus", "--pane", pane, "--direction", "right")
    first.expect(c)
    first.action("back", b)
    first.action("back", a)
    first.action("forward", b)
    first.focus(c)
    first.action("forward", c)
    print("PASS: pane focus churn preserves workspace-only back/forward history")

    # D makes truncation observable even when C was already a forward entry.
    first.focus(d)
    first.action("back", c)
    first.action("back", b)
    first.focus(c)
    first.action("forward", c)
    print("PASS: external focus discards the old forward branch")

    first.close_workspace(b)
    first.action("back", a)
    first.action("forward", c)
    first.close_workspace(a)
    first.action("back", c)
    first.focus(d)
    first.action("back", c)
    first.close_workspace(d)
    first.action("forward", c)
    print("PASS: closed destinations are skipped in both directions")

    e = first.create("E")
    first.focus(e)
    first.action("back", c)
    second = Server(root, "two", herdr, plugin_dir)
    servers.append(second)
    second.ready()
    x = second.create("X", focus=True)
    y = second.create("Y")
    z = second.create("Z")
    second.link(x)
    second.focus(y)
    second.focus(z)
    second.action("back", y)
    second.action("back", x)
    second.close_workspace(x)
    second.expect(y)
    second.action("forward", z)
    print("PASS: closing the oldest current workspace preserves its forward branch")
    first.action("forward", e)
    if second.current() != z:
        raise AssertionError("Navigation in the first session changed the second session")
    print("PASS: separate sockets preserve independent histories with shared plugin state")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--herdr", default=shutil.which("herdr"))
    parser.add_argument("--plugin-dir", type=Path, required=True)
    args = parser.parse_args()
    if not args.herdr:
        print("SKIP: herdr is not installed")
        return 0
    herdr = str(Path(args.herdr).resolve())
    plugin_dir = args.plugin_dir.resolve()
    binary = plugin_dir / "target" / "release" / "herdr-last-workspace"
    if not binary.is_file():
        parser.error("Build the plugin first with cargo build --release")
    if os.name != "posix":
        print("SKIP: private Unix-socket smoke test requires macOS or Linux")
        return 0
    servers = []
    # Keep socket names below macOS's Unix socket path limit.
    with tempfile.TemporaryDirectory(prefix="herdr-smoke-", dir="/tmp") as directory:
        try:
            smoke(Path(directory).resolve(), herdr, plugin_dir, servers)
            keyboard_smoke(Path(directory).resolve(), herdr, plugin_dir, servers)
        except Exception:
            for server in servers:
                server.diagnostic()
            raise
        finally:
            for server in reversed(servers):
                server.stop()
    return 0


if __name__ == "__main__":
    sys.exit(main())
