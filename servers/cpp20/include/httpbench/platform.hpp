#pragma once

#include <cerrno>
#include <cstddef>
#include <cstdint>
#include <stdexcept>
#include <string>
#include <system_error>

#ifdef _WIN32
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <winsock2.h>
#include <ws2tcpip.h>
#else
#include <arpa/inet.h>
#include <fcntl.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <sys/socket.h>
#include <unistd.h>
#endif

namespace httpbench {

#ifdef _WIN32
using NativeSocket = SOCKET;
inline constexpr NativeSocket invalid_socket = INVALID_SOCKET;
#else
using NativeSocket = int;
inline constexpr NativeSocket invalid_socket = -1;
#endif

class NetworkRuntime final {
public:
    NetworkRuntime() {
#ifdef _WIN32
        WSADATA data{};
        const int result = ::WSAStartup(MAKEWORD(2, 2), &data);
        if (result != 0) {
            throw std::system_error(result, std::system_category(), "WSAStartup");
        }
#endif
    }

    ~NetworkRuntime() {
#ifdef _WIN32
        ::WSACleanup();
#endif
    }

    NetworkRuntime(const NetworkRuntime&) = delete;
    NetworkRuntime& operator=(const NetworkRuntime&) = delete;
};

inline int last_socket_error() noexcept {
#ifdef _WIN32
    return ::WSAGetLastError();
#else
    return errno;
#endif
}

inline bool would_block(int error) noexcept {
#ifdef _WIN32
    return error == WSAEWOULDBLOCK;
#else
    return error == EAGAIN || error == EWOULDBLOCK;
#endif
}

inline bool interrupted(int error) noexcept {
#ifdef _WIN32
    return error == WSAEINTR;
#else
    return error == EINTR;
#endif
}

inline void close_socket(NativeSocket socket) noexcept {
    if (socket == invalid_socket) {
        return;
    }
#ifdef _WIN32
    ::closesocket(socket);
#else
    ::close(socket);
#endif
}

inline void set_non_blocking(NativeSocket socket) {
#ifdef _WIN32
    u_long enabled = 1;
    if (::ioctlsocket(socket, FIONBIO, &enabled) != 0) {
        throw std::system_error(last_socket_error(), std::system_category(), "ioctlsocket");
    }
#else
    const int flags = ::fcntl(socket, F_GETFL, 0);
    if (flags < 0 || ::fcntl(socket, F_SETFL, flags | O_NONBLOCK) < 0) {
        throw std::system_error(errno, std::generic_category(), "fcntl(O_NONBLOCK)");
    }
#endif
}

inline void set_close_on_exec(NativeSocket socket) {
#ifndef _WIN32
    const int flags = ::fcntl(socket, F_GETFD, 0);
    if (flags < 0 || ::fcntl(socket, F_SETFD, flags | FD_CLOEXEC) < 0) {
        throw std::system_error(errno, std::generic_category(), "fcntl(FD_CLOEXEC)");
    }
#else
    (void)socket;
#endif
}

inline void set_tcp_no_delay(NativeSocket socket) {
    const int enabled = 1;
    if (::setsockopt(socket, IPPROTO_TCP, TCP_NODELAY,
#ifdef _WIN32
                     reinterpret_cast<const char*>(&enabled),
#else
                     &enabled,
#endif
                     sizeof(enabled)) != 0) {
        throw std::system_error(last_socket_error(), std::system_category(), "setsockopt(TCP_NODELAY)");
    }
}

inline std::ptrdiff_t receive_bytes(NativeSocket socket, void* data, std::size_t size) noexcept {
#ifdef _WIN32
    return ::recv(socket, static_cast<char*>(data), static_cast<int>(size), 0);
#else
    return ::recv(socket, data, size, 0);
#endif
}

inline std::ptrdiff_t send_bytes(NativeSocket socket, const void* data, std::size_t size) noexcept {
#ifdef _WIN32
    return ::send(socket, static_cast<const char*>(data), static_cast<int>(size), 0);
#else
    return ::send(socket, data, size, MSG_NOSIGNAL);
#endif
}

}  // namespace httpbench
