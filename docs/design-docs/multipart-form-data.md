# Multipart Form-Data Support

## Status

Draft

## Context

URL-encoded forms are small key-value bodies that fit Camelio's current
buffered `Body.t`. Multipart form-data can contain files and should eventually
stream through Eio flows. Camelio should therefore add multipart support in
phases instead of pretending file uploads are just another string multimap.

Phase 1 uses the current buffered body model to establish public concepts:
multipart values, parts, structured errors, content-type handling, and ordered
field lookup. Later phases can replace the internal part body representation
with streaming without changing the high-level separation between URL-encoded
forms and multipart parts.

## Goals

- Add `Camelio.Multipart` as a separate optional module.
- Keep `Request.t`, `Body.t`, and `Server` unchanged in Phase 1.
- Preserve part headers and body bytes.
- Expose field lookup by `Content-Disposition` name.
- Use result errors for malformed client input.
- Document the path toward Eio streaming support.

## Non-Goals

- Streaming parser implementation in Phase 1.
- Automatic tempfile management.
- Filename sanitization or upload storage policy.
- Full MIME feature coverage.
- Nested multipart parsing.

## Proposed Design

`Multipart.t` is an abstract ordered part list. Each `Part.t` contains:

- parsed part headers;
- optional field name from `Content-Disposition`;
- optional filename from `Content-Disposition`;
- optional content type from `Content-Type`;
- buffered body bytes as `Body.t`.
- helpers for copying the buffered body to an application-owned Eio sink or
  path.

The first parser accepts canonical CRLF-delimited multipart bodies:

```text
--boundary CRLF
headers CRLF
CRLF
body CRLF
--boundary CRLF
...
--boundary-- CRLF?
```

Headers use the same field-name and field-value validation as `Headers.add`.
Header continuation lines are rejected as malformed input.

`Content-Disposition` parameters are parsed for quoted or token values. Phase 1
does not unescape quoted-pair sequences and does not implement extended
parameters such as `filename*`.

`Multipart.of_request` accepts media type `multipart/form-data`
case-insensitively and extracts a non-empty `boundary` parameter. The boundary
may be token-like or quoted. The parser does not scan for a boundary when the
parameter is absent.

`Multipart.of_request_limited ~max_size request` performs the same content-type
and boundary validation, then reads `Request.body request` with
`Body.to_string_limited ~max_size`. This lets handlers that may receive
server-created streaming bodies opt into a bounded in-memory multipart parse.
It is still the buffered parser internally and does not expose streaming parts.

`Multipart.Streaming.iter_request ?max_header_size request ~on_part` is the
first true streaming multipart API. It validates `Content-Type` and boundary
before consuming the body, then parses canonical CRLF multipart framing from
`Body.with_source`. Each callback receives part metadata and a source that yields
bytes up to the next boundary without exposing boundary bytes.

Part sources are scoped to the dynamic extent of the callback. They must not be
stored, read concurrently, or read after the callback returns. If the callback
returns normally without consuming the part source, the iterator drains the
remaining part bytes before parsing the next part. If the callback raises, the
iterator does not drain and re-raises the application exception unchanged.

`max_header_size` is a per-part header block limit. It defaults to `8192` bytes,
raises `Invalid_argument` when negative, and returns `Malformed_body` when a
part header block exceeds the limit. Premature request-body termination maps to
`Unexpected_end_of_body`; complete but invalid multipart syntax maps to
`Malformed_body`.

## Contracts

The first implementation should add:

```ocaml
module Multipart : sig
  type t

  type error =
    | Missing_content_type
    | Unsupported_content_type of string
    | Missing_boundary
    | Malformed_body
    | Body_too_large
    | Unexpected_end_of_body

  module Part : sig
    type t

    val headers : t -> Headers.t
    val name : t -> string option
    val filename : t -> string option
    val content_type : t -> string option
    val body : t -> Body.t
    val copy_to_sink : t -> _ Eio.Flow.sink -> unit
    val save_to_path :
      ?append:bool -> create:Eio.Fs.create -> _ Eio.Path.t -> t -> unit
  end

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

  val decode : boundary:string -> string -> (t, error) result
  val of_request : Request.t -> (t, error) result
  val of_request_limited : max_size:int -> Request.t -> (t, error) result
  val parts : t -> Part.t list
  val get : string -> t -> Part.t option
  val get_all : string -> t -> Part.t list
  val pp_error : Format.formatter -> error -> unit
end
```

All public functions and types in `multipart.mli` must have block comments.

## Alternatives Considered

- Return `Form.t`: rejected because multipart parts include headers, filenames,
  content types, and future streaming bodies.
- Implement streaming first: deferred because the current protocol layer
  buffers request bodies and a streaming body redesign deserves its own design
  and likely ADR.
- Raise exceptions for malformed multipart input: rejected because malformed
  upload bodies are ordinary client input.

## Third-Party Review

Not run in this pass because the available multi-agent tool may only be used
when the user explicitly requests delegation. The design is intentionally
limited to Phase 1 and covered with behavior tests.

## Validation

Implementation should follow Explore -> Red -> Green -> Refactor:

- add `lib/multipart.mli` with contracts first;
- add `test/test_multipart.ml` before implementation;
- test request content-type handling, boundary extraction, basic parts,
  repeated fields, filenames, part content types, and malformed bodies;
- run `dune build @all`, `dune runtest`, `dune build @fmt`, `dune build
  @check`, `dune build @install`, and `opam lint camelio.opam`.

## Open Questions

- Should Phase 3 redesign `Body.t` as replayable-buffered-or-streaming, or add a
  separate request streaming API?
