# Implement Generic Pre-Body Selector

## Status

Completed

## Objective

Implement the public generic pre-body request body-mode selector API for
handler-backed servers.

## Context

- [Generic Pre-Body Selector](../../product-specs/generic-pre-body-selector.md)
- [Generic Pre-Body Selector Design](../../design-docs/generic-pre-body-selector.md)
- [Design Generic Pre-Body Selector](../completed/0029-design-generic-pre-body-selector.md)
- [Route-Level Body Mode](../../design-docs/route-level-body-mode.md)

## Clarifications

- Keep `Server.create` and `Server.create_router` source-compatible.
- Keep `Handler.t = Request.t -> Response.t`.
- Do not add routing, per-route limits, or middleware-time body-mode selection.

## Contract First

- Add public `Request_head.t` with method, target, path, and headers.
- Export `Request_head` through `Choku.Request_head`.
- Add `Server.create_with_request_body_selector`.
- Catch non-cancellation selector exceptions before body reads and return
  500/close, with normal HEAD body suppression.

## Steps

- [x] Explore: inspect request target validation, server body-mode selection,
      router integration, and tests.
- [x] Red: add focused unit and server tests for the new public API and
      selector failure behavior.
- [x] Green: implement `Request_head` and selector-backed server creation.
- [x] Refactor: keep the server read path explicit and preserve existing router
      behavior.
- [x] Static checks: run formatter and targeted/full test commands.
- [x] Code review: request context-free review, fix findings, and re-review.
- [x] Completion: move plan to completed and commit.

## Decisions

- Use a separate constructor instead of overloading `Server.create`.
- Model selector failure as an explicit pre-body read result rather than as a
  handler exception.
- Validate request body framing headers before selector invocation so malformed
  framing does not call application selector code.

## Verification

Passed:

- `dune build @fmt`
- `dune exec test/test_request_head.exe`
- `CHOKU_RUN_NETWORK_TESTS=1 dune exec test/test_server.exe`
- `dune runtest`
- `dune build @all`
- `dune build @check`
- `dune build @install`
- `opam lint choku.opam`

## Completion Notes

Implemented `Request_head.t` and exported it through `Choku.Request_head`.
Added `Server.create_with_request_body_selector` for handler-backed servers
that need to select buffered or streaming request bodies from request-head
metadata before body delivery.

The server read path now models body-mode selection as an explicit decision.
Non-cancellation selector exceptions become a pre-body 500/close response, with
normal HEAD body suppression. `Eio.Cancel.Cancelled _` still propagates.
Existing `Server.create`, `Server.create_router`, and `Server.handle` behavior
remains compatible.

Context-free code review passed with no blocking findings.

## Commit

`feat: add generic pre-body selector`
