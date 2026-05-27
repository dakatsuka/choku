# Add Testing Support

## Status

Completed

## Objective

Add a small official test-support surface for Choku applications, including a
listener-based server run entry point and a framework-neutral `choku.test`
library.

## Context

- [Testing Support Product Spec](../../product-specs/testing-support.md)
- [Testing Support Design](../../design-docs/testing-support.md)
- [Minimal Server API](../../product-specs/minimal-server-api.md)
- [Minimal HTTP Client](../../product-specs/minimal-http-client.md)

## Clarifications

- The user accepted the direction of adding official testing support.
- Keep the first implementation small and framework-neutral.
- Do not add Alcotest as a runtime dependency of Choku or `choku.test`.

## Contract First

- Add `Server.run_listener`.
- Add `choku.test` with OCaml module `Choku_test`.
- Add `Choku_test.request`.
- Add `Choku_test.response_body_string`.
- Add `Choku_test.client_response_body_string`.
- Add `Choku_test.streaming_body`.
- Add `Choku_test.raw_request`.
- Add `Choku_test.with_server`.

## Steps

- [x] Explore: inspect existing docs, Dune layout, server run loop, client
      tests, and server tests.
- [x] Design review: request context-free third-party review and incorporate
      feedback.
- [x] Red: write failing behavior-focused tests for the test-support API.
- [x] Green: implement the smallest change that satisfies the tests.
- [x] Refactor: improve structure while keeping tests green.
- [x] Static checks: run formatters and static analysis tools, then fix
      findings.
- [x] Code review: request context-free third-party review after implementation.
- [x] Re-review: fix review findings and repeat review until it passes.

## Decisions

- Use a separate `choku.test` library instead of adding test-only helpers to
  the main `Choku` module.
- Add `Server.run_listener` so harnesses can bind port `0` and discover the
  selected port before serving.
- Keep framework-specific assertions out of the first helper library.
- `Choku_test.streaming_body` caps its source to the declared content length so
  both `Body.to_string_limited` and `Body.with_source` observe the same
  declared-length contract.
- `Server.run_listener` runs the server loop under the supplied Eio switch and
  propagates server-loop exceptions to the caller.

## Verification

- `dune build @fmt`
- `dune exec test/test_choku_test.exe`
- `CHOKU_RUN_NETWORK_TESTS=1 dune exec test/test_choku_test.exe`
- `dune runtest`
- `dune build @all`

## Completion Notes

Added a framework-neutral `choku.test` library with request construction,
response body, streaming body, raw request, and loopback server harness helpers.
Added `Server.run_listener` and made `Server.run` delegate to it. Added focused
tests for pure helper behavior and gated loopback tests for `with_server` and
`raw_request`.

Context-free review found two medium-severity issues: streaming test bodies did
not cap `Body.with_source` reads to a shorter declared content length, and
`Server.run_listener` accepted but did not use the supplied switch. Both were
fixed and re-reviewed. Re-review reported no blocking findings and one low
severity suggestion for future direct lifecycle coverage of standalone
`Server.run_listener` cancellation.

## Commit

`feat: add testing support helpers`
