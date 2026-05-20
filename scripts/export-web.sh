#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="$ROOT_DIR/dist/web"

rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"

godot --headless --path "$ROOT_DIR/game" --export-release "Web" "$OUT_DIR/index.html"

echo "Exported Godot Web build to $OUT_DIR"
