# Streaming Request Bodies

## Status

Draft

## Context

Camelio currently exposes `Body.t` as a replayable buffered body. This is simple
and works well for tests, URL-encoded forms, small JSON payloads, and Phase 1
multipart parsing. It does not fit large uploads because the server must buffer
the entire request before invoking the handler.

Multipart Phase 1 and Phase 2 deliberately stayed within the buffered model.
Phase 3 should introduce streaming request bodies in a way that keeps simple
handlers ergonomic while allowing Eio-native direct-style upload consumption
with backpressure and structured resource ownership.

## Goals

- Keep small request handlers easy to test.
- Allow large request bodies and multipart parts to be consumed through Eio
  flows without buffering everything first.
- Preserve existing buffered APIs where practical.
- Keep ownership and cancellation aligned with the request-serving fiber.
- Avoid callback-based streaming APIs.

## Non-Goals

- Implementing streaming in this design pass.
- HTTP/2 or HTTP/3 flow-control design.
- Automatic tempfile management.
- Transparent background body draining.
- Making request bodies replayable after streaming consumption.

## Proposed Design

Introduce a body representation with two modes:

```ocaml
module Body : sig
  type t

  val empty : t
  val string : string -> t
  val to_string : t -> string
  val to_string_limited : max_size:int -> t -> (string, error) result

  val is_buffered : t -> bool
  val with_source : t -> (Eio.Flow.source_ty Eio.Resource.t -> 'a) -> 'a
end
```

Buffered bodies continue to work as they do today. `Body.with_source` exposes a
source for both buffered and streaming bodies. For buffered bodies, the source is
created from the stored string. For streaming bodies, the source is the live
request stream scoped to the handler invocation.

`Body.to_string` remains convenient for existing buffered workflows.
`Body.to_string_limited` is the preferred API for code that may later receive
streaming bodies because it makes in-memory reads explicitly bounded. The
streaming implementation should preserve `to_string_limited` as the safe
consuming read path.

The server should invoke handlers before fully reading streaming bodies. The
request body source remains valid only while the handler is running. If the
handler returns without consuming the body, the HTTP/1.1 server may close the
connection instead of attempting connection reuse. This is acceptable for the
current close-oriented HTTP/1.1 implementation.

Multipart streaming should build on `Body.with_source` or a protocol-level body
source. A future streaming multipart parser should expose each part body through
a source scoped to the part consumer callback:

```ocaml
val iter :
  t ->
  (Part.t -> (Eio.Flow.source_ty Eio.Resource.t -> unit) -> unit) ->
  unit
```

The exact multipart streaming API needs its own design after the body contract
is settled.

## Contracts To Preserve

- `Request.t` remains immutable.
- `Handler.t` remains `Request.t -> Response.t`.
- Buffered body construction with `Body.string` remains available for tests.
- Middleware continues to operate at the `Handler.t` layer.
- Streaming consumption uses direct-style Eio operations, not callbacks that
  escape the handler scope.

## Alternatives Considered

- Replace `Body.t` with only `Eio.Flow.source`: rejected because simple tests and
  small body workflows would become unnecessarily awkward.
- Keep only buffered bodies and raise size limits: rejected because file uploads
  need backpressure and bounded memory.
- Store multipart files automatically in tempfiles: rejected because storage
  policy, cleanup, permissions, and filename handling belong to applications or
  a later helper layer.
- Add Lwt/Async-style callbacks: rejected by Camelio's Eio-native design.

## Validation

Before implementation:

- write an execution plan for the `Body.t` transition;
- decide whether `Body.to_string` remains total, takes a limit, or gets split
  into buffered-only and consuming variants;
- add tests for buffered compatibility and streaming one-shot behavior;
- add HTTP/1.1 tests proving handlers can consume request bodies directly.

## Open Questions

- Should `Body.to_string` raise on streaming bodies or require a max-size
  parameter?
- Should streaming bodies be single-consumption by type, by runtime state, or by
  documentation?
- Should the server expose a per-route or per-server body buffering policy?
- How should future HTTP/2 flow control integrate with the same `Body.t`
  abstraction?
