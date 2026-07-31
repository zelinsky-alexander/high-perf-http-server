# High-Performance HTTP Server Research

Cross-language research and reproducible performance benchmarking of high-performance HTTP servers implemented with different languages, runtimes, and frameworks in the same environment.

## Initial environment

- Windows 10 desktop host
- WSL2
- Ubuntu 24.04
- HTTP/1.1 over loopback
- No TLS, compression, reverse proxy, database, or access logging in baseline tests

## First server

The first implementation is a dependency-free Java NIO baseline targeting Java 26:

```text
servers/java-nio
```

It deliberately uses the JDK networking APIs directly. Later Java implementations can add Netty or other frameworks while preserving the same endpoint and benchmark contract.

## Baseline endpoints

- `GET /health` returns `ok\n`
- `GET /plaintext` returns `Hello, World!\n`

Both endpoints support HTTP/1.1 keep-alive. Other methods return `405`; unknown paths return `404`.

## Run

```bash
cd servers/java-nio
mvn -q clean package
java -jar target/java-nio-server.jar --host 127.0.0.1 --port 8080
```

Or from the repository root:

```bash
./scripts/run-java-nio.sh
```

Validate:

```bash
curl -i http://127.0.0.1:8080/health
curl -i http://127.0.0.1:8080/plaintext
```

## Benchmark

Install `wrk` inside Ubuntu:

```bash
sudo apt update
sudo apt install -y wrk
```

Run the initial benchmark:

```bash
./scripts/benchmark-java-nio.sh
```

The script performs a warm-up and a small concurrency sweep. Raw output is written under `results/`.

## Benchmarking principles

- Run one server implementation at a time.
- Use identical response bodies and HTTP semantics.
- Disable debug logging and profiling in measured runs.
- Warm up before measurement.
- Repeat every scenario and compare medians.
- Record runtime, compiler, OS, CPU, worker count, command line, CPU use, memory, throughput, latency, and errors.
- Treat WSL2 results as comparative local results, not universal production capacity.

## Planned structure

```text
specification/       Shared endpoint and measurement contracts
servers/             One folder per language/framework implementation
scripts/             Common build, run, validation, and benchmark tooling
results/             Ignored local benchmark output
```

## License

Apache License 2.0. See `LICENSE`.
