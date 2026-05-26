# Add Client Convenience Helpers

## Status

Completed

## Objective

Add thin `Choku.Client` convenience helpers that construct a client request and
send it without changing existing `Client.Request.make` or `Client.request`
semantics.

## Context

- [Minimal HTTP Client Product Spec](../../product-specs/minimal-http-client.md)
- [Minimal HTTP Client Design](../../design-docs/minimal-http-client.md)
- [HTTPS Client Product Spec](../../product-specs/https-client.md)
- [HTTPS Client Design](../../design-docs/https-client.md)

## Clarifications

- Keep `Client.Request.make` plus `Client.request` as the canonical explicit
  API.
- Add helpers only as thin wrappers; do not add new method/body, middleware,
  timeout, redirect, TLS, buffering, or header semantics.
- `Client.Request.make` failures bypass middleware because no request value
  exists. Post-construction errors keep normal `Client.request` behavior.

## Contract First

- Add `Client.fetch`.
- Add `Client.get`, `Client.head`, `Client.post`, `Client.put`,
  `Client.patch`, `Client.delete`, and `Client.options`.
- Document public contracts in `lib/client.mli`.

## Steps

- [x] Explore: inspect existing client docs, public API, implementation, and
      tests.
- [x] Design review: request context-free third-party review and incorporate
      feedback.
- [x] Red: write failing behavior-focused tests for helper delegation,
      argument preservation, and construction-error bypass.
- [x] Green: implement the smallest change that satisfies the tests.
- [x] Refactor: improve structure while keeping tests green.
- [x] Static checks: run formatters and static analysis tools, then fix
      findings.
- [x] Code review: request context-free third-party review after implementation.
- [x] Re-review: fix review findings and repeat review until it passes.

## Decisions

- Use middleware that returns a synthetic response to test helper behavior
  without opening a network connection.

## Verification

- `dune build @fmt`
- `dune exec test/test_client.exe`
- `dune build examples/client_fetch.exe`
- `dune build @check`
- `dune build @all`

## Completion Notes

Added `Client.fetch` plus method-specific helpers for common HTTP methods.
Updated focused client tests to verify helper delegation, optional header/body
preservation, arbitrary method preservation, and request-construction error
bypass. Updated README and the client fetch example to use `Client.get`.

Code review found no API or implementation bugs. It flagged stale execution
plan bookkeeping; the plan was completed and moved to `completed/`.

## Commit

feat: add client convenience helpers
