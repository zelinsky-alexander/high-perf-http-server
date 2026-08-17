# High-Performance HTTP Server Research

Cross-language research and reproducible performance benchmarking of high-performance HTTP servers implemented with different languages, runtimes, and frameworks in the same environment.

## Initial environment

- Windows 10 desktop host
- WSL2
- Ubuntu 24.04
- HTTP/1.1 over loopback
- No TLS, compression, reverse proxy, database, or access logging in baseline tests

## Current baseline servers

### Java NIO

```text
servers/java-nio
```

Dependency-free Java NIO implementation targeting Java 21. It uses the JDK networking APIs directly so later Netty and virtual-thread implementations can be measured separately.

Run:

```bash
bash scripts/run-java-nio.sh
```

Benchmark:

```bash
bash scripts/benchmark-java-nio.sh
```

### Python asyncio

```text
servers/python-asyncio
```

Dependency-free CPython implementation using the standard-library `asyncio` streams API. It targets Python 3.12+, which is the Ubuntu 24.04 baseline. Uvicorn, uvloop, and httptools will be evaluated as separate framework/runtime variants.

Run:

```bash
bash scripts/run-python-asyncio.sh
```

Benchmark:

```bash
bash scripts/benchmark-python-asyncio.sh
```

### C++20

```text
servers/cpp20
```

Dependency-free C++20 implementation with the HTTP/server core separated from the platform event loop. Linux uses an `epoll` backend, with a portable poll-style fallback for other supported platforms.

Run:

```bash
bash scripts/run-cpp20.sh
```

Benchmark:

```bash
bash scripts/benchmark-cpp20.sh
```

### Go net/http

```text
servers/go-nethttp
```

Dependency-free Go implementation using the standard-library `net/http` stack directly. Third-party routers and frameworks are intentionally excluded from this baseline so they can be measured separately later.

Run:

```bash
bash scripts/run-go-nethttp.sh
```

Benchmark:

```bash
bash scripts/benchmark-go-nethttp.sh
```

### Rust Hyper

```text
servers/rust-hyper
```

Rust HTTP/1.1 implementation using Tokio for the asynchronous runtime and Hyper for the low-level HTTP server. Higher-level Rust frameworks such as Axum can be benchmarked later as separate variants.

Run:

```bash
bash scripts/run-rust-hyper.sh
```

Benchmark:

```bash
bash scripts/benchmark-rust-hyper.sh
```

`RUST_WORKERS` controls Tokio runtime worker threads; the baseline defaults to one worker so single-executor and multi-core experiments can be kept separate.

## Baseline endpoints

- `GET /health` returns `ok\n`
- `GET /plaintext` returns `Hello, World!\n`

Both endpoints support HTTP/1.1 keep-alive. Other methods return `405`; unknown paths return `404`.

## Port selection

All run scripts use port `8080` unless overridden:

```bash
HTTP_PORT=8888 bash scripts/run-java-nio.sh
HTTP_PORT=8888 bash scripts/run-python-asyncio.sh
HTTP_PORT=8888 bash scripts/run-cpp20.sh
HTTP_PORT=8888 bash scripts/run-go-nethttp.sh
HTTP_PORT=8888 RUST_WORKERS=1 bash scripts/run-rust-hyper.sh
```

Validate:

```bash
curl -i http://127.0.0.1:8080/health
curl -i http://127.0.0.1:8080/plaintext
```

## Benchmark tooling

Install `wrk` inside Ubuntu:

```bash
sudo apt update
sudo apt install -y wrk
```

Example controlled run:

```bash
bash scripts/benchmark-rust-hyper.sh \
  -c 128 \
  -t 4 \
  -d 60s \
  http://127.0.0.1:8080/plaintext
```

Raw output is written under `results/<implementation>/<timestamp>/`.

## Benchmarking principles

- Run one server implementation at a time.
- Use identical response bodies and HTTP semantics.
- Disable debug logging and profiling in measured runs.
- Warm up before measurement.
- Repeat every scenario and compare medians.
- Record runtime, compiler, OS, CPU, worker count, command line, CPU use, memory, throughput, latency, and errors.
- Compare single-executor and multi-core configurations separately.
- Record framework/runtime-added wire differences such as automatic response headers.
- Treat WSL2 results as comparative local results, not universal production capacity.

## Repository structure

```text
specification/       Shared endpoint and measurement contracts
servers/             One folder per language/framework implementation
scripts/             Common build, run, validation, and benchmark tooling
results/             Ignored local benchmark output
```

## License

Apache License 2.0. See `LICENSE`.
