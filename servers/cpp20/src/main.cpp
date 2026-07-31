#include "httpbench/server.hpp"

#include <charconv>
#include <cstdint>
#include <exception>
#include <iostream>
#include <stdexcept>
#include <string>
#include <string_view>

namespace {

int parse_positive_int(std::string_view value, std::string_view name) {
    int parsed = 0;
    const auto result = std::from_chars(value.data(), value.data() + value.size(), parsed);
    if (result.ec != std::errc{} || result.ptr != value.data() + value.size() || parsed <= 0) {
        throw std::invalid_argument(std::string(name) + " must be a positive integer");
    }
    return parsed;
}

httpbench::ServerConfig parse_arguments(int argc, char** argv) {
    httpbench::ServerConfig config;
    for (int index = 1; index < argc; ++index) {
        const std::string_view option = argv[index];
        auto require_value = [&]() -> std::string_view {
            if (++index >= argc) {
                throw std::invalid_argument("missing value for " + std::string(option));
            }
            return argv[index];
        };

        if (option == "--host") {
            config.host = require_value();
        } else if (option == "--port") {
            const int port = parse_positive_int(require_value(), "port");
            if (port > 65535) {
                throw std::invalid_argument("port must be <= 65535");
            }
            config.port = static_cast<std::uint16_t>(port);
        } else if (option == "--backlog") {
            config.backlog = parse_positive_int(require_value(), "backlog");
        } else if (option == "--help") {
            std::cout << "Usage: cpp20-http-server [--host ADDRESS] [--port PORT] [--backlog N]\n";
            std::exit(0);
        } else {
            throw std::invalid_argument("unknown argument: " + std::string(option));
        }
    }
    return config;
}

}  // namespace

int main(int argc, char** argv) {
    try {
        httpbench::HttpServer server(parse_arguments(argc, argv));
        server.run();
        return 0;
    } catch (const std::exception& exception) {
        std::cerr << "cpp20-http-server: " << exception.what() << '\n';
        return 1;
    }
}
