#!/usr/bin/env bash
set -Eeuo pipefail

PORT="${PORT:-8080}"

if ! command -v uvicorn >/dev/null 2>&1; then
  echo "uvicorn not found. Install with: pip install uvicorn[standard]" >&2
  exit 1
fi

exec uvicorn app.main:app --reload --host 0.0.0.0 --port "$PORT"


