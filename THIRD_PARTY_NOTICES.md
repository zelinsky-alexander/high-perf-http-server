# Third-Party Notices

The Java NIO, Python asyncio, C++20, and Go `net/http` baselines use their language/runtime standard libraries directly and do not vendor third-party runtime source code into this repository.

The Maven build resolves the following build plugins:

- `org.apache.maven.plugins:maven-compiler-plugin` — Apache License 2.0 — compiles Java source.
- `org.apache.maven.plugins:maven-jar-plugin` — Apache License 2.0 — creates the executable JAR manifest.

The Rust Hyper baseline declares the following direct Cargo dependencies:

- `tokio` — MIT — asynchronous runtime, networking, scheduling, and signal handling.
- `hyper` — MIT — low-level HTTP/1.1 server implementation.
- `hyper-util` — MIT — Tokio I/O adapter used by Hyper.
- `http-body-util` — MIT — concrete HTTP response body utility.

Cargo resolves additional transitive dependencies for those crates. Their exact versions and licence metadata should be captured from the generated `Cargo.lock` and reviewed before redistributing benchmark binaries. MIT licence notices from redistributed dependencies must be preserved as required by their respective licence texts.

Maven, the selected JDK distribution, Python, the C++ toolchain, Go, Rust/Cargo, `wrk`, the operating system, and other development or benchmark tools are installed separately and are not redistributed by this repository.

Versions and licences must be reviewed whenever dependencies or benchmark implementations are added or upgraded.
