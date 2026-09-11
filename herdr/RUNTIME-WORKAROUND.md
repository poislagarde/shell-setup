# Temporary herdr runtime patch

Use `herdr 0.9.0-local.focus-1682cab` until an official stable release includes
[herdr PR #3850](https://github.com/herdrdev/herdr/pull/3850), commit
`1682cab3263b27b296f477552a4e79ab54923091`. Stock 0.9.0 omits plugin focus events
for client navigation, so Alt+1 followed by Alt+Backtick can skip the space you
came from. The keybindings and workspace-history plugin need no workaround.

The local build uses stable v0.9.0, commit
`b99002ac99b09e00b4ca692436cb15a6b0d676f1`, plus the exact upstream patch in
[`patches/client-focus-events.patch`](patches/client-focus-events.patch).
The patch includes the upstream regression test. Its runtime changes are confined
to `src/app/api.rs` and `src/server/headless/client_views.rs`; private protocol 22,
endpoint generation 1, and the handoff format are unchanged.

## Build and verify

Requires Git, Rust/Cargo (Rust 1.96.1 or newer), and Zig 0.15.2. On macOS,
`brew install rust zig@0.15` supplies the build tools. Run from the repo root:

```bash
ZIG="$(brew --prefix zig@0.15)/bin/zig" \
  herdr/build-focus-events-fix.sh "$HOME/.local/bin/herdr-focus-candidate"
```

The builder verifies the source commit, applies the checked-in patch, runs its
upstream regression test, and writes a new candidate binary. It does not replace
the installed binary or touch running sessions. It refuses an existing output
path; choose another path for a repeat build.

Run the keyboard-history test with the candidate and the pinned history plugin:

```bash
python3 herdr/tests/workspace-history-test.py \
  --herdr "$HOME/.local/bin/herdr-focus-candidate" \
  --plugin-dir /path/to/the/installed/last-workspace/plugin
```

Find that plugin root with
`herdr plugin list --plugin poislagarde.last-workspace --json`. Tests use private
sockets, config/state directories, and hidden PTYs; they do not operate the
user's session. They cover numbered and relative keyboard navigation, back and
forward, pane focus changes, closed spaces, and separate histories per session.

## Install and activate

Preserve the installed binary before replacing it. Use a same-directory rename
so the executable is never overwritten while running:

```bash
set -e
test ! -e "$HOME/.local/bin/herdr-before-focus-fix"
cp -p "$HOME/.local/bin/herdr" "$HOME/.local/bin/herdr-before-focus-fix"
mv "$HOME/.local/bin/herdr-focus-candidate" "$HOME/.local/bin/herdr"
herdr --version
```

Preserve any existing backup rather than overwriting it. Installing the binary
does not replace a running server.
Activate the intended session with its explicit socket from `herdr status server
--json`:

```bash
HERDR_SOCKET_PATH="/path/from/server-status/herdr.sock" herdr server live-handoff \
  --import-exe "$HOME/.local/bin/herdr" \
  --expected-protocol 22 --expected-version 0.9.0-local.focus-1682cab
```

Handoff is experimental: ordinary local clients exit, so rerun `herdr` afterward; pane
processes stay running on a successful handoff. In-flight API operations can be
interrupted. Check that there are no more than 64 pane PTYs before handoff.
Check workspace/pane IDs, focus, and original pane process IDs before and after.
Internal terminal runtime IDs are regenerated; compare public IDs and process
IDs instead. Read process IDs with `herdr pane process-info --pane <pane-id>`.
Never stop or kill the working server to activate this patch or recover from a
failed handoff. Initialize the history plugin once after a successful handoff:
`herdr plugin action invoke poislagarde.last-workspace.init`.

For rollback, restore the saved binary through a new candidate and atomic rename,
then use the same before/after checks:

```bash
cp -p "$HOME/.local/bin/herdr-before-focus-fix" "$HOME/.local/bin/herdr-rollback-candidate"
mv "$HOME/.local/bin/herdr-rollback-candidate" "$HOME/.local/bin/herdr"
HERDR_SOCKET_PATH="/path/from/server-status/herdr.sock" herdr server live-handoff \
  --import-exe "$HOME/.local/bin/herdr" \
  --expected-protocol 22 --expected-version 0.9.0
```

Keep the backup until the replacement has been verified.

## Removal condition

Do not run `herdr update` merely to replace this local build with stock 0.9.0.
Retire the workaround when **both** conditions hold:

1. An official stable release contains commit
   `1682cab3263b27b296f477552a4e79ab54923091` (verify tag ancestry or equivalent
   release source, rather than assuming a newer version contains it).
2. That release passes `herdr/tests/workspace-history-test.py`, including the
   real Alt+number → Alt+Backtick path, on private servers.

Then install the official release, activate it with the same pane-preservation
checks, and verify `herdr status` reports the intended client and server.
Remove this document, the build script, the patch, the bootstrap version guard
and its surrounding workaround prose/link, and their README/AGENTS references
in the same change. Keep the keyboard-history
test as a regression check. Remove local candidate/backup binaries only after
the official runtime is verified.
