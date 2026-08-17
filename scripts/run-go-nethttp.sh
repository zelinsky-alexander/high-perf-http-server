#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERVER_DIR="$ROOT_DIR/servers/go-nethttp"
HOST="${HTTP_HOST:-127.0.0.1}"
PORT="${HTTP_PORT:-8080}"
GO_MAX_PROCS="${GO_MAX_PROCS:-}"

command -v go >/dev/null || {
  echo "go is required" >&2
  exit 1
}

GO_VERSION="$(go version | awk '{print $3}' | sed 's/^go//')"
GO_MAJOR="${GO_VERSION%%.*}"
GO_REST="${GO_VERSION#*.}"
GO_MINOR="${GO_REST%%.*}"

if [[ -z "$GO_MAJOR" || -z "$GO_MINOR" ]] || ((GO_MAJOR < 1 || (GO_MAJOR == 1 && GO_MINOR < 22))); then
  echo "Go 1.22 or newer is required; detected: $(go version)" >&2
  exit 1
fi

mkdir -p "$SERVER_DIR/bin"
(
  cd "$SERVER_DIR"
  go build \
    -trimpath \
    -o bin/go-nethttp \
    .
)

if [[ -n "$GO_MAX_PROCS" ]]; then
  export GOMAXPROCS="$GO_MAX_PROCS"
fi

exec "$SERVER_DIR/bin/go-nethttp" \
  --host "$HOST" \
  --port "$PORT"
