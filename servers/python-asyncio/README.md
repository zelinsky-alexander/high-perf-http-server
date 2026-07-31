# Python asyncio HTTP server

Dependency-free CPython HTTP/1.1 baseline using the standard-library `asyncio` streams API.

## Requirements

- Python 3.12 or newer
- Ubuntu 24.04 / WSL2 for the initial benchmark environment

No third-party runtime packages are required.

## Endpoints

- `GET /health` returns `ok\n`
- `GET /plaintext` returns `Hello, World!\n`

The server supports HTTP/1.1 persistent connections, sequential pipelined requests, bounded request headers, partial writes through asyncio flow control, and graceful SIGINT/SIGTERM shutdown.

## Run directly

```bash
python3 server.py --host 127.0.0.1 --port 8080 --backlog 1024
```

Or from the repository root:

```bash
bash scripts/run-python-asyncio.sh
```

Environment overrides:

```bash
HTTP_PORT=8888 bash scripts/run-python-asyncio.sh
```

## Validate

```bash
curl -i http://127.0.0.1:8080/health
curl -i http://127.0.0.1:8080/plaintext
```

## Benchmark

```bash
bash scripts/benchmark-python-asyncio.sh
bash scripts/benchmark-python-asyncio.sh -c 128 -t 2 -d 60s
```

This implementation is the standard-library Python baseline. Uvicorn with `uvloop` and `httptools` should be added as a separate ecosystem/framework benchmark rather than replacing this server.
