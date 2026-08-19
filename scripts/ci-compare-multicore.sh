#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESULT_DIR="${BENCH_RESULT_DIR:-$ROOT_DIR/benchmark-results-multicore}"
BASE_PORT="${BENCH_BASE_PORT:-18100}"
HOST="127.0.0.1"
DURATION="${BENCH_DURATION:-10s}"
WARMUP_DURATION="${BENCH_WARMUP_DURATION:-5s}"
REPETITIONS="${BENCH_REPETITIONS:-3}"
CONNECTIONS="${BENCH_CONNECTIONS:-32 128}"
WRK_TIMEOUT="${BENCH_WRK_TIMEOUT:-10s}"
MAX_SHARDS="${BENCH_MAX_SHARDS:-4}"

command -v wrk >/dev/null || { echo "wrk is required" >&2; exit 1; }
command -v curl >/dev/null || { echo "curl is required" >&2; exit 1; }
command -v python3 >/dev/null || { echo "python3 is required" >&2; exit 1; }

CPU_COUNT="$(nproc)"
SHARDS="$CPU_COUNT"
if ((SHARDS > MAX_SHARDS)); then SHARDS="$MAX_SHARDS"; fi
if ((SHARDS < 1)); then SHARDS=1; fi

mkdir -p "$RESULT_DIR/raw"

cat > "$RESULT_DIR/environment.txt" <<EOF
timestamp_utc=$(date -u --iso-8601=seconds)
kernel=$(uname -srmo)
cpu_count=$CPU_COUNT
shards=$SHARDS
connections=$CONNECTIONS
duration=$DURATION
warmup_duration=$WARMUP_DURATION
repetitions=$REPETITIONS
wrk_timeout=$WRK_TIMEOUT
mode=multicore-process-sharded
EOF

SERVER_PIDS=()

stop_servers() {
  for pid in "${SERVER_PIDS[@]:-}"; do
    kill "$pid" 2>/dev/null || true
  done
  for pid in "${SERVER_PIDS[@]:-}"; do
    wait "$pid" 2>/dev/null || true
  done
  SERVER_PIDS=()
}
trap stop_servers EXIT

wait_for_port() {
  local port="$1"
  for _ in {1..80}; do
    if curl -fsS "http://$HOST:$port/health" >/dev/null 2>&1; then return 0; fi
    sleep 0.125
  done
  return 1
}

start_shards() {
  local name="$1"
  stop_servers

  for ((i=0; i<SHARDS; i++)); do
    local port=$((BASE_PORT + i))
    local log="$RESULT_DIR/raw/${name}-shard${i}-server.log"

    case "$name" in
      java-nio)
        java -jar "$ROOT_DIR/servers/java-nio/target/java-nio-server.jar" \
          --host "$HOST" --port "$port" --backlog 1024 >"$log" 2>&1 &
        ;;
      python-asyncio)
        python3 "$ROOT_DIR/servers/python-asyncio/server.py" \
          --host "$HOST" --port "$port" --backlog 1024 >"$log" 2>&1 &
        ;;
      cpp20)
        "$ROOT_DIR/servers/cpp20/build-bench/cpp20-http-server" \
          --host "$HOST" --port "$port" --backlog 1024 >"$log" 2>&1 &
        ;;
      go-nethttp)
        GOMAXPROCS=1 "$ROOT_DIR/servers/go-nethttp/bin/go-nethttp" \
          --host "$HOST" --port "$port" >"$log" 2>&1 &
        ;;
      rust-hyper)
        "$ROOT_DIR/servers/rust-hyper/target/release/rust-hyper-server" \
          --host "$HOST" --port "$port" --backlog 1024 --workers 1 >"$log" 2>&1 &
        ;;
      *) echo "unknown server: $name" >&2; return 2 ;;
    esac

    SERVER_PIDS+=("$!")
  done

  for ((i=0; i<SHARDS; i++)); do
    local port=$((BASE_PORT + i))
    if ! wait_for_port "$port"; then
      echo "$name shard $i failed to become ready" >&2
      cat "$RESULT_DIR/raw/${name}-shard${i}-server.log" >&2 || true
      return 1
    fi
    test "$(curl -fsS "http://$HOST:$port/plaintext")" = "Hello, World!"
  done
}

connections_for_shard() {
  local total="$1" shard="$2"
  local base=$((total / SHARDS))
  local rem=$((total % SHARDS))
  local value="$base"
  if ((shard < rem)); then value=$((value + 1)); fi
  if ((value < 1)); then value=1; fi
  echo "$value"
}

run_parallel_wrk() {
  local name="$1" total_connections="$2" repetition="$3" duration="$4" prefix="$5"
  local wrk_pids=()

  for ((i=0; i<SHARDS; i++)); do
    local port=$((BASE_PORT + i))
    local shard_connections
    shard_connections="$(connections_for_shard "$total_connections" "$i")"
    local output="$RESULT_DIR/raw/${name}-${prefix}-c${total_connections}-r${repetition}-shard${i}.txt"

    wrk -t1 -c"$shard_connections" -d"$duration" --timeout "$WRK_TIMEOUT" --latency \
      "http://$HOST:$port/plaintext" >"$output" 2>&1 &
    wrk_pids+=("$!")
  done

  local failed=0
  for pid in "${wrk_pids[@]}"; do
    if ! wait "$pid"; then failed=1; fi
  done
  return "$failed"
}

SERVERS=(java-nio python-asyncio cpp20 go-nethttp rust-hyper)

for name in "${SERVERS[@]}"; do
  echo "=== multicore/process-sharded: $name ($SHARDS shards) ==="
  start_shards "$name"

  echo "Warm-up $name"
  run_parallel_wrk "$name" 32 0 "$WARMUP_DURATION" warmup

  for total_connections in $CONNECTIONS; do
    for repetition in $(seq 1 "$REPETITIONS"); do
      echo "Benchmarking $name: total_connections=$total_connections repetition=$repetition/$REPETITIONS shards=$SHARDS"
      run_parallel_wrk "$name" "$total_connections" "$repetition" "$DURATION" measured
      sleep 2
    done
  done

  stop_servers
  sleep 1
done

python3 "$ROOT_DIR/scripts/summarize-ci-multicore.py" \
  --input "$RESULT_DIR/raw" \
  --markdown "$RESULT_DIR/comparison.md" \
  --csv "$RESULT_DIR/comparison.csv" \
  --shards "$SHARDS"

cat "$RESULT_DIR/comparison.md"
