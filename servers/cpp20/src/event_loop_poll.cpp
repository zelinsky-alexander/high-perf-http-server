#include "httpbench/event_loop.hpp"

#ifndef HTTPBENCH_HAS_EPOLL

#include <algorithm>
#include <cerrno>
#include <stdexcept>
#include <system_error>
#include <unordered_map>

#ifdef _WIN32
#include <winsock2.h>
#else
#include <poll.h>
#endif

namespace httpbench {
namespace {

#ifdef _WIN32
using PollDescriptor = WSAPOLLFD;
#else
using PollDescriptor = pollfd;
#endif

class PollEventLoop final : public EventLoop {
public:
    void add(NativeSocket socket, bool readable, bool writable) override {
        if (indices_.contains(socket)) {
            throw std::logic_error("socket already registered");
        }
        indices_.emplace(socket, descriptors_.size());
        descriptors_.push_back(make_descriptor(socket, readable, writable));
    }

    void update(NativeSocket socket, bool readable, bool writable) override {
        const auto iterator = indices_.find(socket);
        if (iterator == indices_.end()) {
            throw std::logic_error("socket is not registered");
        }
        descriptors_[iterator->second].events = requested_events(readable, writable);
    }

    void remove(NativeSocket socket) noexcept override {
        const auto iterator = indices_.find(socket);
        if (iterator == indices_.end()) {
            return;
        }

        const std::size_t removed = iterator->second;
        const std::size_t last = descriptors_.size() - 1;
        if (removed != last) {
            descriptors_[removed] = descriptors_[last];
            indices_[descriptors_[removed].fd] = removed;
        }
        descriptors_.pop_back();
        indices_.erase(iterator);
    }

    int wait(std::vector<Event>& events, int timeout_ms) override {
#ifdef _WIN32
        const int count = ::WSAPoll(
            descriptors_.data(), static_cast<ULONG>(descriptors_.size()), timeout_ms);
#else
        const int count = ::poll(
            descriptors_.data(), static_cast<nfds_t>(descriptors_.size()), timeout_ms);
#endif
        if (count < 0) {
            const int error = last_socket_error();
            if (interrupted(error)) {
                events.clear();
                return 0;
            }
            throw std::system_error(error, std::system_category(), "poll");
        }

        events.clear();
        events.reserve(static_cast<std::size_t>(count));
        for (auto& descriptor : descriptors_) {
            if (descriptor.revents == 0) {
                continue;
            }
            const short flags = descriptor.revents;
            events.push_back(Event{
                .socket = descriptor.fd,
                .readable = (flags & POLLIN) != 0,
                .writable = (flags & POLLOUT) != 0,
                .error = (flags & (POLLERR | POLLHUP | POLLNVAL)) != 0,
            });
            descriptor.revents = 0;
        }
        return count;
    }

private:
    static short requested_events(bool readable, bool writable) noexcept {
        short events = 0;
        if (readable) {
            events = static_cast<short>(events | POLLIN);
        }
        if (writable) {
            events = static_cast<short>(events | POLLOUT);
        }
        return events;
    }

    static PollDescriptor make_descriptor(
        NativeSocket socket, bool readable, bool writable) noexcept {
        PollDescriptor descriptor{};
        descriptor.fd = socket;
        descriptor.events = requested_events(readable, writable);
        return descriptor;
    }

    std::vector<PollDescriptor> descriptors_;
    std::unordered_map<NativeSocket, std::size_t> indices_;
};

}  // namespace

std::unique_ptr<EventLoop> make_event_loop() {
    return std::make_unique<PollEventLoop>();
}

}  // namespace httpbench

#endif
