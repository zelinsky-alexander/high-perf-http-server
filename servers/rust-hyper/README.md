# Rust Hyper baseline

Minimal HTTP/1.1 benchmark server using Tokio as the async runtime and Hyper as the HTTP implementation.

## Purpose

This is the first Rust baseline for the repository. It intentionally avoids a higher-level web framework so the measured path stays close to the runtime and HTTP stack.

## Dependencies

- `tokio` — MIT — asynchronous runtime, networking, task scheduling, and signal handling.
- `hyper` — MIT — low-level HTTP/1.1 server implementation.
- `hyper-util` — MIT — Tokio I/O adapter for Hyper.
- `http-body-util` — MIT — concrete response body type used with Hyper.

These projects are actively maintained. The main benchmark concern is not restrictive licensing, but dependency/version drift: commit `Cargo.lock` after the first successful local build so later runs remain reproducible.

## Endpoints

- `GET /health` -> `ok\n`
- `GET /plaintext` -> `Hello, World!\n`
- other methods -> `405`
- unknown paths -> `404`

HTTP/1.1 keep-alive is enabled. Hyper's automatic `Date` response header is disabled for a closer wire-level comparison with the hand-written Java and C++ baselines.

## Build

```bash
cargo build --release --manifest-path servers/rust-hyper/Cargo.toml
```

## Run

```bash
HTTP_PORT=8888 RUST_WORKERS=1 bash scripts/run-rust-hyper.sh
```

`RUST_WORKERS` controls Tokio runtime worker threads. Use `1` for a single-executor comparison and a higher value for multi-core throughput experiments.

## Benchmark

```bash
bash scripts/benchmark-rust-hyper.sh \
  -c 128 \
  -t 4 \
  -d 60s \
  http://127.0.0.1:8888/plaintext
```

## Notes

The implementation uses Hyper's public HTTP/1 server builder and Tokio's public networking/runtime APIs. It does not copy third-party source code into this repository.
