#!/usr/bin/env python3
"""PreToolUse hook (Claude Code and Codex): refuse `git worktree add` into a
directory the OS empties on its own, such as /tmp or $TMPDIR."""

import json
import os
import re
import shlex
import sys

# macOS clears /private/tmp and the per-user /private/var/folders trees; on
# Linux, /tmp is usually a tmpfs that empties on reboot.
MKTEMP_ROOT = os.path.realpath(os.environ.get("TMPDIR") or "/tmp")
TEMP_ROOTS = sorted({os.path.realpath("/tmp"), os.path.realpath("/var/folders"), MKTEMP_ROOT})
OPERATORS = {"&&", "||", ";", ";;", "|", "&", "(", ")"}
VALUE_OPTIONS = {"-b", "-B", "--reason"}


def expand(word, env):
    word = re.sub(r"\$\{(\w+)\}|\$(\w+)", lambda m: env.get(m.group(1) or m.group(2), m.group(0)), word)
    return os.path.expanduser(word)


def worktree_targets(command, cwd):
    """Yield the resolved path of each `worktree add`, or None when it cannot be resolved."""
    lexer = shlex.shlex(command, posix=True, punctuation_chars=True)
    lexer.whitespace_split = True
    tokens = list(lexer)
    env, base, git_dir = dict(os.environ), cwd, None
    for index, token in enumerate(tokens):
        following = tokens[index + 1] if index + 1 < len(tokens) else None
        if token in OPERATORS:
            git_dir = None
        elif re.fullmatch(r"[A-Za-z_]\w*=.*", token):
            name, value = token.split("=", 1)
            env[name] = expand(value, env)
        elif token == "cd" and following and following not in OPERATORS:
            base = os.path.join(base, expand(following, env))
        elif token == "-C" and following and following not in OPERATORS:
            git_dir = os.path.join(base, expand(following, env))
        elif token == "worktree" and following == "add":
            path = None
            rest = iter(tokens[index + 2:])
            for argument in rest:
                if argument in OPERATORS:
                    break
                if argument == "--":
                    path = next(rest, None)
                    break
                if argument in VALUE_OPTIONS:
                    next(rest, None)
                elif not argument.startswith("-"):
                    path = argument
                    break
            if path is None:
                continue
            path = expand(path, env)
            if "$" in path:
                yield None
            else:
                yield os.path.realpath(os.path.join(git_dir or base, path))


def temp_root(path):
    return next((root for root in TEMP_ROOTS if os.path.commonpath([path, root]) == root), None)


def main():
    try:
        payload = json.load(sys.stdin)
        command = payload["tool_input"]["command"]
        if "worktree" not in command:
            return 0
        cwd = payload.get("cwd") or os.getcwd()
        for target in worktree_targets(command, cwd):
            # An unexpandable path counts as temporary only when mktemp produced it.
            root = temp_root(target) if target else (MKTEMP_ROOT if "mktemp" in command else None)
            if root:
                break
        else:
            return 0
    except (ValueError, KeyError, TypeError):
        return 0  # not a shell command this hook can read: let it run
    where = target or "a mktemp directory"
    reason = (f"Refusing `git worktree add` into {where}: {root} is emptied automatically by the OS, "
              "so the checkout would disappear while it is still in use. Create the worktree in a "
              "persistent directory instead, for example ~/.herdr/worktrees/<repo>/<name>. "
              "Keep temporary directories for other scratch files.")
    print(json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse",
                                             "permissionDecision": "deny",
                                             "permissionDecisionReason": reason}}))
    return 0


if __name__ == "__main__":
    sys.exit(main())
