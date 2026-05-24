# Implement Route-Level Body Mode

## Status

Completed

## Objective

Implement route-level request body delivery mode selection for router-backed
servers.

## Context

- [Route-Level Body Mode](../../design-docs/route-level-body-mode.md)
- [Streaming Request Bodies](../../design-docs/streaming-request-bodies.md)
- [Minimal Router DSL](../../product-specs/minimal-router-dsl.md)
- [Design Route-Level Body Mode](../completed/0019-design-route-level-body-mode.md)

## Clarifications

- Proceed with implementation after the design/review phase.

## Contract First

- Add `Request_body_mode.t = Buffered | Streaming`.
- Keep `Server.request_body_mode` as a compatibility alias.
- Add optional `?request_body_mode` to `Router.route` and method helpers.
- Add `Server.create_router`.
- Keep `Router.to_handler` and `Server.handle` behavior compatible for
  already-built requests.

## Steps

- [x] Explore: inspect server, router, HTTP/1.1 request reading, and tests.
- [x] Red: add focused router/server tests for route-level body mode.
- [x] Green: implement shared body mode, router metadata, and server selection.
- [x] Refactor: keep internal matcher parity with `Router.to_handler`.
- [x] Static checks: run formatter and full checks.
- [x] Code review: request context-free review, fix findings, and re-review.
- [x] Completion: move plan to completed and commit.

## Decisions

- Expose a hidden `Router.Internal` matcher for server integration instead of
  duplicating matcher logic in `Server`.
- Keep the internal matcher metadata-only so route handler code is not invoked
  before request body delivery.
- Keep unmatched router requests buffered and subject to the existing
  `max_request_body_size` rejection behavior.

## Verification

- `dune build @fmt`
- `dune exec test/test_router.exe`
- `dune exec test/test_server.exe`
- `CHOKU_RUN_NETWORK_TESTS=1 dune exec test/test_server.exe`
- `dune build @all`
- `dune runtest`
- `dune build @check`
- `dune build @install`
- `opam lint choku.opam`

## Completion Notes

Implemented route-level request body mode for router-backed servers.
Applications can use `Server.create_router` and set
`~request_body_mode:Request_body_mode.Streaming` on upload routes while leaving
other routes buffered. Existing direct `Server.create` and `Router.to_handler`
workflows remain compatible.

Context-free review found two issues: the internal matcher originally applied
route handlers too early, and router-backed multipart streaming lacked
end-to-end coverage. Both were fixed and re-reviewed with no blocking findings.

## Commit

`feat: add route-level body mode`
