# C++20 HTTP server baseline

Dependency-free HTTP/1.1 benchmark server written in C++20.

## Architecture

- Platform-neutral HTTP connection and parsing core.
- Small `EventLoop` abstraction used by the server core.
- Linux backend: `epoll`.
- Other POSIX and Windows fallback: `poll`/`WSAPoll`.
- Cross-platform socket wrappers for non-blocking mode, errors, close, receive, and send.
- One event-loop thread for the initial baseline.

This is a portability-first baseline. The Windows fallback is functional but is not an IOCP implementation. A future Windows-specific backend can implement the same event-loop contract without changing HTTP parsing and routing code.

## Endpoints

- `GET /health` returns `ok\n`.
- `GET /plaintext` returns `Hello, World!\n`.
- Unknown paths return `404`.
- Unsupported methods return `405` and close the connection.

The server supports HTTP/1.1 keep-alive, sequential pipelined requests, partial reads, and partial writes. Request headers are limited to 16 KiB.

## Dependencies

No third-party runtime or source dependency is used.

Build dependencies:

- CMake, BSD-3-Clause licence, build-system generation, actively maintained.
- A C++20 compiler such as GCC, GPL toolchain components with runtime exceptions, actively maintained.

These tools are used to build the project and are not linked into the resulting server as application libraries.

## Ubuntu 24.04 / WSL2

```bash
sudo apt update
sudo apt install -y build-essential cmake
chmod +x scripts/run-cpp20.sh scripts/benchmark-cpp20.sh
HTTP_PORT=8888 ./scripts/run-cpp20.sh
```

Validate:

```bash
curl -i http://127.0.0.1:8888/health
curl -i http://127.0.0.1:8888/plaintext
```

Benchmark:

```bash
./scripts/benchmark-cpp20.sh \
  -c 128 \
  -t 4 \
  -d 60s \
  http://127.0.0.1:8888/plaintext
```

## Cross-platform build

Linux and other Unix-like systems:

```bash
cmake -S servers/cpp20 -B servers/cpp20/build-release -DCMAKE_BUILD_TYPE=Release
cmake --build servers/cpp20/build-release --parallel
```

Windows with Visual Studio:

```powershell
cmake -S servers/cpp20 -B servers/cpp20/build
cmake --build servers/cpp20/build --config Release
```

Manual licence and similarity review is still recommended before publication or commercial reuse.
