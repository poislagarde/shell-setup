#!/usr/bin/env python3
"""Feed the worktree guard PreToolUse payloads and check which commands it denies."""

import json
import os
from pathlib import Path
import subprocess
import sys
import unittest


GUARD = Path(__file__).resolve().parents[1] / "worktree-guard.py"


def decide(command, cwd="/path/to/repo"):
    payload = {"hook_event_name": "PreToolUse", "tool_name": "Bash", "cwd": cwd,
               "tool_input": {"command": command}}
    result = subprocess.run([sys.executable, str(GUARD)], input=json.dumps(payload),
                            capture_output=True, text=True, check=True)
    if not result.stdout:
        return "allow"
    output = json.loads(result.stdout)["hookSpecificOutput"]
    assert output["permissionDecisionReason"]
    return output["permissionDecision"]


class WorktreeGuard(unittest.TestCase):
    def test_denies_worktrees_under_temporary_directories(self):
        for command in (
            "git worktree add /tmp/wt main",
            "git -C /path/to/repo worktree add -b feature /private/tmp/wt main",
            "S=/private/tmp/agent/scratchpad; cd /path/to/repo && git worktree add -q --detach $S/wt origin/main",
            'git worktree add "$TMPDIR/wt"',
            'git worktree add "$(mktemp -d)/wt"',
            "cd /tmp && git worktree add wt",
            "git -C /tmp/repo worktree add ../wt",
            "git worktree add --reason why --lock -- /tmp/wt",
        ):
            with self.subTest(command=command):
                self.assertEqual(decide(command), "deny")

    def test_allows_persistent_worktrees_and_unrelated_temp_use(self):
        for command in (
            "git worktree add ~/.herdr/worktrees/repo/feature main > /tmp/worktree.log",
            "git worktree add -b feature ../feature main && cp /tmp/notes ../feature/",
            "git worktree add $UNSET_DIRECTORY/feature",
            'echo "git worktree add /tmp/wt"',
            "git worktree list && ls /tmp",
            "git worktree remove /tmp/wt",
        ):
            with self.subTest(command=command):
                self.assertEqual(decide(command), "allow")

    def test_relative_path_resolves_against_hook_cwd(self):
        self.assertEqual(decide("git worktree add wt", cwd="/tmp/repo"), "deny")
        self.assertEqual(decide("git worktree add wt", cwd=os.path.expanduser("~")), "allow")

    def test_ignores_payloads_without_a_shell_command(self):
        result = subprocess.run([sys.executable, str(GUARD)], input='{"tool_name": "Edit", "tool_input": {}}',
                                capture_output=True, text=True, check=True)
        self.assertEqual(result.stdout, "")


if __name__ == "__main__":
    unittest.main()
