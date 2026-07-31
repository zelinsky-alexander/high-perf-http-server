#include "httpbench/server.hpp"

#include <algorithm>
#include <cstring>
#include <iostream>
#include <stdexcept>
#include <system_error>

namespace httpbench {
namespace {

const std::string health_keep_alive =
    "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: 3\r\n"
    "Connection: keep-alive\r\n\r\nok\n";
const std::string health_close =
    "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: 3\r\n"
    "Connection: close\r\n\r\nok\n";
const std::string plaintext_keep_alive =
    "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: 14\r\n"
    "Connection: keep-alive\r\n\r\nHello, World!\n";
const std::string plaintext_close =
    "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: 14\r\n"
    "Connection: close\r\n\r\nHello, World!\n";
const std::string not_found_keep_alive =
    "HTTP/1.1 404 Not Found\r\nContent-Type: text/plain\r\nContent-Length: 10\r\n"
    "Connection: keep-alive\r\n\r\nNot Found\n";
const std::string not_found_close =
    "HTTP/1.1 404 Not Found\r\nContent-Type: text/plain\r\nContent-Length: 10\r\n"
    "Connection: close\r\n\r\nNot Found\n";
const std::string method_not_allowed =
    "HTTP/1.1 405 Method Not Allowed\r\nContent-Type: text/plain\r\nContent-Length: 19\r\n"
    "Connection: close\r\n\r\nMethod Not Allowed\n";
const std::string bad_request =
    "HTTP/1.1 400 Bad Request\r\nContent-Type: text/plain\r\nContent-Length: 12\r\n"
    "Connection: close\r\n\r\nBad Request\n";
const std::string header_too_large =
    "HTTP/1.1 431 Request Header Fields Too Large\r\nContent-Type: text/plain\r\n"
    "Content-Length: 25\r\nConnection: close\r\n\r\nRequest Header Too Large\n";

bool contains_connection_close(std::string_view request) {
    constexpr std::string_view header = "connection:";
    std::size_t line_start = request.find("\r\n") + 2;
    while (line_start < request.size()) {
        const std::size_t line_end = request.find("\r\n", line_start);
        if (line_end == std::string_view::npos || line_end == line_start) {
            break;
        }
        const std::string_view line = request.substr(line_start, line_end - line_start);
        if (line.size() >= header.size()
            && std::equal(header.begin(), header.end(), line.begin(), [](char left, char right) {
                   return static_cast<char>(std::tolower(static_cast<unsigned char>(left)))
                       == static_cast<char>(std::tolower(static_cast<unsigned char>(right)));
               })) {
            const std::string_view value = line.substr(header.size());
            return value.find("close") != std::string_view::npos
                || value.find("Close") != std::string_view::npos;
        }
        line_start = line_end + 2;
    }
    return false;
}

}  // namespace

HttpServer::HttpServer(ServerConfig config)
    : config_(std::move(config)), event_loop_(make_event_loop()) {
    events_.reserve(1024);
    open_listener();
}

HttpServer::~HttpServer() {
    for (const auto& [socket, connection] : connections_) {
        (void)connection;
        close_socket(socket);
    }
    close_socket(listener_);
}

void HttpServer::open_listener() {
    listener_ = ::socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
    if (listener_ == invalid_socket) {
        throw std::system_error(last_socket_error(), std::system_category(), "socket");
    }

    try {
        set_non_blocking(listener_);
        set_close_on_exec(listener_);

        const int enabled = 1;
        if (::setsockopt(listener_, SOL_SOCKET, SO_REUSEADDR,
#ifdef _WIN32
                         reinterpret_cast<const char*>(&enabled),
#else
                         &enabled,
#endif
                         sizeof(enabled)) != 0) {
            throw std::system_error(last_socket_error(), std::system_category(), "setsockopt(SO_REUSEADDR)");
        }

        sockaddr_in address{};
        address.sin_family = AF_INET;
        address.sin_port = htons(config_.port);
        if (::inet_pton(AF_INET, config_.host.c_str(), &address.sin_addr) != 1) {
            throw std::invalid_argument("host must be an IPv4 address");
        }

        if (::bind(listener_, reinterpret_cast<const sockaddr*>(&address), sizeof(address)) != 0) {
            throw std::system_error(last_socket_error(), std::system_category(), "bind");
        }
        if (::listen(listener_, config_.backlog) != 0) {
            throw std::system_error(last_socket_error(), std::system_category(), "listen");
        }
        event_loop_->add(listener_, true, false);
    } catch (...) {
        close_socket(listener_);
        listener_ = invalid_socket;
        throw;
    }
}

void HttpServer::run() {
    std::cout << "cpp20 listening on http://" << config_.host << ':' << config_.port << '\n';

    while (true) {
        event_loop_->wait(events_, -1);
        for (const Event& event : events_) {
            if (event.socket == listener_) {
                if (event.readable) {
                    accept_ready();
                }
                continue;
            }

            if (!connections_.contains(event.socket)) {
                continue;
            }

            if (event.readable) {
                read_ready(event.socket);
            }
            if (connections_.contains(event.socket) && event.writable) {
                write_ready(event.socket);
            }
            if (connections_.contains(event.socket) && event.error) {
                close_connection(event.socket);
            }
        }
    }
}

void HttpServer::accept_ready() {
    while (true) {
        sockaddr_in peer{};
#ifdef _WIN32
        int peer_size = sizeof(peer);
#else
        socklen_t peer_size = sizeof(peer);
#endif
        const NativeSocket socket = ::accept(
            listener_, reinterpret_cast<sockaddr*>(&peer), &peer_size);
        if (socket == invalid_socket) {
            const int error = last_socket_error();
            if (interrupted(error)) {
                continue;
            }
            if (would_block(error)) {
                return;
            }
            throw std::system_error(error, std::system_category(), "accept");
        }

        try {
            set_non_blocking(socket);
            set_close_on_exec(socket);
            set_tcp_no_delay(socket);
            connections_.try_emplace(socket);
            event_loop_->add(socket, true, false);
        } catch (...) {
            close_socket(socket);
        }
    }
}

void HttpServer::read_ready(NativeSocket socket) {
    auto iterator = connections_.find(socket);
    if (iterator == connections_.end()) {
        return;
    }
    Connection& connection = iterator->second;

    while (!connection.close_after_write) {
        const std::size_t remaining = connection.input.size() - connection.used;
        if (remaining == 0) {
            connection.output.push_back(PendingWrite{&header_too_large, 0});
            connection.close_after_write = true;
            break;
        }

        const std::ptrdiff_t received = receive_bytes(
            socket, connection.input.data() + connection.used, remaining);
        if (received > 0) {
            connection.used += static_cast<std::size_t>(received);
            parse_requests(connection);
            continue;
        }
        if (received == 0) {
            close_connection(socket);
            return;
        }

        const int error = last_socket_error();
        if (interrupted(error)) {
            continue;
        }
        if (would_block(error)) {
            break;
        }
        close_connection(socket);
        return;
    }

    if (connections_.contains(socket)) {
        update_interest(socket, connection);
    }
}

void HttpServer::parse_requests(Connection& connection) {
    std::size_t consumed = 0;
    while (!connection.close_after_write) {
        const std::string_view available(
            connection.input.data() + consumed, connection.used - consumed);
        const std::size_t header_end = available.find("\r\n\r\n");
        if (header_end == std::string_view::npos) {
            break;
        }

        enqueue_response(connection, available.substr(0, header_end + 2));
        consumed += header_end + 4;
    }

    if (consumed > 0) {
        const std::size_t remaining = connection.used - consumed;
        std::memmove(connection.input.data(), connection.input.data() + consumed, remaining);
        connection.used = remaining;
    }
}

void HttpServer::enqueue_response(Connection& connection, std::string_view request) {
    const std::size_t line_end = request.find("\r\n");
    if (line_end == std::string_view::npos) {
        connection.output.push_back(PendingWrite{&bad_request, 0});
        connection.close_after_write = true;
        return;
    }

    const std::string_view request_line = request.substr(0, line_end);
    if (!request_line.starts_with("GET ")) {
        connection.output.push_back(PendingWrite{&method_not_allowed, 0});
        connection.close_after_write = true;
        return;
    }

    const std::size_t target_end = request_line.find(' ', 4);
    if (target_end == std::string_view::npos || !request_line.substr(target_end).starts_with(" HTTP/1.1")) {
        connection.output.push_back(PendingWrite{&bad_request, 0});
        connection.close_after_write = true;
        return;
    }

    const std::string_view target = request_line.substr(4, target_end - 4);
    const bool close = contains_connection_close(request);
    const std::string* response = nullptr;
    if (target == "/health") {
        response = close ? &health_close : &health_keep_alive;
    } else if (target == "/plaintext") {
        response = close ? &plaintext_close : &plaintext_keep_alive;
    } else {
        response = close ? &not_found_close : &not_found_keep_alive;
    }

    connection.output.push_back(PendingWrite{response, 0});
    connection.close_after_write = close;
}

void HttpServer::write_ready(NativeSocket socket) {
    auto iterator = connections_.find(socket);
    if (iterator == connections_.end()) {
        return;
    }
    Connection& connection = iterator->second;

    while (!connection.output.empty()) {
        PendingWrite& pending = connection.output.front();
        const std::string& response = *pending.response;
        const std::ptrdiff_t sent = send_bytes(
            socket, response.data() + pending.offset, response.size() - pending.offset);
        if (sent > 0) {
            pending.offset += static_cast<std::size_t>(sent);
            if (pending.offset == response.size()) {
                connection.output.pop_front();
            }
            continue;
        }

        const int error = last_socket_error();
        if (interrupted(error)) {
            continue;
        }
        if (would_block(error)) {
            break;
        }
        close_connection(socket);
        return;
    }

    if (connection.output.empty() && connection.close_after_write) {
        close_connection(socket);
        return;
    }
    update_interest(socket, connection);
}

void HttpServer::update_interest(NativeSocket socket, const Connection& connection) {
    event_loop_->update(
        socket,
        !connection.close_after_write && connection.output.size() < 64,
        !connection.output.empty());
}

void HttpServer::close_connection(NativeSocket socket) noexcept {
    event_loop_->remove(socket);
    close_socket(socket);
    connections_.erase(socket);
}

}  // namespace httpbench
