#pragma once

#include <cstdint>
#include <memory>
#include <vector>

#include "httpbench/platform.hpp"

namespace httpbench {

struct Event final {
    NativeSocket socket{invalid_socket};
    bool readable{false};
    bool writable{false};
    bool error{false};
};

class EventLoop {
public:
    virtual ~EventLoop() = default;

    virtual void add(NativeSocket socket, bool readable, bool writable) = 0;
    virtual void update(NativeSocket socket, bool readable, bool writable) = 0;
    virtual void remove(NativeSocket socket) noexcept = 0;
    virtual int wait(std::vector<Event>& events, int timeout_ms) = 0;
};

std::unique_ptr<EventLoop> make_event_loop();

}  // namespace httpbench
