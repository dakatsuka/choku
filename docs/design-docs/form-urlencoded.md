# URL-Encoded Form Support

## Status

Draft

## Context

The first `Body.t` implementation is a buffered, replayable byte string.
`application/x-www-form-urlencoded` fits that model because typical form fields
are small key-value pairs. Multipart uploads do not fit the same model because
file parts should eventually stream through Eio flows and resource scopes.

This design adds only URL-encoded form parsing and keeps multipart as a separate
future design with phased streaming work.

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
`(string * string) list`. Accessors mirror `Headers` and `Router.Params`:

- `get` returns the first matching value;
- `get_all` returns all matching values in insertion order;
- `to_list` returns every pair in insertion order.

`Form.decode body` parses raw URL-encoded bytes. It splits entries on `&`, then
splits each entry at the first `=`. Missing `=` means an empty value. Both field
names and values decode `+` to space and `%HH` to the byte represented by two
hex digits. Other bytes are preserved unchanged; Choku does not validate or
transcode character encodings in this milestone.

`Form.of_request request` first checks `Content-Type`. It accepts
`application/x-www-form-urlencoded` case-insensitively, ignoring parameters
after `;`, then decodes `Body.to_string (Request.body request)`.

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

The first implementation should add:

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

Not run in this implementation pass because the available multi-agent tool may
only be used when the user explicitly requests delegation. The design is narrow,
covered by behavior tests, and leaves multipart streaming as a separate design.

## Validation

Implementation should follow Explore -> Red -> Green -> Refactor:

- add `lib/form.mli` with contracts first;
- add `test/test_form.ml` before implementation;
- test decoding, repeated fields, empty names and values, malformed percent
  escapes, `Content-Type` handling, and accessors;
- run `dune build @all`, `dune runtest`, `dune build @fmt`, `dune build
  @check`, `dune build @install`, and `opam lint choku.opam`.

## Open Questions

- Should query parsing reuse `Form.t` in a future URI module?
- Should a future validation module expose typed decoders over `Form.t`?
