#!/usr/bin/env bash
set -euo pipefail

if [[ $# != 1 ]]; then
  echo "Usage: $0 /path/to/Ghostty.app" >&2
  exit 2
fi

source_app=$1
target=/Applications/Ghostty.app
backup_dir="$HOME/.local/share/shell-setup/ghostty-backups"

if [[ ! -d "$source_app" || ! -x "$source_app/Contents/MacOS/ghostty" ]]; then
  echo "Ghostty app not found: $source_app" >&2
  exit 1
fi
if pgrep -x ghostty >/dev/null; then
  echo 'Quit Ghostty completely before installing the custom app.' >&2
  exit 1
fi
if [[ ! -d "$target" || ! -w /Applications ]]; then
  echo "Cannot replace $target" >&2
  exit 1
fi

codesign --verify --deep --strict "$source_app"
version=$("$source_app/Contents/MacOS/ghostty" --version | sed -n '1p')
if [[ "$version" != 'Ghostty 1.3.1' ]]; then
  echo "Expected Ghostty 1.3.1, found: $version" >&2
  exit 1
fi

mkdir -p "$backup_dir"
backup="$backup_dir/Ghostty-$(date +%Y%m%d%H%M%S)-$$.app"
staging=$(mktemp -d /Applications/.ghostty-install.XXXXXX)
trap 'rm -rf "$staging"' EXIT
ditto "$source_app" "$staging/Ghostty.app"
codesign --verify --deep --strict "$staging/Ghostty.app"

mv "$target" "$backup"
if ! mv "$staging/Ghostty.app" "$target"; then
  mv "$backup" "$target"
  echo 'Install failed; restored the original Ghostty app.' >&2
  exit 1
fi

printf 'Installed: %s\nBackup: %s\n' "$target" "$backup"
