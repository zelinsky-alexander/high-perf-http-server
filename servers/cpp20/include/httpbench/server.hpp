#pragma once

#include <array>
#include <cstddef>
#include <cstdint>
#include <deque>
#include <memory>
#include <string>
#include <string_view>
#include <unordered_map>
#include <vector>

#include "httpbench/event_loop.hpp"
#include "httpbench/platform.hpp"

namespace httpbench {

struct ServerConfig final {
    std::string host{"127.0.0.1"};
    std::uint16_t port{8080};
    int backlog{1024};
};

class HttpServer final {
public:
    explicit HttpServer(ServerConfig config);
    ~HttpServer();

    HttpServer(const HttpServer&) = delete;
    HttpServer& operator=(const HttpServer&) = delete;

    void run();

private:
    static constexpr std::size_t input_capacity = 16 * 1024;

    struct PendingWrite final {
        const std::string* response{nullptr};
        std::size_t offset{0};
    };

    struct Connection final {
        std::array<char, input_capacity> input{};
        std::size_t used{0};
        std::deque<PendingWrite> output;
        bool close_after_write{false};
    };

    void open_listener();
    void accept_ready();
    void read_ready(NativeSocket socket);
    void write_ready(NativeSocket socket);
    void parse_requests(Connection& connection);
    void enqueue_response(Connection& connection, std::string_view request);
    void update_interest(NativeSocket socket, const Connection& connection);
    void close_connection(NativeSocket socket) noexcept;

    ServerConfig config_;
    NetworkRuntime network_runtime_;
    std::unique_ptr<EventLoop> event_loop_;
    NativeSocket listener_{invalid_socket};
    std::unordered_map<NativeSocket, Connection> connections_;
    std::vector<Event> events_;
};

}  // namespace httpbench
