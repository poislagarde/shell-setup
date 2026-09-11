#!/usr/bin/env bash
set -euo pipefail

# Build the temporary runtime described in RUNTIME-WORKAROUND.md.
if [[ $# != 1 ]]; then
  echo "usage: $0 OUTPUT_BINARY" >&2
  exit 2
fi

herdr_source_commit=b99002ac99b09e00b4ca692436cb15a6b0d676f1
herdr_patch_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
herdr_zig=${ZIG:-zig}
if [[ "$("$herdr_zig" version)" != 0.15.2 ]]; then
  echo "This build requires Zig 0.15.2; set ZIG to its executable." >&2
  exit 1
fi
command -v cargo >/dev/null
mkdir -p -- "$(dirname -- "$1")"
herdr_output_dir=$(cd -- "$(dirname -- "$1")" && pwd -P)
herdr_output="$herdr_output_dir/$(basename -- "$1")"
if [[ -e "$herdr_output" || -L "$herdr_output" ]]; then
  echo "Refusing to overwrite $herdr_output; build to a new candidate path." >&2
  exit 1
fi

herdr_build_dir=$(mktemp -d "${TMPDIR:-/tmp}/herdr-focus-build.XXXXXX")
herdr_build_dir=$(cd -- "$herdr_build_dir" && pwd -P)
trap 'rm -rf -- "$herdr_build_dir"' EXIT
git clone --depth 1 --branch v0.9.0 https://github.com/herdrdev/herdr.git "$herdr_build_dir/source"
cd -- "$herdr_build_dir/source"
[[ "$(git rev-parse HEAD)" == "$herdr_source_commit" ]]
git apply --check "$herdr_patch_dir/patches/client-focus-events.patch"
git apply "$herdr_patch_dir/patches/client-focus-events.patch"

# Keep all Zig/Cargo paths canonical on macOS.
export CARGO_HOME="$herdr_build_dir/cargo"
export CARGO_TARGET_DIR="$herdr_build_dir/target"
export ZIG_GLOBAL_CACHE_DIR="$herdr_build_dir/zig-global-cache"
export ZIG_LOCAL_CACHE_DIR="$herdr_build_dir/source/vendor/libghostty-vt/.zig-cache"
export ZIG="$herdr_zig"
export HERDR_BUILD_CHANNEL=local
export HERDR_BUILD_ID=focus-1682cab
export HERDR_BUILD_COMMIT="$herdr_source_commit"
cargo build --release --locked
cargo test --release --locked --bin herdr \
  client_local_navigation_emits_pane_focused_only_when_that_client_moves
[[ "$("$CARGO_TARGET_DIR/release/herdr" --version)" == "herdr 0.9.0-local.focus-1682cab" ]]
install -m 755 "$CARGO_TARGET_DIR/release/herdr" "$herdr_output"
printf 'Built %s\n' "$herdr_output"
