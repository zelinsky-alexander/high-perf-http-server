cmake_minimum_required(VERSION 3.22)
project(cpp20_http_server VERSION 0.1.0 LANGUAGES CXX)

option(HTTPBENCH_WARNINGS_AS_ERRORS "Treat compiler warnings as errors" OFF)

add_executable(cpp20-http-server
    src/main.cpp
    src/server.cpp
    src/event_loop_poll.cpp
)

if(CMAKE_SYSTEM_NAME STREQUAL "Linux")
    target_sources(cpp20-http-server PRIVATE src/event_loop_epoll.cpp)
    target_compile_definitions(cpp20-http-server PRIVATE HTTPBENCH_HAS_EPOLL=1)
endif()

target_include_directories(cpp20-http-server PRIVATE include)
target_compile_features(cpp20-http-server PRIVATE cxx_std_20)

if(MSVC)
    target_compile_options(cpp20-http-server PRIVATE /W4 /permissive-)
    if(HTTPBENCH_WARNINGS_AS_ERRORS)
        target_compile_options(cpp20-http-server PRIVATE /WX)
    endif()
    target_link_libraries(cpp20-http-server PRIVATE ws2_32)
else()
    target_compile_options(cpp20-http-server PRIVATE -Wall -Wextra -Wpedantic)
    if(HTTPBENCH_WARNINGS_AS_ERRORS)
        target_compile_options(cpp20-http-server PRIVATE -Werror)
    endif()
endif()

install(TARGETS cpp20-http-server RUNTIME DESTINATION bin)
