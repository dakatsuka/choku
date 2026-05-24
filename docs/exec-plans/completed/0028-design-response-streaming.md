# Design Response Streaming

## Status

Completed

## Objective

Design Choku's first response streaming and HTTP/1.1 chunked response behavior
without implementing it yet.

## Context

- [Response Streaming](../../product-specs/response-streaming.md)
- [Response Streaming Design](../../design-docs/response-streaming.md)
- [Streaming Request Bodies](../../design-docs/streaming-request-bodies.md)
- [HTTP/1.1 Persistent Connections](../../product-specs/http1-persistent-connections.md)
- [Minimal Server API](../../product-specs/minimal-server-api.md)

## Clarifications

- This milestone is design-only.
- Preserve `Handler.t = Request.t -> Response.t`.
- Do not add HTTP/2, HTTP/3, trailers, compression, sendfile, or SSE in the
  first implementation design.

## Contract First

- Define expected callback/scoped public API shape for streaming responses.
- Define HTTP/1.1 framing behavior for buffered, known-length streaming, and
  unknown-length streaming responses.
- Define HEAD, keep-alive, failure, and ownership semantics before
  implementation.

## Steps

- [x] Explore: inspect current `Body`, `Response`, HTTP/1.1 serialization, and
      server response writing paths.
- [x] Draft: add response streaming product spec and design doc.
- [x] Design review: request context-free third-party review and incorporate
      feedback.
- [x] Revise: update docs based on review.
- [x] Static checks: run documentation-safe formatting/build checks.

## Decisions

- Prefer callback-based `Response.stream` as the ergonomic user-facing
  constructor.
- Defer source-backed public constructors because source lifetime is easy to
  misuse when serialization happens after the handler returns.
- Use HTTP/1.1 chunked transfer coding for unknown-length streaming responses.
- Keep the first response streaming implementation in the connection fiber.

## Verification

Passed:

- `dune build @fmt`
- `dune runtest`
- `dune build @all`
- `dune build @check`
- `dune build @install`
- `opam lint choku.opam`

## Completion Notes

Designed the first response streaming milestone around a callback-scoped
`Response.stream` API. The design specifies HTTP/1.1 chunked responses for
unknown-length streams, fixed-length writer enforcement, HEAD handling,
body-forbidden status handling, server-owned framing headers, connection reuse
rules, and the internal body view needed by serializers.

Design review first found unsafe raw-source lifetime, missing internal body
inspection, no-body status gaps, unclear framing header policy, and unresolved
known-length overflow semantics. The design was revised and re-reviewed with
PASS.

## Commit

`docs: design response streaming`
