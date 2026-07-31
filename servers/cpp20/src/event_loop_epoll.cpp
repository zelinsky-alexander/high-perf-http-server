#include "httpbench/event_loop.hpp"

#ifdef HTTPBENCH_HAS_EPOLL

#include <array>
#include <cerrno>
#include <stdexcept>
#include <system_error>

#include <sys/epoll.h>
#include <unistd.h>

namespace httpbench {
namespace {

class EpollEventLoop final : public EventLoop {
public:
    EpollEventLoop() : epoll_fd_(::epoll_create1(EPOLL_CLOEXEC)) {
        if (epoll_fd_ < 0) {
            throw std::system_error(errno, std::generic_category(), "epoll_create1");
        }
    }

    ~EpollEventLoop() override {
        ::close(epoll_fd_);
    }

    void add(NativeSocket socket, bool readable, bool writable) override {
        control(EPOLL_CTL_ADD, socket, readable, writable);
    }

    void update(NativeSocket socket, bool readable, bool writable) override {
        control(EPOLL_CTL_MOD, socket, readable, writable);
    }

    void remove(NativeSocket socket) noexcept override {
        ::epoll_ctl(epoll_fd_, EPOLL_CTL_DEL, socket, nullptr);
    }

    int wait(std::vector<Event>& events, int timeout_ms) override {
        std::array<epoll_event, 1024> native_events{};
        const int count = ::epoll_wait(
            epoll_fd_, native_events.data(), static_cast<int>(native_events.size()), timeout_ms);
        if (count < 0) {
            if (errno == EINTR) {
                events.clear();
                return 0;
            }
            throw std::system_error(errno, std::generic_category(), "epoll_wait");
        }

        events.clear();
        events.reserve(static_cast<std::size_t>(count));
        for (int index = 0; index < count; ++index) {
            const auto flags = native_events[static_cast<std::size_t>(index)].events;
            events.push_back(Event{
                .socket = static_cast<NativeSocket>(native_events[static_cast<std::size_t>(index)].data.fd),
                .readable = (flags & EPOLLIN) != 0,
                .writable = (flags & EPOLLOUT) != 0,
                .error = (flags & (EPOLLERR | EPOLLHUP | EPOLLRDHUP)) != 0,
            });
        }
        return count;
    }

private:
    void control(int operation, NativeSocket socket, bool readable, bool writable) {
        epoll_event event{};
        event.data.fd = socket;
        event.events = EPOLLRDHUP;
        if (readable) {
            event.events |= EPOLLIN;
        }
        if (writable) {
            event.events |= EPOLLOUT;
        }
        if (::epoll_ctl(epoll_fd_, operation, socket, &event) != 0) {
            throw std::system_error(errno, std::generic_category(), "epoll_ctl");
        }
    }

    int epoll_fd_;
};

}  // namespace

std::unique_ptr<EventLoop> make_event_loop() {
    return std::make_unique<EpollEventLoop>();
}

}  // namespace httpbench

#endif
