# Implement HTTP/1.1 Chunked Request Bodies

## Status

Completed

## Objective

Support HTTP/1.1 request bodies framed with `Transfer-Encoding: chunked` while
preserving Choku's close-oriented HTTP/1.1 server model, request-smuggling
protections, body-size limit, buffered body compatibility, and opt-in streaming
request bodies.

## Context

- [Minimal HTTP/1.1 Server Milestone](../../product-specs/minimal-http1-server.md)
- [Minimal Server API](../../product-specs/minimal-server-api.md)
- [Streaming Request Bodies](../../design-docs/streaming-request-bodies.md)
- [HTTP/1.1 Chunked Request Bodies](../../design-docs/http1-chunked-request-bodies.md)
- [HTTP/1.1 Chunked Transfer Coding Reference](../../references/http1-chunked-transfer-coding.md)

## Clarifications

- Implement request chunked decoding only. Chunked responses, keep-alive,
  pipelining, and trailer exposure remain out of scope.
- Preserve rejection of requests with both `Transfer-Encoding` and
  `Content-Length`.

## Contract First

- Update `Http1` body framing validation so `Transfer-Encoding: chunked` is
  accepted and unsupported or ambiguous transfer framing remains a 400.
- Extend internal `Body` streaming construction to support unknown-length
  decoded sources.
- Add a body consumer exception for decoded body-size overflow during streaming
  chunked consumption and map it through `Body.to_string_limited`.
- Add a body consumer exception and result variant for malformed streaming
  chunked framing and map uncaught body protocol exceptions in `Server` to 400
  or 413 before response writing.
- Bound chunk framing metadata with the existing `max_request_head_size` value.

## Steps

- [x] Explore: inspect existing docs, parser, server request reading, body API,
      and tests.
- [x] Design review: request context-free third-party review and incorporate
      feedback.
- [x] Red: add behavior-focused tests for buffered chunked requests, malformed
      chunks, mixed framing rejection, decoded size limits, and streaming
      chunked consumption.
- [x] Green: implement the smallest protocol and body changes that satisfy the
      tests.
- [x] Refactor: keep chunked parsing isolated from fixed-length body reading and
      preserve existing public API shape.
- [x] Static checks: run formatters and focused/full Dune checks.
- [x] Code review: request context-free third-party review after implementation.
- [x] Re-review: fix review findings and repeat review until it passes.

## Decisions

- Decode chunked request bytes before exposing them to handlers.
- Reject `Transfer-Encoding` plus `Content-Length` instead of normalizing mixed
  framing.
- Read and discard trailers; do not expose trailer fields in this milestone.
- Enforce buffered chunked body limits before handler invocation.
- Enforce streaming chunked body limits while the handler consumes the body.
- Treat chunk metadata overflow as malformed request framing.
- Parse `Transfer-Encoding` as case-insensitive HTTP list values and accept only
  the singleton `chunked` coding.

## Verification

- `dune build @fmt`
- `dune exec test/test_http1.exe`
- `dune exec test/test_body.exe`
- `dune exec test/test_multipart.exe`
- `dune exec test/test_server.exe`
- `CHOKU_RUN_NETWORK_TESTS=1 dune exec test/test_server.exe`
- `dune build @all`
- `dune runtest`
- `dune build @check`
- `dune build @install`
- `opam lint choku.opam`

## Completion Notes

Implemented request-side `Transfer-Encoding: chunked` support for buffered and
streaming body modes. Added a private chunk decoder/source, overflow-safe chunk
size parsing, trailer drain, chunk metadata limits, singleton `chunked`
Transfer-Encoding validation, and continued `Transfer-Encoding` plus
`Content-Length` rejection.

Extended `Body` internal streaming support for unknown-length sources and added
explicit body protocol errors for streaming decoded overflow and malformed body
framing. Updated server exception mapping, multipart body-consumption error
handling, public docs, product specs, README status, and regression tests.

Design review required explicit chunk metadata limits, streaming malformed body
contracts, overflow-safe parsing, product error-policy clarification, and
Transfer-Encoding list semantics. Code review found multipart error-handling and
stale public docs; both were fixed and reverified.

## Commit

`feat: support chunked request bodies`
