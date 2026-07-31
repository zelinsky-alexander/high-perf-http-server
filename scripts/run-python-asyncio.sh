#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERVER="$ROOT_DIR/servers/python-asyncio/server.py"
HOST="${HTTP_HOST:-127.0.0.1}"
PORT="${HTTP_PORT:-8080}"
BACKLOG="${HTTP_BACKLOG:-1024}"
PYTHON="${PYTHON_BIN:-python3}"

command -v "$PYTHON" >/dev/null || {
  echo "$PYTHON is required" >&2
  exit 1
}

PYTHON_VERSION="$($PYTHON -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')"
PYTHON_MAJOR="${PYTHON_VERSION%%.*}"
PYTHON_MINOR="${PYTHON_VERSION##*.}"
if ((PYTHON_MAJOR < 3 || (PYTHON_MAJOR == 3 && PYTHON_MINOR < 12))); then
  echo "Python 3.12 or newer is required; detected: $($PYTHON --version 2>&1)" >&2
  exit 1
fi

exec "$PYTHON" -OO "$SERVER" \
  --host "$HOST" \
  --port "$PORT" \
  --backlog "$BACKLOG"
