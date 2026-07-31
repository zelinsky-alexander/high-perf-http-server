#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESULT_DIR="$ROOT_DIR/results/java-nio/$(date -u +%Y%m%dT%H%M%SZ)"
URL="${BENCHMARK_URL:-http://127.0.0.1:8080/plaintext}"
THREADS="${WRK_THREADS:-2}"
DURATION="${WRK_DURATION:-30s}"

command -v wrk >/dev/null || {
  echo "wrk is required: sudo apt install wrk" >&2
  exit 1
}
command -v curl >/dev/null || {
  echo "curl is required" >&2
  exit 1
}

mkdir -p "$RESULT_DIR"

curl --fail --silent --show-error "$URL" >/dev/null

{
  echo "timestamp_utc=$(date -u --iso-8601=seconds)"
  echo "url=$URL"
  echo "wrk_threads=$THREADS"
  echo "duration=$DURATION"
  echo "kernel=$(uname -srmo)"
  echo "java=$(java -version 2>&1 | head -n1)"
  echo "maven=$(mvn -version 2>&1 | head -n1)"
  lscpu
} > "$RESULT_DIR/environment.txt"

echo "Warm-up..."
wrk -t"$THREADS" -c32 -d15s "$URL" > "$RESULT_DIR/warmup.txt"

for connections in 1 8 32 128 512; do
  echo "Benchmarking concurrency=$connections"
  wrk \
    -t"$THREADS" \
    -c"$connections" \
    -d"$DURATION" \
    --latency \
    "$URL" \
    | tee "$RESULT_DIR/connections-${connections}.txt"
  sleep 5
done

echo "Results written to: $RESULT_DIR"
