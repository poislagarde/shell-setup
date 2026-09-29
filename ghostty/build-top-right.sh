#!/usr/bin/env bash
set -euo pipefail

repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
version=1.3.1

if [[ $(zig version) != 0.15.2 ]]; then
  echo 'Ghostty 1.3.1 requires Zig 0.15.2' >&2
  exit 1
fi

build_dir=${1:-$(mktemp -d "${TMPDIR:-/tmp}/ghostty-top-right.XXXXXX")}
if [[ -e "$build_dir/source" ]]; then
  echo "Source directory already exists: $build_dir/source" >&2
  exit 1
fi

mkdir -p "$build_dir"
git clone --depth 1 --branch "v$version" \
  https://github.com/ghostty-org/ghostty.git "$build_dir/source"
git -C "$build_dir/source" apply --check "$repo_dir/top-right-quick-terminal.patch"
git -C "$build_dir/source" apply "$repo_dir/top-right-quick-terminal.patch"
(
  cd "$build_dir/source"
  zig build -Doptimize=ReleaseFast -Dxcframework-target=native
)

app="$build_dir/source/zig-out/Ghostty.app"
codesign --verify --deep --strict "$app"
"$app/Contents/MacOS/ghostty" +validate-config --config-file="$repo_dir/config"
printf 'Built Ghostty app: %s\n' "$app"
