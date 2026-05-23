# Add Opt-In Streaming Request Bodies

## Status

Completed

## Objective

Add an opt-in server mode that passes request bodies to handlers as streaming
`Body.t` values, while keeping the default buffered request behavior unchanged.

## Context

- [Agent Guide](../../../AGENTS.md)
- [Minimal HTTP/1.1 Server Milestone](../../product-specs/minimal-http1-server.md)
- [Minimal Server API](../../product-specs/minimal-server-api.md)
- [Streaming Request Bodies](../../design-docs/streaming-request-bodies.md)
- [ADR 0002](../../design-docs/adr/0002-introduce-streaming-bodies-with-buffered-compatibility.md)
- [Introduce Body Internal Variants](../completed/0012-introduce-body-internal-variants.md)
- [Build Server Request From Parsed Head](../completed/0013-build-server-request-from-head.md)

## Clarifications

- Preserve `Server.create` default behavior: request bodies are buffered and
  replayable unless the caller opts into streaming.
- Keep the handler contract `Request.t -> Response.t`.
- Do not implement streaming multipart parsing in this plan.
- Continue rejecting unsupported transfer encodings and declared bodies larger
  than `max_request_body_size`.

## Contract First

Extend `Server` with a request body mode:

```ocaml
type request_body_mode = Buffered | Streaming

val create :
  ?max_request_body_size:int ->
  ?request_body_mode:request_body_mode ->
  ?middlewares:Middleware.t list ->
  handler:Handler.t ->
  unit ->
  t
```

`Buffered` is the default and preserves existing behavior. `Streaming` makes the
server invoke the handler after the request head is parsed and body length is
validated, with `Request.body request` backed by the live connection source.

`Body.to_string` remains a buffered compatibility helper and raises
`Invalid_argument` for streaming bodies. `Body.to_string_limited`,
`Body.with_source`, `Body.copy_to_sink`, and `Body.save_to_path` are the
streaming-capable consuming paths.

## Steps

- [x] Explore: inspect Body, Server, specs, design docs, and tests.
- [x] Design review: request context-free third-party review before
      implementation.
- [x] Red: add Body and Server tests for opt-in streaming behavior.
- [x] Green: implement the smallest streaming request path.
- [x] Refactor: keep protocol validation in `Http1` and source construction in
      `Body`/`Server`.
- [x] Static checks: run formatters and static analysis tools, then fix
      findings.
- [x] Code review: request context-free third-party review after implementation.
- [x] Re-review: fix review findings and repeat review until it passes.

## Decisions

- Add `Server.request_body_mode = Buffered | Streaming` with default
  `Buffered`.
- Expose a narrow `Body.Internal.streaming` bridge so `Server` can construct
  streaming bodies while keeping ordinary body constructors buffered.
- In streaming mode, expose a source capped to the declared `Content-Length`.
  The source yields already-buffered body bytes before reading from the live
  flow, and it never exposes bytes beyond the declared body length.
- Add `Body.Unexpected_end_of_body` for bounded in-memory reads that observe a
  short streaming body.
- Keep live streaming request bodies handler-scoped and single-consumption by
  runtime state.

## Verification

- `dune build @fmt`
- `dune build @all`
- `dune runtest`
- `CAMELIO_RUN_NETWORK_TESTS=1 dune exec test/test_server.exe`
- `dune build @check`
- `dune build @install`
- `opam lint camelio.opam`

## Completion Notes

Added opt-in streaming request bodies with `Server.request_body_mode`. Buffered
mode remains the default. Streaming mode validates `Content-Length`, rejects
declared over-limit bodies before handler invocation, and provides a
single-consumption `Body.t` backed by a source capped to the declared body
length.

The bounded source exposes already-read body bytes before reading from the live
connection and raises `Body.Unexpected_end_of_body_read` if the live body ends
early. `Body.to_string_limited` maps short streaming reads to
`Unexpected_end_of_body`.

Code review found one high-severity short-body source-consumer issue, one test
gap, and stale interface docs. All were fixed, and the second re-review passed.

## Commit

Pending.
