#!/usr/bin/env python3
"""Exercise hook wiring using private Git repositories and a recording plugin."""

import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


ADAPTER = Path(__file__).resolve().parents[1] / "worktree-register.py"
PLUGIN_ID = "poislagarde.worktree-cleanup"


class RegistrationHooks(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="herdr-registration-test-")
        self.addCleanup(self.temporary.cleanup)
        self.base = Path(self.temporary.name).resolve()
        self.repo = self.base / "primary repo"
        self.repo.mkdir()
        self.calls = self.base / "calls.jsonl"
        self.env = os.environ.copy()
        for key in list(self.env):
            if key.startswith("GIT_") or key.startswith("HERDR_"):
                del self.env[key]
        self.env.update({
            "XDG_CONFIG_HOME": str(self.base / "config"),
            "XDG_STATE_HOME": str(self.base / "state"),
            "HERDR_SOCKET_PATH": str(self.base / "origin.sock"),
            "HERDR_PANE_ID": "origin-pane",
            "FIXTURE_CALLS": str(self.calls),
        })
        self.run_command(["git", "init", "-q", str(self.repo)])
        self.git("config", "user.name", "Fixture")
        self.git("config", "user.email", "fixture@example.invalid")
        (self.repo / "tracked").write_text("fixture\n")
        self.git("add", ".")
        self.git("commit", "-qm", "fixture")
        self.plugin = self.base / "plugin checkout"
        self.plugin.mkdir()
        (self.plugin / "herdr-plugin.toml").write_text(f'id = "{PLUGIN_ID}"\n')
        (self.plugin / "plugin.py").write_text(
            "import json, os, sys\n"
            "from pathlib import Path\n"
            "with Path(os.environ['FIXTURE_CALLS']).open('a') as output:\n"
            " output.write(json.dumps({'args': sys.argv[1:], 'cwd': os.getcwd(), "
            "'socket': os.environ.get('HERDR_SOCKET_PATH'), 'pane': os.environ.get('HERDR_PANE_ID'), "
            "'state': os.environ.get('HERDR_PLUGIN_STATE_DIR'), "
            "'config': os.environ.get('HERDR_PLUGIN_CONFIG_DIR')}) + '\\n')\n"
            "print(os.environ.get('FIXTURE_RESULT', '{\"outcome\":\"registered\"}'))\n"
        )
        self.entry = {
            "plugin_id": PLUGIN_ID, "enabled": True,
            "plugin_root": str(self.plugin),
            "manifest_path": str(self.plugin / "herdr-plugin.toml"),
        }
        self.registry = self.base / "config" / "herdr" / "plugins.json"
        self.registry.parent.mkdir(parents=True)
        self.registry.write_text(json.dumps([self.entry]))
        self.state = self.base / "state" / "herdr" / "plugins" / PLUGIN_ID / "worktrees.json"

    def run_command(self, args, cwd=None, expected=0, env=None, input=None):
        result = subprocess.run(args, cwd=cwd or self.base, env=env or self.env,
                                text=True, input=input, capture_output=True, check=False)
        self.assertEqual(result.returncode, expected, result.stdout + result.stderr)
        return result

    def git(self, *args, **options):
        return self.run_command(["git", "-C", str(self.repo), *args], **options)

    def install(self, expected=0):
        return self.run_command([sys.executable, str(ADAPTER), "install", str(self.repo),
                                 "--adapter", str(ADAPTER)], expected=expected)

    def recorded(self):
        return [json.loads(line) for line in self.calls.read_text().splitlines()] if self.calls.exists() else []

    def add_worktree(self, name="linked checkout"):
        checkout = self.base / name
        self.git("worktree", "add", "-q", "--detach", str(checkout))
        return checkout

    def test_git_creation_registers_exact_target_and_skips_normal_checkout(self):
        self.install()
        checkout = self.add_worktree()
        self.assertEqual(self.recorded()[0]["args"], ["register", "--checkout", str(checkout), "--defer-on-unavailable"])
        self.assertEqual(self.recorded()[0]["socket"], self.env["HERDR_SOCKET_PATH"])
        self.assertEqual(self.recorded()[0]["pane"], "origin-pane")
        self.run_command(["git", "-C", str(checkout), "checkout", "-q", "--detach", "HEAD"])
        self.run_command([sys.executable, str(ADAPTER), "post-checkout", "0" * 40, "a" * 40, "1"], cwd=self.repo)
        self.assertEqual(len(self.recorded()), 1)

    def test_existing_hook_keeps_arguments_stdin_and_exit_status(self):
        hook = self.repo / ".git" / "hooks" / "post-checkout"
        original = '#!/bin/sh\nprintf "%s\\n" "$@" > "$FIXTURE_ARGS"\ncat > "$FIXTURE_INPUT"\nexit 7\n'
        hook.write_text(original)
        hook.chmod(0o755)
        self.env["FIXTURE_ARGS"] = str(self.base / "args")
        self.env["FIXTURE_INPUT"] = str(self.base / "input")
        self.install()
        self.install()
        self.run_command([str(hook), "old", "new", "1"], cwd=self.repo, expected=7, input="original input")
        self.assertEqual((self.base / "args").read_text(), "old\nnew\n1\n")
        self.assertEqual((self.base / "input").read_text(), "original input")
        self.assertEqual(hook.with_name("post-checkout.shell-setup-original").read_text(), original)

    def test_existing_relative_symlink_and_nonexecutable_hook_are_preserved(self):
        directory = self.repo / ".git" / "hooks"
        (directory / "original-script").write_text("#!/bin/sh\nexit 9\n")
        (directory / "original-script").chmod(0o755)
        (directory / "post-checkout").symlink_to("original-script")
        self.install()
        backup = directory / "post-checkout.shell-setup-original"
        self.assertTrue(backup.is_symlink())
        self.assertEqual(os.readlink(backup), "original-script")
        self.run_command([str(directory / "post-checkout"), "old", "new", "1"], cwd=self.repo, expected=9)
        (directory / "original-script").chmod(0o644)
        self.run_command([str(directory / "post-checkout"), "old", "new", "1"], cwd=self.repo)

    def test_absolute_hooks_path_and_other_hooks_remain_unchanged(self):
        directory = self.base / "custom hooks"
        directory.mkdir()
        (directory / "pre-commit").write_text("existing\n")
        self.git("config", "core.hooksPath", str(directory))
        before = (self.repo / ".git" / "config").read_bytes()
        self.install()
        self.add_worktree()
        self.assertEqual(len(self.recorded()), 1)
        self.assertEqual((directory / "pre-commit").read_text(), "existing\n")
        self.assertEqual((self.repo / ".git" / "config").read_bytes(), before)

    def test_relative_hooks_path_and_backup_collision_refuse_without_replacement(self):
        self.git("config", "core.hooksPath", ".custom-hooks")
        self.assertIn("Relative core.hooksPath", self.install(expected=1).stderr)
        self.assertFalse((self.repo / ".custom-hooks").exists())
        self.git("config", "--unset", "core.hooksPath")
        directory = self.repo / ".git" / "hooks"
        (directory / "post-checkout").write_text("existing\n")
        (directory / "post-checkout.shell-setup-original").write_text("backup\n")
        self.install(expected=1)
        self.assertEqual((directory / "post-checkout").read_text(), "existing\n")
        self.assertEqual((directory / "post-checkout.shell-setup-original").read_text(), "backup\n")

    def test_name_sensitive_original_is_not_renamed(self):
        hook = self.repo / ".git" / "hooks" / "post-checkout"
        source = '#!/bin/sh\n[ "$(basename "$0")" = post-checkout ] || exit 42\n'
        hook.write_text(source)
        hook.chmod(0o755)
        self.run_command([str(hook)])
        self.assertIn("own filename", self.install(expected=1).stderr)
        self.assertEqual(hook.read_text(), source)
        self.assertFalse(hook.with_name("post-checkout.shell-setup-original").exists())

    def test_missing_context_does_not_register(self):
        self.install()
        self.env.pop("HERDR_PANE_ID")
        self.add_worktree()
        self.assertFalse(self.recorded())

    def test_explicit_registration_resolves_a_no_checkout_target(self):
        checkout = self.base / "deferred checkout"
        self.git("worktree", "add", "-q", "--detach", "--no-checkout", str(checkout))
        result = self.run_command([sys.executable, str(ADAPTER), "register", checkout.name])
        self.assertEqual(result.stdout, "")
        self.assertEqual(self.recorded()[0]["args"], ["register", "--checkout", str(checkout), "--defer-on-unavailable"])

    def test_drain_empty_fast_path_and_pending_preserves_stored_owner_handling(self):
        self.registry.unlink()
        self.env["HERDR_BIN_PATH"] = str(self.base / "must-not-run")
        self.run_command([sys.executable, str(ADAPTER), "drain"])
        self.state.parent.mkdir(parents=True)
        self.state.write_text('{"schema_version":2,"pending":[]}')
        self.run_command([sys.executable, str(ADAPTER), "drain"])
        self.assertFalse(self.recorded())
        self.registry.write_text(json.dumps([self.entry]))
        self.state.write_text('{"schema_version":2,"pending":[{"fixture":true}]}')
        self.env.pop("HERDR_SOCKET_PATH")
        self.env.pop("HERDR_PANE_ID")
        self.env["HERDR_PLUGIN_STATE_DIR"] = "/wrong/inherited/plugin/state"
        self.env["HERDR_PLUGIN_CONFIG_DIR"] = "/wrong/inherited/plugin/config"
        result = self.run_command([sys.executable, str(ADAPTER), "drain"])
        self.assertEqual(result.stdout, "")
        self.assertEqual(self.recorded()[0]["args"], ["drain"])
        self.assertEqual(self.recorded()[0]["state"], str(self.state.parent))
        self.assertEqual(self.recorded()[0]["config"], str(self.registry.parent / "plugins" / "config" / PLUGIN_ID))

    def test_disabled_or_mismatched_plugin_is_not_executed(self):
        self.install()
        self.entry["enabled"] = False
        self.registry.write_text(json.dumps([self.entry]))
        self.add_worktree("disabled")
        self.entry["enabled"] = True
        self.registry.write_text(json.dumps([self.entry]))
        (self.plugin / "herdr-plugin.toml").write_text('id = "different.plugin"\n')
        self.add_worktree("mismatched")
        self.assertFalse(self.recorded())

    def test_exit_zero_registration_failure_is_reported_without_changing_hook_status(self):
        self.install()
        self.env["FIXTURE_RESULT"] = json.dumps({"outcome": "kept", "reason": "permission denied writing plugin state"})
        checkout = self.base / "state blocked"
        result = self.git("worktree", "add", "-q", "--detach", str(checkout))
        self.assertIn("permission denied writing plugin state", result.stderr)
        self.assertEqual(result.stdout, "")
        self.assertTrue(checkout.is_dir())
        self.run_command([sys.executable, str(ADAPTER), "register", str(checkout)], expected=1)


if __name__ == "__main__":
    unittest.main()
