#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERVER_DIR="$ROOT_DIR/servers/cpp20"
BUILD_DIR="$SERVER_DIR/build-release"
HOST="${HTTP_HOST:-127.0.0.1}"
PORT="${HTTP_PORT:-8080}"
BACKLOG="${HTTP_BACKLOG:-1024}"

command -v cmake >/dev/null || { echo "cmake is required" >&2; exit 1; }
command -v c++ >/dev/null || { echo "a C++ compiler is required" >&2; exit 1; }

cmake -S "$SERVER_DIR" -B "$BUILD_DIR" -DCMAKE_BUILD_TYPE=Release
cmake --build "$BUILD_DIR" --parallel

exec "$BUILD_DIR/cpp20-http-server" \
  --host "$HOST" \
  --port "$PORT" \
  --backlog "$BACKLOG"
