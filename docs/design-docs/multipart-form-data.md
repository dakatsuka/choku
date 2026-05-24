# Multipart Form-Data Support

## Status

Draft

## Context

URL-encoded forms are small key-value bodies that fit Choku's buffered
`Body.t`. Multipart form-data can contain files, so Choku added multipart
support in phases instead of pretending file uploads are just another string
multimap.

Phase 1 used the buffered body model to establish public concepts: multipart
values, parts, structured errors, content-type handling, and ordered field
lookup. Later phases added bounded parsing for streaming request bodies and a
true streaming iterator for callback-scoped part sources.

## Goals

- Add `Choku.Multipart` as a separate optional module.
- Keep URL-encoded forms and multipart parts as separate abstractions.
- Preserve part headers and body bytes.
- Expose field lookup by `Content-Disposition` name.
- Use result errors for malformed client input.
- Support both buffered multipart parsing and Eio streaming upload handling.

## Non-Goals

- Automatic upload storage policy.
- Full MIME feature coverage.
- Nested multipart parsing.

## Proposed Design

`Multipart.t` is an abstract ordered part list for buffered multipart data.
Each `Part.t` contains:

- parsed part headers;
- optional field name from `Content-Disposition`;
- optional filename from `Content-Disposition`;
- optional content type from `Content-Type`;
- buffered body bytes as `Body.t`;
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

`Multipart.Filename.sanitize ?max_length filename` is a pure helper for turning
client supplied filename metadata into a filesystem-friendly candidate name. It
does not choose a destination directory, prevent overwrites, validate file
content, or make the original filename trustworthy. It replaces unsafe
characters, including path separators, with `-`; collapses repeated separators
and periods; removes leading periods and separators; truncates to `max_length`
bytes; and falls back to `upload`, truncated to `max_length`, when no safe
characters remain.

`Multipart.Tempfile.save_source` writes a source to a generated temporary file
under an application-provided Eio directory capability. The helper also backs
`Multipart.Tempfile.save_part` for buffered parts. The storage filename is
generated from an explicit random source, never from the client supplied
filename. Files are created with `` `Exclusive 0o600 ``. Successful files remain
application-owned; failed copies remove partial files on a best-effort basis.

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

  module Filename : sig
    val sanitize : ?max_length:int -> string -> string
  end

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

  module Tempfile : sig
    type 'a t constraint 'a = [> Eio.Fs.dir_ty ]

    val path : 'a t -> 'a Eio.Path.t
    val original_filename : 'a t -> string option
    val display_filename : 'a t -> string option
    val size : 'a t -> int

    val save_source :
      dir:'a Eio.Path.t ->
      random:Eio.Flow.source_ty Eio.Resource.t ->
      ?original_filename:string ->
      Eio.Flow.source_ty Eio.Resource.t ->
      'a t

    val save_part :
      dir:'a Eio.Path.t ->
      random:Eio.Flow.source_ty Eio.Resource.t ->
      Part.t ->
      'a t
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
- Implement streaming first: rejected for the first multipart milestone because
  Choku needed the buffered request-body contract, part metadata model, and
  structured multipart errors before adding live request streaming.
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
  @check`, `dune build @install`, and `opam lint choku.opam`.

## Open Questions

- Should future helpers add a higher-level upload storage policy, or leave that
  entirely to applications?
