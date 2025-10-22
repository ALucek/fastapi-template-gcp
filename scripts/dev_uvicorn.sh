#!/usr/bin/env bash
set -Eeuo pipefail

# Load .env if present via shared lib
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$SCRIPT_DIR/lib.sh"
load_env

PORT="${PORT:-8080}"

if ! command -v uvicorn >/dev/null 2>&1; then
  echo "uvicorn not found. Install with: pip install uvicorn[standard]" >&2
  exit 1
fi

exec uvicorn app.main:app --reload --host 0.0.0.0 --port "$PORT"


