#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESULT_DIR="${BENCH_RESULT_DIR:-$ROOT_DIR/benchmark-results}"
PORT="${BENCH_PORT:-18080}"
HOST="127.0.0.1"
DURATION="${BENCH_DURATION:-10s}"
WARMUP_DURATION="${BENCH_WARMUP_DURATION:-5s}"
THREADS="${BENCH_THREADS:-2}"
REPETITIONS="${BENCH_REPETITIONS:-3}"
CONNECTIONS="${BENCH_CONNECTIONS:-32 128}"
WRK_TIMEOUT="${BENCH_WRK_TIMEOUT:-10s}"

command -v wrk >/dev/null || { echo "wrk is required" >&2; exit 1; }
command -v curl >/dev/null || { echo "curl is required" >&2; exit 1; }
command -v python3 >/dev/null || { echo "python3 is required" >&2; exit 1; }

mkdir -p "$RESULT_DIR/raw"

cat > "$RESULT_DIR/environment.txt" <<EOF
timestamp_utc=$(date -u --iso-8601=seconds)
kernel=$(uname -srmo)
cpu_count=$(nproc)
threads=$THREADS
connections=$CONNECTIONS
duration=$DURATION
warmup_duration=$WARMUP_DURATION
repetitions=$REPETITIONS
wrk_timeout=$WRK_TIMEOUT
EOF

{
  echo
  lscpu
  echo
  java -version 2>&1 | head -n1 || true
  python3 --version || true
  c++ --version | head -n1 || true
  go version || true
  rustc --version || true
  wrk --version || true
} >> "$RESULT_DIR/environment.txt"

SERVER_PID=""

stop_server() {
  if [[ -n "$SERVER_PID" ]]; then
    kill "$SERVER_PID" 2>/dev/null || true
    wait "$SERVER_PID" 2>/dev/null || true
    SERVER_PID=""
  fi
}
trap stop_server EXIT

wait_for_server() {
  for _ in {1..80}; do
    if curl -fsS "http://$HOST:$PORT/health" >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.125
  done
  return 1
}

start_server() {
  local name="$1"
  local log="$RESULT_DIR/raw/${name}-server.log"

  stop_server

  case "$name" in
    java-nio)
      java -jar "$ROOT_DIR/servers/java-nio/target/java-nio-server.jar" \
        --host "$HOST" --port "$PORT" --backlog 1024 >"$log" 2>&1 &
      ;;
    python-asyncio)
      python3 "$ROOT_DIR/servers/python-asyncio/server.py" \
        --host "$HOST" --port "$PORT" --backlog 1024 >"$log" 2>&1 &
      ;;
    cpp20)
      "$ROOT_DIR/servers/cpp20/build-bench/cpp20-http-server" \
        --host "$HOST" --port "$PORT" --backlog 1024 >"$log" 2>&1 &
      ;;
    go-nethttp)
      GOMAXPROCS=1 "$ROOT_DIR/servers/go-nethttp/bin/go-nethttp" \
        --host "$HOST" --port "$PORT" >"$log" 2>&1 &
      ;;
    rust-hyper)
      "$ROOT_DIR/servers/rust-hyper/target/release/rust-hyper-server" \
        --host "$HOST" --port "$PORT" --backlog 1024 --workers 1 >"$log" 2>&1 &
      ;;
    *)
      echo "unknown server: $name" >&2
      return 2
      ;;
  esac

  SERVER_PID=$!

  if ! wait_for_server; then
    echo "$name failed to become ready" >&2
    cat "$log" >&2 || true
    return 1
  fi

  test "$(curl -fsS "http://$HOST:$PORT/health")" = "ok"
  test "$(curl -fsS "http://$HOST:$PORT/plaintext")" = "Hello, World!"
}

run_one() {
  local name="$1"
  local connections="$2"
  local repetition="$3"
  local output="$RESULT_DIR/raw/${name}-c${connections}-r${repetition}.txt"

  echo "Benchmarking $name: connections=$connections repetition=$repetition/$REPETITIONS"
  wrk \
    -t"$THREADS" \
    -c"$connections" \
    -d"$DURATION" \
    --timeout "$WRK_TIMEOUT" \
    --latency \
    "http://$HOST:$PORT/plaintext" \
    | tee "$output"
}

SERVERS=(java-nio python-asyncio cpp20 go-nethttp rust-hyper)

for name in "${SERVERS[@]}"; do
  echo "=== $name ==="
  start_server "$name"

  warmup_connections=32
  if ((warmup_connections < THREADS)); then
    warmup_connections="$THREADS"
  fi

  echo "Warm-up $name: connections=$warmup_connections duration=$WARMUP_DURATION"
  wrk \
    -t"$THREADS" \
    -c"$warmup_connections" \
    -d"$WARMUP_DURATION" \
    --timeout "$WRK_TIMEOUT" \
    "http://$HOST:$PORT/plaintext" \
    > "$RESULT_DIR/raw/${name}-warmup.txt"

  for connections in $CONNECTIONS; do
    if ((connections < THREADS)); then
      echo "Skipping invalid connections=$connections (< threads=$THREADS)" >&2
      continue
    fi
    for repetition in $(seq 1 "$REPETITIONS"); do
      run_one "$name" "$connections" "$repetition"
      sleep 2
    done
  done

  stop_server
  sleep 1
done

python3 "$ROOT_DIR/scripts/summarize-ci-benchmarks.py" \
  --input "$RESULT_DIR/raw" \
  --markdown "$RESULT_DIR/comparison.md" \
  --csv "$RESULT_DIR/comparison.csv"

cat "$RESULT_DIR/comparison.md"
