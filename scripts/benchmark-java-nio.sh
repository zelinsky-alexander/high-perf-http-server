#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESULT_DIR="$ROOT_DIR/results/java-nio/$(date -u +%Y%m%dT%H%M%SZ)"
URL="${BENCHMARK_URL:-http://127.0.0.1:8080/plaintext}"
THREADS="${WRK_THREADS:-2}"
DURATION="${WRK_DURATION:-30s}"
CONNECTIONS=""
DEFAULT_SWEEP=(2 8 32 128 512)

usage() {
  cat <<'EOF'
Usage:
  benchmark-java-nio.sh [options] [url]

Options:
  -c, --connections N   Run one benchmark with N open connections.
                        Without this option, runs the default sweep.
  -t, --threads N       Number of wrk threads (default: 2).
  -d, --duration T      Duration of each measured run (default: 30s).
  -h, --help            Show this help.

Examples:
  ./scripts/benchmark-java-nio.sh
  ./scripts/benchmark-java-nio.sh -c 10 -t 2 http://127.0.0.1:8080/plaintext
  ./scripts/benchmark-java-nio.sh -c 128 -t 4 -d 60s
EOF
}

is_positive_integer() {
  [[ "$1" =~ ^[1-9][0-9]*$ ]]
}

while (($# > 0)); do
  case "$1" in
    -c|--connections)
      (($# >= 2)) || { echo "Missing value for $1" >&2; usage >&2; exit 2; }
      CONNECTIONS="$2"
      shift 2
      ;;
    -t|--threads)
      (($# >= 2)) || { echo "Missing value for $1" >&2; usage >&2; exit 2; }
      THREADS="$2"
      shift 2
      ;;
    -d|--duration)
      (($# >= 2)) || { echo "Missing value for $1" >&2; usage >&2; exit 2; }
      DURATION="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      if (($# > 1)); then
        echo "Only one URL may be supplied" >&2
        exit 2
      fi
      if (($# == 1)); then
        URL="$1"
      fi
      break
      ;;
    -*)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
    *)
      URL="$1"
      shift
      if (($# > 0)); then
        echo "Unexpected argument: $1" >&2
        usage >&2
        exit 2
      fi
      ;;
  esac
done

is_positive_integer "$THREADS" || {
  echo "wrk thread count must be a positive integer: $THREADS" >&2
  exit 2
}

if [[ -n "$CONNECTIONS" ]]; then
  is_positive_integer "$CONNECTIONS" || {
    echo "connection count must be a positive integer: $CONNECTIONS" >&2
    exit 2
  }
  if ((CONNECTIONS < THREADS)); then
    echo "connection count ($CONNECTIONS) must be >= wrk thread count ($THREADS)" >&2
    exit 2
  fi
  SWEEP=("$CONNECTIONS")
else
  SWEEP=()
  for connections in "${DEFAULT_SWEEP[@]}"; do
    if ((connections >= THREADS)); then
      SWEEP+=("$connections")
    fi
  done

  if ((${#SWEEP[@]} == 0)); then
    SWEEP=("$THREADS")
  fi
fi

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
  echo "connections=${SWEEP[*]}"
  echo "kernel=$(uname -srmo)"
  echo "java=$(java -version 2>&1 | head -n1)"
  echo "maven=$(mvn -version 2>&1 | head -n1)"
  lscpu
} > "$RESULT_DIR/environment.txt"

WARMUP_CONNECTIONS=32
if ((WARMUP_CONNECTIONS < THREADS)); then
  WARMUP_CONNECTIONS="$THREADS"
fi

echo "Warm-up: threads=$THREADS connections=$WARMUP_CONNECTIONS duration=15s"
wrk \
  -t"$THREADS" \
  -c"$WARMUP_CONNECTIONS" \
  -d15s \
  "$URL" \
  > "$RESULT_DIR/warmup.txt"

for connections in "${SWEEP[@]}"; do
  echo "Benchmarking threads=$THREADS concurrency=$connections duration=$DURATION"
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
