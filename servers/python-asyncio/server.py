#!/usr/bin/env python3
"""Dependency-free HTTP/1.1 benchmark server built on Python asyncio."""

from __future__ import annotations

import argparse
import asyncio
import signal
from dataclasses import dataclass

MAX_HEADER_BYTES = 16 * 1024
MAX_REQUESTS_PER_CONNECTION = 10_000


def make_response(status: str, content_type: str, body: bytes, close: bool) -> bytes:
    connection = b"close" if close else b"keep-alive"
    return b"".join(
        (
            b"HTTP/1.1 ",
            status.encode("ascii"),
            b"\r\nContent-Type: ",
            content_type.encode("ascii"),
            b"\r\nContent-Length: ",
            str(len(body)).encode("ascii"),
            b"\r\nConnection: ",
            connection,
            b"\r\n\r\n",
            body,
        )
    )


HEALTH_KEEP_ALIVE = make_response("200 OK", "text/plain", b"ok\n", False)
HEALTH_CLOSE = make_response("200 OK", "text/plain", b"ok\n", True)
PLAINTEXT_KEEP_ALIVE = make_response("200 OK", "text/plain", b"Hello, World!\n", False)
PLAINTEXT_CLOSE = make_response("200 OK", "text/plain", b"Hello, World!\n", True)
NOT_FOUND_KEEP_ALIVE = make_response("404 Not Found", "text/plain", b"Not Found\n", False)
NOT_FOUND_CLOSE = make_response("404 Not Found", "text/plain", b"Not Found\n", True)
METHOD_NOT_ALLOWED = make_response(
    "405 Method Not Allowed", "text/plain", b"Method Not Allowed\n", True
)
BAD_REQUEST = make_response("400 Bad Request", "text/plain", b"Bad Request\n", True)
HEADER_TOO_LARGE = make_response(
    "431 Request Header Fields Too Large",
    "text/plain",
    b"Request Header Too Large\n",
    True,
)


@dataclass(frozen=True, slots=True)
class Config:
    host: str
    port: int
    backlog: int


def select_response(header_block: bytes) -> tuple[bytes, bool]:
    lines = header_block.split(b"\r\n")
    if not lines:
        return BAD_REQUEST, True

    request_parts = lines[0].split(b" ")
    if len(request_parts) != 3:
        return BAD_REQUEST, True

    method, target, version = request_parts
    if version != b"HTTP/1.1":
        return BAD_REQUEST, True
    if method != b"GET":
        return METHOD_NOT_ALLOWED, True

    close = any(line.lower() == b"connection: close" for line in lines[1:])

    if target == b"/health":
        return (HEALTH_CLOSE if close else HEALTH_KEEP_ALIVE), close
    if target == b"/plaintext":
        return (PLAINTEXT_CLOSE if close else PLAINTEXT_KEEP_ALIVE), close
    return (NOT_FOUND_CLOSE if close else NOT_FOUND_KEEP_ALIVE), close


async def handle_connection(
    reader: asyncio.StreamReader, writer: asyncio.StreamWriter
) -> None:
    transport = writer.transport
    transport.set_write_buffer_limits(high=64 * 1024, low=16 * 1024)

    try:
        for _ in range(MAX_REQUESTS_PER_CONNECTION):
            try:
                request = await reader.readuntil(b"\r\n\r\n")
            except asyncio.LimitOverrunError:
                writer.write(HEADER_TOO_LARGE)
                await writer.drain()
                return
            except asyncio.IncompleteReadError:
                return

            if len(request) > MAX_HEADER_BYTES:
                writer.write(HEADER_TOO_LARGE)
                await writer.drain()
                return

            response, close = select_response(request[:-4])
            writer.write(response)
            await writer.drain()

            if close:
                return
    except (ConnectionError, asyncio.CancelledError):
        return
    finally:
        writer.close()
        try:
            await writer.wait_closed()
        except ConnectionError:
            pass


def parse_args() -> Config:
    parser = argparse.ArgumentParser(description="Python asyncio HTTP benchmark server")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8080)
    parser.add_argument("--backlog", type=int, default=1024)
    args = parser.parse_args()

    if not 1 <= args.port <= 65_535:
        parser.error("--port must be between 1 and 65535")
    if args.backlog <= 0:
        parser.error("--backlog must be positive")

    return Config(host=args.host, port=args.port, backlog=args.backlog)


async def serve(config: Config) -> None:
    server = await asyncio.start_server(
        handle_connection,
        host=config.host,
        port=config.port,
        backlog=config.backlog,
        limit=MAX_HEADER_BYTES + 4,
        reuse_address=True,
    )

    stop_event = asyncio.Event()
    loop = asyncio.get_running_loop()
    for signum in (signal.SIGINT, signal.SIGTERM):
        loop.add_signal_handler(signum, stop_event.set)

    sockets = server.sockets or []
    addresses = ", ".join(str(sock.getsockname()) for sock in sockets)
    print(f"python-asyncio listening on {addresses}", flush=True)

    async with server:
        await stop_event.wait()


def main() -> None:
    config = parse_args()
    try:
        asyncio.run(serve(config))
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
