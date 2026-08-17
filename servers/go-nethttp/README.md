# Go net/http baseline

Minimal dependency-free HTTP/1.1 benchmark server implemented with the Go standard library.

## Purpose

This is the initial Go baseline for cross-language comparison. It intentionally uses `net/http` directly without third-party routers, middleware, logging frameworks, or JSON libraries.

Baseline contract:

- `GET /health` -> `ok\n`
- `GET /plaintext` -> `Hello, World!\n`
- unknown path -> `404`
- non-GET method -> `405`
- HTTP/1.1 keep-alive handled by `net/http`
- 16 KiB maximum header budget configured through `http.Server.MaxHeaderBytes`
- no TLS, compression, reverse proxy, database, or access logging

The Go standard library is distributed under a BSD-style license and is maintained as part of the Go project. No third-party runtime dependency is used by this implementation.

## Build

From this directory:

```bash
go build -trimpath -o bin/go-nethttp .
```

Or use the repository script:

```bash
bash ../../scripts/run-go-nethttp.sh
```

## Run on another port

```bash
HTTP_PORT=8888 bash ../../scripts/run-go-nethttp.sh
```

Optionally constrain Go scheduler parallelism for controlled comparisons:

```bash
GO_MAX_PROCS=1 HTTP_PORT=8888 bash ../../scripts/run-go-nethttp.sh
```

## Validate

```bash
curl -i http://127.0.0.1:8888/health
curl -i http://127.0.0.1:8888/plaintext
```

## Benchmark

```bash
bash ../../scripts/benchmark-go-nethttp.sh \
  -c 128 \
  -t 4 \
  -d 60s \
  http://127.0.0.1:8888/plaintext
```

Results are written under `results/go-nethttp/<timestamp>/` from the repository root.

## Comparison note

`net/http` is a production-oriented standard-library HTTP stack rather than a hand-written parser. It may add standard response headers such as `Date`, so exact wire bytes can differ from lower-level implementations even when response bodies and endpoint semantics match. Record those differences when interpreting benchmark results.
