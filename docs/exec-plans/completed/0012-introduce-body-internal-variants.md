# Introduce Body Internal Variants

## Status

Completed

## Objective

Change `Body.t` from a raw buffered string into an internal representation that
can also hold a future streaming source, while preserving existing public
buffered behavior.

## Context

- [Agent Guide](../../../AGENTS.md)
- [Streaming Request Bodies](../../design-docs/streaming-request-bodies.md)
- [ADR 0002](../../design-docs/adr/0002-introduce-streaming-bodies-with-buffered-compatibility.md)
- [Add Buffered Body Source Access](../completed/0007-add-buffered-body-source.md)
- [Add Body Consumers](../completed/0008-add-body-consumers.md)
- [Add Limited Body Read](../completed/0009-add-limited-body-read.md)
- [Split Server Request Reading](../completed/0011-split-server-request-reading.md)

## Clarifications

- Preserve the existing public `Body` API for this plan.
- Do not yet pass live request streams from `Server` to handlers.
- Keep existing buffered behavior stable for tests, multipart, forms, router,
  and server request parsing.

## Contract First

No new public functions are exposed. Internally, `Body.t` becomes:

```ocaml
type t =
  | Buffered of string
  | Streaming of streaming
```

The streaming record carries enough state to support future work:

- a request-scoped Eio source;
- a mutable single-consumption flag;
- an optional source-level maximum size used by bounded reads.

Public contract behavior preserved in this plan:

- `Body.empty` and `Body.string` produce replayable buffered bodies;
- `Body.to_string`, `Body.to_string_limited`, `Body.with_source`, and
  `Body.copy_to_sink` continue to behave as before for buffered bodies;
- `Body.is_buffered` returns `true` for buffered bodies.

## Steps

- [x] Explore: inspect existing Body, Server read boundaries, specs, design docs,
      and tests.
- [x] Design review: request context-free third-party review before
      implementation.
- [x] Red: add focused Body tests that pin buffered compatibility after the
      representation change.
- [x] Green: implement the smallest Body representation change.
- [x] Refactor: keep streaming-ready helpers local and explicit.
- [x] Static checks: run formatters and static analysis tools, then fix
      findings.
- [x] Code review: request context-free third-party review after implementation.
- [x] Re-review: fix review findings and repeat review until it passes.

## Decisions

- Keep the streaming constructor private to `Body.ml` until `Server` starts
  constructing streaming request bodies.
- Use runtime single-consumption state for the future streaming branch, because
  `Body.t` remains abstract and must still fit the existing `Request.t` shape.
- Keep `Body.to_string` as the buffered compatibility API. If it is ever called
  on a streaming body before a dedicated public contract is added, it raises
  `Invalid_argument` rather than implicitly consuming the stream.

## Verification

- `dune build @fmt`
- `dune runtest`
- `dune build @all`
- `dune build @check`
- `dune build @install`
- `opam lint choku.opam`

## Completion Notes

Changed `Body.t` to an internal buffered-or-streaming representation while
keeping all public constructors buffered and replayable. Added streaming-ready
single-consumption state and bounded read handling for the private streaming
branch, but did not expose a streaming constructor or wire the server to live
request streams.

The post-implementation context-free review found no issues. Residual risk:
the private streaming branch is dormant until a later server integration or
internal constructor makes it directly testable.

## Commit

`refactor: introduce body internal variants`
