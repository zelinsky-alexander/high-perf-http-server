#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESULT_DIR="$ROOT_DIR/results/cpp20/$(date -u +%Y%m%dT%H%M%SZ)"
URL="${BENCHMARK_URL:-http://127.0.0.1:8080/plaintext}"
THREADS="${WRK_THREADS:-2}"
DURATION="${WRK_DURATION:-30s}"
CONNECTIONS=""
DEFAULT_SWEEP=(2 8 32 128 512)

usage() {
  echo "Usage: benchmark-cpp20.sh [-c connections] [-t threads] [-d duration] [url]"
}

while (($#)); do
  case "$1" in
    -c|--connections) CONNECTIONS="$2"; shift 2 ;;
    -t|--threads) THREADS="$2"; shift 2 ;;
    -d|--duration) DURATION="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    -*) echo "Unknown option: $1" >&2; exit 2 ;;
    *) URL="$1"; shift ;;
  esac
done

[[ "$THREADS" =~ ^[1-9][0-9]*$ ]] || { echo "threads must be positive" >&2; exit 2; }
if [[ -n "$CONNECTIONS" ]]; then
  [[ "$CONNECTIONS" =~ ^[1-9][0-9]*$ ]] || { echo "connections must be positive" >&2; exit 2; }
  ((CONNECTIONS >= THREADS)) || { echo "connections must be >= threads" >&2; exit 2; }
  SWEEP=("$CONNECTIONS")
else
  SWEEP=()
  for value in "${DEFAULT_SWEEP[@]}"; do ((value >= THREADS)) && SWEEP+=("$value"); done
  ((${#SWEEP[@]})) || SWEEP=("$THREADS")
fi

command -v wrk >/dev/null || { echo "wrk is required: sudo apt install wrk" >&2; exit 1; }
command -v curl >/dev/null || { echo "curl is required" >&2; exit 1; }
mkdir -p "$RESULT_DIR"
curl --fail --silent --show-error "$URL" >/dev/null

{
  echo "timestamp_utc=$(date -u --iso-8601=seconds)"
  echo "url=$URL"
  echo "wrk_threads=$THREADS"
  echo "duration=$DURATION"
  echo "connections=${SWEEP[*]}"
  echo "kernel=$(uname -srmo)"
  echo "compiler=$(c++ --version | head -n1)"
  echo "cmake=$(cmake --version | head -n1)"
  lscpu
} > "$RESULT_DIR/environment.txt"

WARMUP_CONNECTIONS=32
((WARMUP_CONNECTIONS >= THREADS)) || WARMUP_CONNECTIONS="$THREADS"
echo "Warm-up: threads=$THREADS connections=$WARMUP_CONNECTIONS duration=15s"
wrk -t"$THREADS" -c"$WARMUP_CONNECTIONS" -d15s "$URL" > "$RESULT_DIR/warmup.txt"

for connections in "${SWEEP[@]}"; do
  echo "Benchmarking threads=$THREADS concurrency=$connections duration=$DURATION"
  wrk -t"$THREADS" -c"$connections" -d"$DURATION" --latency "$URL" \
    | tee "$RESULT_DIR/connections-${connections}.txt"
  sleep 5
done

echo "Results written to: $RESULT_DIR"
