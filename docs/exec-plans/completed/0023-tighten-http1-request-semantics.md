# Tighten HTTP/1.1 Request Semantics

## Status

Completed

## Objective

Close correctness and security gaps in Choku's current HTTP/1.1 server by
validating required `Host` headers, centralizing origin-form request-target
validation, preserving documented protocol error precedence, and suppressing
response body bytes for explicit `HEAD` requests.

## Context

- [Minimal HTTP/1.1 Server Milestone](../../product-specs/minimal-http1-server.md)
- [Minimal Server API](../../product-specs/minimal-server-api.md)
- [Minimal Server, Handler, and Middleware API](../../design-docs/minimal-server-handler-middleware-api.md)
- [HTTP Request Limits And Timeouts](../../design-docs/http-request-limits-and-timeouts.md)
- [Future Work](../../design-docs/future-work.md)

## Clarifications

- The user approved the inspection plan that prioritizes `Host` validation,
  origin-form target validation, explicit `HEAD` response behavior, request-head
  scanner cleanup, and network test harness cleanup.
- Keep-alive, pipelining, chunked bodies, trailers, upgrades, TLS, HTTP/2,
  HTTP/3, full body timeouts, slow upload policy, automatic router `HEAD`
  fallback, and 405 handling remain out of scope.

## Contract First

- Update product/design docs to state the server rejects missing, empty, or
  duplicate `Host` headers for HTTP/1.1 requests before handler invocation.
- Update request-target documentation to define the accepted origin-form subset:
  slash-prefixed path with optional query and no fragment or control/space
  bytes.
- Update response serialization documentation to state explicit `HEAD` requests
  preserve the response `Content-Length` but do not write body bytes.

## Steps

- [x] Explore: inspect existing docs, tests, and source.
- [x] Design review: request context-free third-party review and incorporate
      feedback.
- [x] Red: add behavior-focused tests for `Host`, target validation precedence,
      and explicit `HEAD`.
- [x] Green: implement the smallest protocol changes that satisfy tests.
- [x] Refactor: centralize target validation and reduce scanner/test harness
      duplication where scoped.
- [x] Static checks: run formatters and focused/full test commands.
- [x] Code review: request context-free third-party review after implementation.
- [x] Re-review: fix review findings and repeat review until it passes.

## Decisions

- HTTP/1.1 `Host` validation is enforced as exactly one non-empty field and maps
  violations to the existing `Malformed_header`/400 behavior.
- The accepted origin-form subset is enforced before body reading so malformed
  targets take precedence over body-size errors.
- Explicit `HEAD` requests suppress only wire body bytes; serialized
  `Content-Length` remains based on the response body.
- Internal helper modules are hidden with Dune `private_modules`.

## Verification

- `dune build @fmt`
- `dune exec test/test_http1.exe`
- `dune exec test/test_request.exe`
- `dune exec test/test_server.exe`
- `CHOKU_RUN_NETWORK_TESTS=1 dune exec test/test_server.exe`
- `dune build @all`
- `dune runtest`
- `dune build @check`
- `dune build @install`
- `opam lint choku.opam`

## Completion Notes

Updated product and design docs, added protocol regression tests, tightened
HTTP/1.1 request parsing, added explicit `HEAD` response serialization behavior,
and reduced small duplications in request-target validation, header-end scanning,
and the network server test harness.

## Commit

Pending.
