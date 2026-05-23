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

  module Part : sig
    type t

    val headers : t -> Headers.t
    val name : t -> string option
    val filename : t -> string option
    val content_type : t -> string option
    val body : t -> Body.t
  end

  val decode : boundary:string -> string -> (t, error) result
  val of_request : Request.t -> (t, error) result
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

- Should Phase 2 expose `copy_part_to_flow` before `Body.t` becomes streaming?
- Should Phase 3 redesign `Body.t` as replayable-buffered-or-streaming, or add a
  separate request streaming API?
