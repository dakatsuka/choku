# Add Streaming Multipart Iterator

## Status

Completed

## Objective

Add the first true streaming multipart API so handlers can process multipart
parts through Eio sources without buffering the whole request body or each part
body into memory.

## Context

- [Agent Guide](../../../AGENTS.md)
- [Multipart Form-Data Support](../../product-specs/multipart-form-data.md)
- [Streaming Request Bodies](../../design-docs/streaming-request-bodies.md)
- [Add Opt-In Streaming Request Bodies](../completed/0014-add-opt-in-streaming-request-bodies.md)
- [Add Bounded Multipart Request Read](../completed/0015-add-bounded-multipart-request-read.md)

## Clarifications

- Preserve existing buffered `Multipart` APIs.
- Keep the first streaming parser canonical and narrow: CRLF-delimited multipart
  form-data, no nested multipart, no header continuations, no automatic file
  storage.
- Streaming parts are scoped to the iterator callback.

## Contract First

Add:

```ocaml
module Streaming : sig
  type part

  val headers : part -> Headers.t
  val name : part -> string option
  val filename : part -> string option
  val content_type : part -> string option

  val iter_request :
    ?max_header_size:int ->
    Request.t ->
    on_part:(part -> Eio.Flow.source_ty Eio.Resource.t -> unit) ->
    (unit, error) result
end
```

`iter_request` validates `Content-Type` and boundary before consuming the body,
then invokes `on_part part source` for each part. The part source yields bytes
up to the next multipart boundary. If `on_part` returns before consuming the
part source, the iterator drains the remainder to reach the next part.

## Steps

- [x] Explore: inspect current multipart parser, Body streaming source, docs,
      and tests.
- [x] Design review: request context-free third-party review before
      implementation.
- [x] Red: add tests for streaming multipart success, partial consumption,
      malformed bodies, and content-type errors.
- [x] Green: implement a canonical CRLF streaming multipart iterator.
- [x] Refactor: share metadata parsing with buffered parts where practical.
- [x] Static checks: run formatters and static analysis tools, then fix
      findings.
- [x] Code review: request context-free third-party review after implementation.
- [x] Re-review: fix review findings and repeat review until it passes.

## Decisions

- Put streaming multipart under `Multipart.Streaming` so existing buffered
  `Multipart` APIs remain unchanged.
- Use callback scoping for part sources. The source is valid only during
  `on_part`.
- Drain an unconsumed part only when `on_part` returns normally. Propagate
  callback exceptions unchanged without draining.
- Map body-source truncation to `Unexpected_end_of_body`; reserve
  `Malformed_body` for multipart syntax and header errors.
- Apply `max_header_size` per part header block. Negative values raise
  `Invalid_argument`; exceeded limits return `Malformed_body`.

## Verification

- `dune build @fmt`
- `dune build @all`
- `dune runtest`
- `dune build @check`
- `dune build @install`
- `opam lint choku.opam`

## Completion Notes

Added `Multipart.Streaming.iter_request` for canonical CRLF multipart request
bodies. The iterator validates request content type before body consumption,
streams each part body to a callback-scoped source, drains unconsumed part bytes
after normal callback return, and propagates callback exceptions without
draining.

Code review found a header-size accounting issue when the header terminator was
split across reads. The parser now excludes possible delimiter-prefix bytes from
the `max_header_size` check, and a chunked-source regression test covers the
case. Re-review passed.

## Commit

`feat: add streaming multipart iterator`
