# Add HTTP Security Regression Tests

## Status

Completed

## Objective

Add regression tests for HTTP server vulnerability classes that commonly affect
HTTP parser, request body, routing, header, and multipart implementations.

## Context

- [Minimal HTTP/1.1 Server Milestone](../../product-specs/minimal-http1-server.md)
- [Minimal Server API](../../product-specs/minimal-server-api.md)
- [Multipart Form-Data Support](../../product-specs/multipart-form-data.md)
- [Streaming Request Bodies](../../design-docs/streaming-request-bodies.md)
- [Route-Level Body Mode](../../design-docs/route-level-body-mode.md)

## Clarifications

- The tests should target vulnerability classes, not product-specific CVEs.
- The expected behavior should match Camelio's current HTTP/1.1 scope:
  connection-close responses, no chunked request support, origin-form request
  targets only, bounded request bodies, and explicit streaming opt-in.

## Contract First

No new public API is planned. This work records and verifies existing security
contracts:

- unsupported transfer codings are rejected;
- ambiguous or malformed `Content-Length` is rejected;
- invalid request targets are rejected before handler invocation;
- invalid header names and response header values are rejected;
- body size limits apply before handlers run;
- streaming bodies expose no more than the declared `Content-Length`;
- malformed multipart data is rejected without path traversal in helper output.

## Steps

- [x] Explore: inspect HTTP/1 parser, server, header, request, and multipart
      tests.
- [x] Red: add focused negative tests for smuggling, header injection, target
      validation, body boundaries, and multipart filename/header cases.
- [x] Green: tighten implementation only where tests expose a gap.
- [x] Refactor: keep tests readable and grouped by vulnerability class.
- [x] Static checks: run formatter and focused/full checks.
- [x] Code review: not delegated unless explicitly requested by the user.
- [x] Completion: move plan to completed and commit.

## Decisions

- Keep this pass test-only because the added cases confirmed existing Camelio
  behavior already rejects or safely bounds the tested inputs.
- Treat any `Transfer-Encoding` request as unsupported, including
  `Transfer-Encoding` plus `Content-Length`, because Camelio does not implement
  chunked request bodies.
- Preserve connection-close semantics and verify declared `Content-Length`
  bounds the exposed body bytes.

## Verification

- `dune build @fmt`
- `dune exec test/test_http1.exe`
- `dune exec test/test_request.exe`
- `dune exec test/test_response.exe`
- `dune exec test/test_multipart.exe`
- `dune exec test/test_server.exe`
- `CAMELIO_RUN_NETWORK_TESTS=1 dune exec test/test_server.exe`
- `dune build @all`
- `dune runtest`
- `dune build @check`
- `dune build @install`
- `opam lint camelio.opam`

## Completion Notes

Added regression coverage for request smuggling classes, malformed folded
headers, response header injection, request target controls, content-length body
caps, and multipart filename/header hardening. No implementation changes were
required.

## Commit

`test: add http security regression coverage`
