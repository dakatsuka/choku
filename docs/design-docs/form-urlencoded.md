# URL-Encoded Form Support

## Status

Accepted

## Context

URL-encoded forms fit buffered request-body parsing because typical form fields
are small key-value pairs. Multipart uploads do not fit the same model because
file parts need Eio flow streaming and explicit resource scopes.

This design keeps URL-encoded form parsing separate from multipart's buffered
and streaming APIs.

## Goals

- Add a small `Choku.Form` module above existing `Request.t` and `Body.t`.
- Keep request and body representations unchanged.
- Make malformed form input explicit with result errors.
- Preserve enough ordering information for repeated fields.
- Avoid API choices that force multipart into buffered strings.

## Non-Goals

- Multipart parsing.
- Streaming body redesign.
- Request mutation or cached parsed-form storage inside `Request.t`.
- Form validation or typed conversion.

## Proposed Design

`Form.t` is an abstract ordered multimap represented internally as a
`(string * string) list`. Accessors follow the same lookup style as other
ordered collections in Choku:

- `get` returns the first matching value;
- `get_or` returns the first matching value or a caller-provided default;
- `get_all` returns all matching values in insertion order;
- `to_list` returns every pair in insertion order.

`get_or` treats an empty present value as present; it returns the default only
when the field is absent.

`Form.decode body` parses raw URL-encoded bytes. It splits entries on `&`, then
splits each entry at the first `=`. Missing `=` means an empty value. Both field
names and values decode `+` to space and `%HH` to the byte represented by two
hex digits. Other bytes are preserved unchanged; Choku does not validate or
transcode character encodings in this milestone.

`Form.of_request request` first checks `Content-Type`. It accepts
`application/x-www-form-urlencoded` case-insensitively, ignoring parameters
after `;`, then decodes `Body.to_string (Request.body request)`.
It is a buffered compatibility helper: missing or unsupported content types
still return data errors, while an otherwise accepted request with a streaming
body raises `Invalid_argument` from the body read.

Errors are data:

```ocaml
type error =
  | Missing_content_type
  | Unsupported_content_type of string
  | Malformed_percent_encoding
```

Malformed percent escapes include a trailing `%`, a single hex digit after `%`,
or non-hex digits. Parsing returns the first malformed-encoding error.

## Contracts

The current public contract is:

```ocaml
module Form : sig
  type t

  type error =
    | Missing_content_type
    | Unsupported_content_type of string
    | Malformed_percent_encoding

  val empty : t
  val decode : string -> (t, error) result
  val of_request : Request.t -> (t, error) result
  val get : string -> t -> string option
  val get_or : default:string -> string -> t -> string
  val get_all : string -> t -> string list
  val to_list : t -> (string * string) list
  val pp_error : Format.formatter -> error -> unit
end
```

All public functions and types in `form.mli` must have block comments.

## Alternatives Considered

- Add `Request.form`: rejected for now because parsing can fail and should not
  be cached in `Request.t` before the project has a broader request-extension
  story.
- Share one `Form` abstraction with multipart: rejected because multipart parts
  need headers, filenames, content types, and future streaming bodies.
- Raise exceptions for malformed input: rejected because malformed forms are
  ordinary client input and handlers should branch explicitly.

## Third-Party Review

The initial implementation pass recorded the delegation constraint instead of a
context-free third-party review. The design is narrow, covered by behavior
tests, and leaves multipart handling as a separate design.

## Validation

The completed implementation followed Explore -> Red -> Green -> Refactor:

- added `lib/form.mli` with contracts first;
- added `test/test_form.ml` before implementation;
- tested decoding, repeated fields, empty names and values, malformed percent
  escapes, `Content-Type` handling, and accessors;
- ran `dune build @all`, `dune runtest`, `dune build @fmt`, `dune build
  @check`, `dune build @install`, and `opam lint choku.opam`.

## Open Questions

- Should a future validation module expose typed decoders over `Form.t`?
