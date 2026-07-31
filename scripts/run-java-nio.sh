#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERVER_DIR="$ROOT_DIR/servers/java-nio"
HOST="${HTTP_HOST:-127.0.0.1}"
PORT="${HTTP_PORT:-8080}"
BACKLOG="${HTTP_BACKLOG:-1024}"

command -v java >/dev/null || {
  echo "java is required" >&2
  exit 1
}
command -v mvn >/dev/null || {
  echo "maven is required" >&2
  exit 1
}

JAVA_MAJOR="$(java -version 2>&1 | awk -F'[\".]' '/version/ {print $2; exit}')"
if [[ -z "$JAVA_MAJOR" || "$JAVA_MAJOR" -lt 21 ]]; then
  echo "Java 21 or newer is required; detected: $(java -version 2>&1 | head -n1)" >&2
  exit 1
fi

mvn -q -f "$SERVER_DIR/pom.xml" clean package
exec java \
  -XX:+AlwaysPreTouch \
  -jar "$SERVER_DIR/target/java-nio-server.jar" \
  --host "$HOST" \
  --port "$PORT" \
  --backlog "$BACKLOG"
