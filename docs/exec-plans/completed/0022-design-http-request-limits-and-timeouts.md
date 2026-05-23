# Design HTTP Request Limits And Timeouts

## Status

Completed

## Objective

Design and implement HTTP/1.1 request-line/header-size limits and slowloris
mitigation for Camelio's Eio server.

## Context

- [Minimal HTTP/1.1 Server Milestone](../../product-specs/minimal-http1-server.md)
- [Minimal Server API](../../product-specs/minimal-server-api.md)
- [Minimal Server, Handler, and Middleware API](../../design-docs/minimal-server-handler-middleware-api.md)
- [Streaming Request Bodies](../../design-docs/streaming-request-bodies.md)
- [Future Work](../../design-docs/future-work.md)
- [Add HTTP Security Regression Tests](../completed/0021-add-http-security-regression-tests.md)

## Clarifications

- Continue from the security regression work.
- Implement limits after documenting public behavior and the Eio timeout
  strategy.
- Deferred topics for upload storage, generic pre-body selection, and router
  follow-ups are recorded in `docs/design-docs/future-work.md`.
- Use optional `?mono_clock` on `Server.run` for timeout enforcement.

## Contract First

- Add `?max_request_head_size:int` to `Server.create` and
  `Server.create_router`.
- Add `?request_head_timeout:float option` to `Server.create` and
  `Server.create_router`.
- Add optional `?mono_clock:_ Eio.Time.Mono.t` to `Server.run`.
- Add HTTP/1 errors for request-head size limit and timeout, mapped to 431 and
  408 respectively.

## Steps

- [x] Record deferred topics for later design.
- [x] Explore: inspect Eio timeout APIs and current request-head read loop.
- [x] Draft design doc for limits, timeout semantics, defaults, and validation.
- [x] Red: add HTTP/1 and server tests for head limits and timeout behavior.
- [x] Green: implement request-head limits and optional timeout support.
- [x] Refactor: keep read loop and configuration validation simple.
- [x] Static checks: run formatter and focused/full checks.
- [x] Code review: not delegated unless explicitly requested by the user.
- [x] Completion: move plan to completed and commit.

## Decisions

- `max_request_head_size` defaults to `65_536` and rejects non-positive values.
- `request_head_timeout` defaults to `None` for source-compatible
  implementation in this milestone; applications can opt in with
  `Some seconds`.
- Timeout enforcement uses `Eio.Time.Mono.t` through optional
  `Server.run ?mono_clock`.

## Verification

- `dune build @fmt`
- `dune exec test/test_http1.exe`
- `dune exec test/test_server.exe`
- `CAMELIO_RUN_NETWORK_TESTS=1 dune exec test/test_server.exe`
- `dune build @all`
- `dune runtest`
- `dune build @check`
- `dune build @install`
- `opam lint camelio.opam`

## Completion Notes

Implemented bounded HTTP/1.1 request-head reading with
`max_request_head_size`, 431 responses for oversized heads, and opt-in
`request_head_timeout` enforced with `Server.run ?mono_clock`. Timeout
expiration returns 408 before handler invocation. Defaults preserve source
compatibility: head size is bounded by default and timeout is disabled unless
configured.

## Commit

`feat: add request head limits`
