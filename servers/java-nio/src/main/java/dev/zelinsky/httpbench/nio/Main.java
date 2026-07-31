package dev.zelinsky.httpbench.nio;

import java.io.IOException;
import java.net.InetSocketAddress;
import java.nio.ByteBuffer;
import java.nio.channels.SelectionKey;
import java.nio.channels.Selector;
import java.nio.channels.ServerSocketChannel;
import java.nio.channels.SocketChannel;
import java.nio.charset.StandardCharsets;
import java.util.ArrayDeque;
import java.util.Deque;
import java.util.Iterator;

public final class Main {
    private static final int DEFAULT_PORT = 8888;
    private static final int READ_BUFFER_SIZE = 16 * 1024;
    private static final int MAX_EVENTS_PER_SELECT = 1_024;

    private static final byte[] HEALTH_KEEP_ALIVE = response("200 OK", "text/plain", "ok\n", false);
    private static final byte[] HEALTH_CLOSE = response("200 OK", "text/plain", "ok\n", true);
    private static final byte[] PLAINTEXT_KEEP_ALIVE = response("200 OK", "text/plain", "Hello, World!\n", false);
    private static final byte[] PLAINTEXT_CLOSE = response("200 OK", "text/plain", "Hello, World!\n", true);
    private static final byte[] NOT_FOUND_KEEP_ALIVE = response("404 Not Found", "text/plain", "Not Found\n", false);
    private static final byte[] NOT_FOUND_CLOSE = response("404 Not Found", "text/plain", "Not Found\n", true);
    private static final byte[] METHOD_NOT_ALLOWED = response("405 Method Not Allowed", "text/plain", "Method Not Allowed\n", true);
    private static final byte[] HEADER_TOO_LARGE = response("431 Request Header Fields Too Large", "text/plain", "Request Header Too Large\n", true);

    private Main() {
    }

    public static void main(String[] args) throws IOException {
        Config config = Config.parse(args);

        try (Selector selector = Selector.open();
             ServerSocketChannel listener = ServerSocketChannel.open()) {
            listener.configureBlocking(false);
            listener.bind(new InetSocketAddress(config.host(), config.port()), config.backlog());
            listener.register(selector, SelectionKey.OP_ACCEPT);

            System.out.printf("java-nio listening on http://%s:%d%n", config.host(), config.port());

            while (!Thread.currentThread().isInterrupted()) {
                selector.select();
                Iterator<SelectionKey> keys = selector.selectedKeys().iterator();
                int processed = 0;

                while (keys.hasNext() && processed++ < MAX_EVENTS_PER_SELECT) {
                    SelectionKey key = keys.next();
                    keys.remove();

                    if (!key.isValid()) {
                        continue;
                    }

                    try {
                        if (key.isAcceptable()) {
                            acceptReady(selector, listener);
                        } else {
                            Connection connection = (Connection) key.attachment();

                            if (key.isReadable()) {
                                connection.readReady(key);
                            }
                            if (key.isValid() && key.isWritable()) {
                                connection.writeReady(key);
                            }
                        }
                    } catch (IOException | RuntimeException exception) {
                        closeKey(key);
                    }
                }
            }
        }
    }

    private static void acceptReady(Selector selector, ServerSocketChannel listener) throws IOException {
        SocketChannel socket;
        while ((socket = listener.accept()) != null) {
            socket.configureBlocking(false);
            socket.socket().setTcpNoDelay(true);
            socket.register(selector, SelectionKey.OP_READ, new Connection(socket));
        }
    }

    private static void closeKey(SelectionKey key) {
        try {
            key.channel().close();
        } catch (IOException ignored) {
            // Best-effort cleanup after a connection failure.
        }
        key.cancel();
    }

    private static byte[] response(String status, String contentType, String body, boolean close) {
        byte[] bodyBytes = body.getBytes(StandardCharsets.US_ASCII);
        String headers = "HTTP/1.1 " + status + "\r\n"
                + "Content-Type: " + contentType + "\r\n"
                + "Content-Length: " + bodyBytes.length + "\r\n"
                + "Connection: " + (close ? "close" : "keep-alive") + "\r\n"
                + "\r\n";
        byte[] headerBytes = headers.getBytes(StandardCharsets.US_ASCII);
        byte[] complete = new byte[headerBytes.length + bodyBytes.length];
        System.arraycopy(headerBytes, 0, complete, 0, headerBytes.length);
        System.arraycopy(bodyBytes, 0, complete, headerBytes.length, bodyBytes.length);
        return complete;
    }

    private static final class Connection {
        private final SocketChannel socket;
        private final ByteBuffer input = ByteBuffer.allocateDirect(READ_BUFFER_SIZE);
        private final Deque<ByteBuffer> output = new ArrayDeque<>();
        private boolean closeAfterWrite;

        private Connection(SocketChannel socket) {
            this.socket = socket;
        }

