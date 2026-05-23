# Split Server Request Reading

## Status

Completed

## Objective

Refactor the HTTP/1.1 server read path into request-head reading and fixed-body
reading while preserving the current buffered request behavior.

## Context

- [Agent Guide](../../../AGENTS.md)
- [Streaming Request Bodies](../../design-docs/streaming-request-bodies.md)
- [ADR 0002](../../design-docs/adr/0002-introduce-streaming-bodies-with-buffered-compatibility.md)
- [Extract HTTP/1.1 Request Head Parser](../completed/0010-extract-http1-request-head-parser.md)

## Clarifications

- Do not expose new public API in this plan.
- Do not implement streaming request bodies yet.
- Preserve current HTTP/1.1 behavior: request bodies are still fully buffered
  before handler invocation.

## Contract First

No public contract changes. Internal server read boundaries should become:

- read bytes through the request head;
- parse and validate the request head through `Http1`;
- read the fixed-length body according to `Content-Length`.

## Steps

- [x] Explore: inspect current server read path after `Http1` head extraction.
- [x] Design review: keep the refactor behavior-preserving.
- [x] Red: rely on existing server and HTTP/1.1 tests as behavior guard.
- [x] Green: split `Server.read_request_bytes`.
- [x] Refactor: keep helpers small and named around protocol stages.
- [x] Static checks: run formatters and static analysis tools, then fix
      findings.
- [x] Code review: perform local review and address findings.

## Decisions

- Keep the full raw request string as the output of the read path for now, so
  `Http1.parse_request_string` remains the final request constructor.
- Store already-read body bytes separately after head parsing.

## Verification

Verified commands:

```sh
dune build @all
dune runtest
dune build @fmt
dune build @check
dune build @install
opam lint camelio.opam
```

## Completion Notes

Split the server request read path into request-head reading and fixed-length
body reading. The server still buffers request bodies before handler invocation,
but the protocol stages are now explicit and ready for a future streaming body
construction step.

## Commit

```text
refactor: split server request reading
```
