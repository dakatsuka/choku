# Extract HTTP/1.1 Request Head Parser

## Status

Completed

## Objective

Expose and use an HTTP/1.1 request-head parser so `Server` can validate method,
target, headers, transfer encoding, and content length before body handling
without duplicating header parsing logic.

## Context

- [Agent Guide](../../../AGENTS.md)
- [Streaming Request Bodies](../../design-docs/streaming-request-bodies.md)
- [ADR 0002](../../design-docs/adr/0002-introduce-streaming-bodies-with-buffered-compatibility.md)
- [Minimal HTTP/1.1 Server](../completed/0002-implement-minimal-http1-server.md)

## Clarifications

- Do not implement live streaming bodies in this plan.
- Keep `Handler.t`, `Request.t`, and current body buffering behavior unchanged.
- Remove `Server`'s duplicated header parsing by delegating to `Http1`.

## Contract First

Add a documented low-level parser:

- `Http1.request_head`;
- `Http1.parse_request_head_string`.

## Steps

- [x] Explore: inspect `Http1` parser and duplicated `Server` header parsing.
- [x] Design review: keep the parser small and protocol-specific.
- [x] Red: write failing tests for request-head parsing.
- [x] Green: implement parser extraction and update `Server`.
- [x] Refactor: remove duplicated header parsing while keeping behavior.
- [x] Static checks: run formatters and static analysis tools, then fix
      findings.
- [x] Code review: perform local review and address findings.

## Decisions

- `request_head` is a small record of method, target, and headers.
- `parse_request_head_string` accepts the request head block without the final
  `CRLF CRLF` separator.
- Transfer-Encoding is rejected at the head parsing layer, matching existing
  full-request behavior.

## Verification

Verified commands:

```sh
dune build @all
dune runtest
dune build @fmt
dune build @check
dune build @install
opam lint choku.opam
```

## Completion Notes

Added `Http1.request_head` and `Http1.parse_request_head_string`. Full request
parsing now reuses the head parser, and `Server` delegates header validation and
content-length extraction to `Http1` instead of maintaining duplicate parsing
logic.

## Commit

```text
refactor: extract HTTP/1.1 request head parser
```
