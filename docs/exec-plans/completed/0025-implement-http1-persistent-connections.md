# Implement HTTP/1.1 Persistent Connections

## Status

Completed

## Objective

Implement minimal HTTP/1.1 persistent connection support so Choku can serve as a
simple application server behind nginx, ALB, ELB, or similar reverse proxies
without adding edge-server features.

## Context

- [HTTP/1.1 Persistent Connections](../../product-specs/http1-persistent-connections.md)
- [HTTP/1.1 Persistent Connections Design](../../design-docs/http1-persistent-connections.md)
- [Minimal HTTP/1.1 Server Milestone](../../product-specs/minimal-http1-server.md)
- [HTTP Request Limits And Timeouts](../../design-docs/http-request-limits-and-timeouts.md)
- [HTTP/1.1 Chunked Request Bodies](../../design-docs/http1-chunked-request-bodies.md)

## Clarifications

- Target backend application-server behavior, not nginx-like edge-server
  completeness.
- Keep request handling sequential per connection.
- Do not add chunked responses, response streaming, upgrades, TLS, HTTP/2, or
  HTTP/3.
- Use `request_head_timeout` as the keep-alive idle bound for this milestone.
- EOF before any bytes of the next request is a graceful connection close, not
  a 400.

## Contract First

- Add `?keep_alive:bool` to `Server.create` and `Server.create_router`, default
  `true`.
- Update `Server.run` docs to state that a connection may handle multiple
  sequential requests.
- Extend `Http1.serialize_response` so the server can choose `Connection:
  keep-alive` or `Connection: close`.
- Parse `Connection` as case-insensitive comma-separated tokens across repeated
  fields.

## Steps

- [x] Explore: inspect current close-oriented server loop, request reading,
      chunked body prefix handling, docs, and tests.
- [x] Design review: request context-free third-party review and incorporate
      feedback.
- [x] Red: add network tests for shared-connection GETs, HEAD reuse, fixed and
      chunked POST reuse, pipelined bytes after a body in one socket read,
      `Connection: close` token variants, `~keep_alive:false`, graceful EOF,
      error close, streaming close, and idle timeout before second request.
- [x] Green: implement the smallest persistent connection loop and connection
      reader changes that satisfy tests.
- [x] Refactor: isolate connection decision logic and keep fixed/chunked body
      readers explicit.
- [x] Static checks: run formatters, focused tests, full tests, and install/lint
      checks.
- [x] Code review: request context-free third-party review after implementation.
- [x] Re-review: fix review findings and repeat review until it passes.

## Decisions

- `keep_alive` defaults to `true`.
- Streaming request body responses close the connection.
- `request_head_timeout` applies to each request head, including idle time
  between keep-alive requests.
- No public request count or keep-alive idle timeout setting is added yet.
- Direct deployments should configure `request_head_timeout` because keep-alive
  defaults to enabled while timeout defaults remain source-compatible.

## Verification

Passed:

- `dune build @fmt`
- `dune exec test/test_http1.exe`
- `dune exec test/test_server.exe`
- `CHOKU_RUN_NETWORK_TESTS=1 dune exec test/test_server.exe`
- `dune runtest`
- `dune build @all`
- `dune build @check`
- `dune build @install`
- `opam lint choku.opam`

## Completion Notes

Implemented minimal HTTP/1.1 persistent connections for buffered requests.
Connections are reusable by default, can be disabled with `~keep_alive:false`,
and close conservatively for `Connection: close`, errors, and streaming request
bodies. A connection-local reader preserves pipelined bytes after headers,
fixed-length bodies, and chunked bodies.

Design review passed after clarifying graceful EOF, connection-token parsing,
and direct-deployment timeout guidance. Code review passed with two low-severity
test gaps; regression tests were added for response-side repeated/comma
`Connection: close` tokens and partial next-request EOF.

## Commit

`feat: support http1 persistent connections`
