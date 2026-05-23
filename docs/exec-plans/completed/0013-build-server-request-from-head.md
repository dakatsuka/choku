# Build Server Request From Parsed Head

## Status

Completed

## Objective

Refactor the HTTP/1.1 server path to construct `Request.t` directly from the
parsed request head and fixed-length body, instead of rebuilding raw request
bytes and parsing them a second time.

## Context

- [Agent Guide](../../../AGENTS.md)
- [Streaming Request Bodies](../../design-docs/streaming-request-bodies.md)
- [ADR 0002](../../design-docs/adr/0002-introduce-streaming-bodies-with-buffered-compatibility.md)
- [Split Server Request Reading](../completed/0011-split-server-request-reading.md)
- [Introduce Body Internal Variants](../completed/0012-introduce-body-internal-variants.md)

## Clarifications

- Preserve external server behavior.
- Do not expose new public API for this plan.
- Do not pass live request streams to handlers yet.

## Contract First

No public contract changes. Internally, the server request read path should
return `Request.t` after:

- reading and parsing the HTTP/1.1 request head;
- validating `Content-Length`;
- reading the current fixed-length body into `Body.string`;
- constructing `Request.make` from the parsed head and body.

## Steps

- [x] Explore: inspect current `Server`, `Http1`, and tests.
- [x] Design review: request context-free third-party review before
      implementation.
- [x] Red: add or strengthen behavior tests around server body delivery and
      malformed target handling.
- [x] Green: refactor the server read path to construct requests directly.
- [x] Refactor: keep protocol parsing in `Http1` and IO staging in `Server`.
- [x] Static checks: run formatters and static analysis tools, then fix
      findings.
- [x] Code review: request context-free third-party review after implementation.
- [x] Re-review: fix review findings and repeat review until it passes.

## Decisions

- Map `Request.make` validation failures to `Http1.Unsupported_request_target`,
  so direct server construction still returns a protocol error response instead
  of letting request validation escape as an exception.
- Keep all `Content-Length` validation in the existing `read_fixed_body` path:
  use `Http1.content_length`, enforce `max_request_body_size`, reject short
  reads, and truncate surplus bytes already read after the declared body length.
- Keep live streaming deferred. The server still passes `Body.string` to
  handlers in this plan.

## Verification

- `dune build @fmt`
- `dune build @all`
- `dune runtest`
- `CAMELIO_RUN_NETWORK_TESTS=1 dune exec test/test_server.exe`
- `dune build @check`
- `dune build @install`
- `opam lint camelio.opam`

## Completion Notes

The server now constructs `Request.t` directly from `Http1.request_head` and a
buffered `Body.string`, avoiding raw request reconstruction and the second
`Http1.parse_request_string` pass. Request body semantics remain buffered, and
live streaming is still deferred.

Code review found two low-severity issues, both fixed: the server POST test now
asserts `Content-Length` preservation, and the plan wording no longer claims
the new validation mapping preserves an old double-parse detail. Re-review
passed.

## Commit

Pending.
