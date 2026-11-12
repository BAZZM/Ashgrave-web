#!/usr/bin/env bash
# Download Godot 4.4.1 (linux x86_64, editor binary used headless) into DIR.
#   tools/get_godot.sh /home/claude/godot
# Prints the binary path. Safe to re-run.
set -euo pipefail
dir="${1:?usage: get_godot.sh DIR}"
bin="$dir/Godot_v4.4.1-stable_linux.x86_64"
if [ ! -x "$bin" ]; then
  mkdir -p "$dir"
  tmp="$(mktemp -d)"
  curl -fsSL -o "$tmp/g.zip" https://github.com/godotengine/godot/releases/download/4.4.1-stable/Godot_v4.4.1-stable_linux.x86_64.zip
  unzip -q -o "$tmp/g.zip" -d "$dir"
  rm -rf "$tmp"
  chmod +x "$bin"
fi
"$bin" --version >&2
echo "$bin"