        private void readReady(SelectionKey key) throws IOException {
            while (true) {
                int read = socket.read(input);
                if (read > 0) {
                    parseRequests();
                    if (closeAfterWrite) {
                        break;
                    }
                    continue;
                }
                if (read == 0) {
                    break;
                }
                closeKey(key);
                return;
            }

            if (!output.isEmpty() && key.isValid()) {
                key.interestOps(SelectionKey.OP_READ | SelectionKey.OP_WRITE);
            }
        }

        private void parseRequests() {
            input.flip();
            int consumedThrough = 0;

            while (!closeAfterWrite) {
                int headerEnd = findHeaderEnd(input, consumedThrough);
                if (headerEnd < 0) {
                    break;
                }

                int requestLength = headerEnd - consumedThrough;
                byte[] requestBytes = new byte[requestLength];
                int previousPosition = input.position();
                input.position(consumedThrough);
                input.get(requestBytes);
                input.position(previousPosition);

                String request = new String(requestBytes, StandardCharsets.US_ASCII);
                enqueueResponse(request);
                consumedThrough = headerEnd + 4;
            }

            input.position(consumedThrough);
            input.compact();

            if (!input.hasRemaining() && !closeAfterWrite) {
                output.add(ByteBuffer.wrap(HEADER_TOO_LARGE));
                closeAfterWrite = true;
                input.clear();
            }
        }

        private void enqueueResponse(String request) {
            int lineEnd = request.indexOf("\r\n");
            String requestLine = lineEnd >= 0 ? request.substring(0, lineEnd) : request;
            boolean close = containsConnectionClose(request);

            if (!requestLine.startsWith("GET ")) {
                output.add(ByteBuffer.wrap(METHOD_NOT_ALLOWED));
                closeAfterWrite = true;
                return;
            }

            int targetStart = 4;
            int targetEnd = requestLine.indexOf(' ', targetStart);
            if (targetEnd < 0) {
                output.add(ByteBuffer.wrap(METHOD_NOT_ALLOWED));
                closeAfterWrite = true;
                return;
            }

            String target = requestLine.substring(targetStart, targetEnd);
            byte[] responseBytes;
            if ("/health".equals(target)) {
                responseBytes = close ? HEALTH_CLOSE : HEALTH_KEEP_ALIVE;
            } else if ("/plaintext".equals(target)) {
                responseBytes = close ? PLAINTEXT_CLOSE : PLAINTEXT_KEEP_ALIVE;
            } else {
                responseBytes = close ? NOT_FOUND_CLOSE : NOT_FOUND_KEEP_ALIVE;
            }

            output.add(ByteBuffer.wrap(responseBytes));
            closeAfterWrite = close;
        }

        private void writeReady(SelectionKey key) throws IOException {
            while (!output.isEmpty()) {
                ByteBuffer current = output.peek();
                socket.write(current);
                if (current.hasRemaining()) {
                    return;
                }
                output.remove();
            }

            if (closeAfterWrite) {
                closeKey(key);
            } else if (key.isValid()) {
                key.interestOps(SelectionKey.OP_READ);
            }
        }

        private static int findHeaderEnd(ByteBuffer buffer, int start) {
            for (int index = start; index <= buffer.limit() - 4; index++) {
                if (buffer.get(index) == '\r'
                        && buffer.get(index + 1) == '\n'
                        && buffer.get(index + 2) == '\r'
                        && buffer.get(index + 3) == '\n') {
                    return index;
                }
            }
            return -1;
        }

        private static boolean containsConnectionClose(String request) {
            return request.regionMatches(true, 0, "Connection: close", 0, 17)
                    || request.toLowerCase(java.util.Locale.ROOT).contains("\r\nconnection: close\r\n");
        }
    }

    private record Config(String host, int port, int backlog) {
        private static Config parse(String[] args) {
            String host = "127.0.0.1";
            int port = DEFAULT_PORT;
            int backlog = 1_024;

            for (int index = 0; index < args.length; index++) {
                switch (args[index]) {
                    case "--host" -> host = requireValue(args, ++index, "--host");
                    case "--port" -> port = parsePositiveInt(requireValue(args, ++index, "--port"), "port");
                    case "--backlog" -> backlog = parsePositiveInt(requireValue(args, ++index, "--backlog"), "backlog");
                    default -> throw new IllegalArgumentException("Unknown argument: " + args[index]);
                }
            }

            if (port > 65_535) {
                throw new IllegalArgumentException("port must be <= 65535");
            }
            return new Config(host, port, backlog);
        }

        private static String requireValue(String[] args, int index, String option) {
            if (index >= args.length) {
                throw new IllegalArgumentException("Missing value for " + option);
            }
            return args[index];
        }

        private static int parsePositiveInt(String value, String name) {
            try {
                int parsed = Integer.parseInt(value);
                if (parsed <= 0) {
                    throw new IllegalArgumentException(name + " must be positive");
                }
                return parsed;
            } catch (NumberFormatException exception) {
                throw new IllegalArgumentException(name + " must be an integer", exception);
            }
        }
    }
}
