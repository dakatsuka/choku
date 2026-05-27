# Testing Support

## Status

Accepted

## Context

Choku applications need several test shapes:

- pure handler/router/middleware unit tests;
- client middleware tests with fake outbound handlers;
- loopback server/client tests that exercise actual HTTP/1.1 framing;
- raw-wire regression tests for protocol behavior.

Existing public contracts already make pure tests possible. `Server.handle`
invokes the composed handler with a constructed `Request.t`.
`Client.Middleware.apply` works over a public `Client.Handler.t`.
`Client.Response.make` lets tests synthesize responses without a network
transport.

The unstable area is loopback system tests. A harness should be able to bind an
Eio listener to port `0`, discover the actual address, then start the server on
that listener. The current `Server.run` combines binding and serving, so callers
that need the selected port must either guess an available port first or write
their own server loop.

## Goals

- Add a small, framework-neutral `choku.test` library.
- Keep the core `choku` library free of test-framework dependencies.
- Expose a listener-based server run entry point that is useful for test
  harnesses and advanced embedders.
- Keep the test helpers thin wrappers over public Choku contracts.
- Avoid exposing parser internals as user test APIs.

## Non-Goals

- Replacing application test frameworks.
- Providing protocol parser fixtures or internal parser access.
- Supporting TLS fixture generation in this milestone.
- Designing an HTTP mock server DSL.

## Proposed Design

Add a `choku.test` public library whose OCaml module is `Choku_test`.

The library provides:

- request construction defaults for handler tests;
- response body accessors for server and client response values;
- a streaming body helper for exercising streaming handlers without opening a
  socket;
- a raw request helper for wire-level system tests;
- `with_server`, a loopback server harness that creates an Eio listening
  socket before forking the Choku server.

Add `Server.run_listener` to the core server module:

```ocaml
val run_listener :
  sw:Eio.Switch.t ->
  ?mono_clock:Eio.Time.Mono.ty Eio.Resource.t ->
  socket:_ Eio.Net.listening_socket ->
  t ->
  unit
```

`run_listener` uses the same connection loop and timeout validation as
`Server.run`, but accepts an existing listening socket. `Server.run` becomes a
thin wrapper that calls `Eio.Net.listen` and then `run_listener`.

`Choku_test.with_server` creates a listener with `Eio.Net.listen`, calls
`Eio.Net.listening_addr` to discover the actual socket address, forks
`Server.run_listener`, and runs the user callback under the same switch. When
the callback returns or raises, the switch closes the listener and cancels the
server fiber.

`Choku_test.streaming_body` uses Choku's internal body constructor inside the
test-support library. This keeps the internal constructor out of ordinary
application code while giving tests a stable way to exercise streaming
handlers.

## Contracts

`Choku_test.request` defaults to:

- `meth = Choku.Method.GET`;
- `target = "/"`;
- `headers = Choku.Headers.empty`;
- `body = Choku.Body.empty`.

It delegates validation to `Choku.Request.make`.

`Choku_test.streaming_body ?content_length bytes` returns a single-consumption
body. If `content_length` is omitted, the helper uses the byte length. If
`content_length` is shorter than the bytes, consumers see only the declared
number of bytes through the source cap. If it is longer, consumers that require
the declared length receive the normal Choku streaming-body error.

`Choku_test.raw_request` opens one client connection, writes the supplied bytes,
shuts down the write side, reads until EOF, and returns the raw response bytes.

`Choku_test.with_server` defaults to a TCP IPv4 loopback listener on port `0`.
It raises `Invalid_argument` when asked to produce a base URL for a Unix-domain
listener.

## Alternatives Considered

- Put test helpers in `Choku.Test`: rejected because Choku's main public module
  should not grow test-only API surface for production users.
- Depend on Alcotest directly: rejected because users may prefer OUnit,
  ppx_expect, custom runners, or inline tests.
- Keep only documentation and no helpers: rejected because loopback server
  lifecycle code is easy to get subtly wrong.
- Add a full mock transport layer: rejected for now because public client
  handlers already make most client policy tests straightforward.

## Third-Party Review

The implementation plan requested context-free design review and incorporated
feedback before implementation. Code review found two medium-severity issues in
streaming test-body caps and `Server.run_listener` switch usage; both were
fixed before completion.

## Validation

- Add focused unit tests for request defaults, response body helpers, and
  streaming body consumption.
- Add a gated network test for `with_server` using `Choku.Client.request`.
- Add a gated raw-wire test for `raw_request`.
- Run `dune build @fmt`, the focused test executable, and `dune runtest`.

## Open Questions

- Whether to add a separate `choku.test.alcotest` library for testable values.
- Whether `Server.run_listener` should eventually accept server-run options such
  as backlog or max connection count.
