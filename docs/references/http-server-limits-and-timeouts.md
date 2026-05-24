# HTTP Server Limits And Timeouts

## Source

- Go `net/http` package documentation:
  https://pkg.go.dev/net/http
- Node.js HTTP server documentation:
  https://nodejs.org/api/http.html
- Eio `Time.Timeout` documentation:
  https://ocaml.org/p/eio/latest/doc/Eio/Time/Timeout/index.html
- Accessed: 2026-05-24

## Summary

HTTP server implementations commonly expose separate controls for header size
and request-read timeouts.

Go's `net/http.Server` exposes request-read timeout settings and a
`MaxHeaderBytes` setting. Its request parsing APIs also distinguish streaming
multipart processing from whole-body multipart parsing.

Node.js exposes `maxHeaderSize`, `headersTimeout`, `requestTimeout`, and
`maxHeadersCount`. Its documentation states that header timeout expiration
returns 408 without forwarding the request to the handler, then closes the
connection.

Eio exposes `Eio.Time.Timeout.t`, including `Timeout.none`,
`Timeout.seconds`, and `Timeout.run`, which runs a function and cancels it with
`` `Timeout`` if the duration expires.

## Implications

Choku should treat header-size limits and header-read timeout as protocol
layer controls, not middleware. They must apply before constructing
`Request.t`, before route-level body-mode selection, and before invoking user
handlers.

Default limits should be conservative enough to prevent unbounded memory growth
and slowloris-style header reads, while still being configurable on
`Server.create` and `Server.create_router`.
