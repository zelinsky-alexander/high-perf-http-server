package main

import (
    "errors"
    "flag"
    "fmt"
    "log"
    "net"
    "net/http"
    "os"
    "os/signal"
    "strconv"
    "syscall"
    "time"
)

var (
    healthBody    = []byte("ok\n")
    plaintextBody = []byte("Hello, World!\n")
    notFoundBody  = []byte("Not Found\n")
    methodBody    = []byte("Method Not Allowed\n")
)

func main() {
    host := flag.String("host", "127.0.0.1", "listen host")
    port := flag.Int("port", 8080, "listen port")
    readHeaderTimeout := flag.Duration("read-header-timeout", 10*time.Second, "maximum time to read request headers")
    idleTimeout := flag.Duration("idle-timeout", 60*time.Second, "HTTP keep-alive idle timeout")
    flag.Parse()

    if *port < 1 || *port > 65535 {
        log.Fatalf("port must be between 1 and 65535: %d", *port)
    }

    handler := http.HandlerFunc(handleRequest)
    server := &http.Server{
        Addr:              net.JoinHostPort(*host, strconv.Itoa(*port)),
        Handler:           handler,
        ReadHeaderTimeout: *readHeaderTimeout,
        IdleTimeout:       *idleTimeout,
        MaxHeaderBytes:     16 * 1024,
    }

    listener, err := net.Listen("tcp", server.Addr)
    if err != nil {
        log.Fatalf("listen on %s: %v", server.Addr, err)
    }

    fmt.Printf("go-nethttp listening on http://%s\n", server.Addr)

    stop := make(chan os.Signal, 1)
    signal.Notify(stop, os.Interrupt, syscall.SIGTERM)

    serveDone := make(chan error, 1)
    go func() {
        serveDone <- server.Serve(listener)
    }()

    select {
    case sig := <-stop:
        fmt.Printf("received %s, shutting down\n", sig)
        _ = server.Close()
        err = <-serveDone
    case err = <-serveDone:
    }

    if err != nil && !errors.Is(err, http.ErrServerClosed) {
        log.Fatalf("server failed: %v", err)
    }
}

func handleRequest(w http.ResponseWriter, r *http.Request) {
    if r.Method != http.MethodGet {
        writeResponse(w, http.StatusMethodNotAllowed, "text/plain", methodBody)
        return
    }

    switch r.URL.Path {
    case "/health":
        writeResponse(w, http.StatusOK, "text/plain", healthBody)
    case "/plaintext":
        writeResponse(w, http.StatusOK, "text/plain", plaintextBody)
    default:
        writeResponse(w, http.StatusNotFound, "text/plain", notFoundBody)
    }
}

func writeResponse(w http.ResponseWriter, status int, contentType string, body []byte) {
    header := w.Header()
    header.Set("Content-Type", contentType)
    header.Set("Content-Length", strconv.Itoa(len(body)))
    w.WriteHeader(status)
    _, _ = w.Write(body)
}
