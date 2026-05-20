#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WEB_PORT="${WEB_PORT:-8080}"

"$ROOT_DIR/scripts/export-web.sh"

cd "$ROOT_DIR"
WEB_PORT="$WEB_PORT" docker compose up -d --build

echo "Hollow Grid web preview: http://127.0.0.1:$WEB_PORT/"
echo "Server healthcheck: http://127.0.0.1:8787/healthz"
