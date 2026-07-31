# Third-Party Notices

The initial Java NIO server implementation uses only Java Standard Edition APIs at runtime and contains no bundled third-party runtime source code.

The Maven build resolves the following build plugins:

- `org.apache.maven.plugins:maven-compiler-plugin` — Apache License 2.0 — compiles Java source.
- `org.apache.maven.plugins:maven-jar-plugin` — Apache License 2.0 — creates the executable JAR manifest.

Maven, the selected JDK distribution, `wrk`, the operating system, and other development or benchmark tools are installed separately and are not redistributed by this repository.

Versions and licences must be reviewed whenever dependencies or benchmark implementations are added.
