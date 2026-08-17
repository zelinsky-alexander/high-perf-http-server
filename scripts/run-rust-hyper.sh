#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERVER_DIR="$ROOT_DIR/servers/rust-hyper"
HOST="${HTTP_HOST:-127.0.0.1}"
PORT="${HTTP_PORT:-8080}"
BACKLOG="${HTTP_BACKLOG:-1024}"
WORKERS="${RUST_WORKERS:-1}"

command -v cargo >/dev/null || {
  echo "cargo is required; install Rust with rustup or your package manager" >&2
  exit 1
}
command -v rustc >/dev/null || {
  echo "rustc is required" >&2
  exit 1
}

if ! [[ "$WORKERS" =~ ^[1-9][0-9]*$ ]]; then
  echo "RUST_WORKERS must be a positive integer: $WORKERS" >&2
  exit 2
fi

cargo build \
  --release \
  --manifest-path "$SERVER_DIR/Cargo.toml"

exec "$SERVER_DIR/target/release/rust-hyper-server" \
  --host "$HOST" \
  --port "$PORT" \
  --backlog "$BACKLOG" \
  --workers "$WORKERS"
