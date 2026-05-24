# Implement Response Streaming

## Status

Completed

## Objective

Implement the first minimal response streaming API and HTTP/1.1 response writer
for Choku.

## Context

- [Response Streaming](../../product-specs/response-streaming.md)
- [Response Streaming Design](../../design-docs/response-streaming.md)
- [Design Response Streaming](../completed/0028-design-response-streaming.md)
- [HTTP/1.1 Persistent Connections](../../product-specs/http1-persistent-connections.md)

## Clarifications

- Keep `Handler.t = Request.t -> Response.t`.
- Keep existing buffered `Response.text`, `Response.make`, and
  `Http1.serialize_response` behavior source-compatible.
- Implement only callback-scoped `Response.stream`; defer source-backed,
  sendfile, SSE, compression, trailers, and HTTP/2 concerns.

## Contract First

- Add `Response.stream`.
- Extend `Body.t` internally to represent single-consumption response writers.
- Add HTTP/1.1 response writing that supports buffered, known-length streaming,
  and unknown-length chunked streaming bodies.
- Preserve HEAD suppression and no-body status semantics.
- Close the connection after streaming write failures.

## Steps

- [x] Explore: inspect response, body, HTTP/1.1 serialization, and server write
      paths.
- [x] Red: add focused response/body/http1/server tests for streaming response
      behavior.
- [x] Green: implement streaming body writers and HTTP/1.1 response writer.
- [x] Refactor: keep buffered response serialization compatible and keep close
      decisions explicit.
- [x] Static checks: run formatter and targeted/full test commands.
- [x] Code review: request context-free review, fix findings, and re-review.
- [x] Completion: move plan to completed and commit.

## Decisions

- Use chunked transfer coding for unknown-length streaming responses.
- Use `Content-Length` and a counting sink for known-length streaming
  responses.
- Treat no-body statuses differently from HEAD: no-body statuses omit body
  framing; HEAD preserves the would-be GET framing but writes no body.

## Verification

Passed:

- `dune build @fmt`
- `dune exec test/test_response.exe`
- `dune exec test/test_headers.exe`
- `CHOKU_RUN_NETWORK_TESTS=1 dune exec test/test_server.exe`
- `dune runtest`
- `dune build @all`
- `dune build @check`
- `dune build @install`
- `opam lint choku.opam`

## Completion Notes

Implemented callback-scoped response streaming with `Response.stream`.
Streaming responses are represented as single-consumption body writers and are
written by the HTTP/1.1 server after the handler returns.

Unknown-length streaming responses use `Transfer-Encoding: chunked`.
Known-length streaming responses use `Content-Length` and a counting sink that
closes the connection after underflow or overflow. Choku now owns
`Content-Length`, `Transfer-Encoding`, and `Connection` during response
serialization.

HEAD responses preserve would-be GET framing without invoking streaming
writers. Body-forbidden statuses omit body framing and do not invoke streaming
writers. Successful streaming responses may keep the connection alive; streaming
failures close it.

Context-free code review passed with no blocking findings.

## Commit

`feat: add response streaming`
