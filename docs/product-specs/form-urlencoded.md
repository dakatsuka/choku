# URL-Encoded Form Support

## Status

Draft

## Problem

Choku can already expose buffered request bodies, but handlers need a small
and predictable way to read `application/x-www-form-urlencoded` form submissions
without committing multipart upload behavior to the same API.

## Goals

- Provide an optional `Choku.Form` module for URL-encoded form bodies.
- Preserve repeated field order.
- Decode `+` as space and percent-encoded bytes.
- Return structured parse errors instead of raising for malformed user input.
- Keep the API separate from future multipart handling.

## Non-Goals

- `multipart/form-data` parsing.
- Streaming uploads or file storage.
- Form validation, typed converters, CSRF helpers, or sessions.
- Character set transcoding or UTF-8 validation.
- Query-string parsing.

## Requirements

- `Form.t` is an immutable ordered multimap of field names to values.
- `Form.decode` parses an `application/x-www-form-urlencoded` payload string.
- `Form.of_request` checks `Content-Type` and decodes `Request.body`.
- `Content-Type` matching is case-insensitive for the media type and ignores
  parameters such as `charset=utf-8`.
- Missing `Content-Type` returns `Missing_content_type`.
- Unsupported `Content-Type` returns `Unsupported_content_type value`.
- Malformed percent escapes return `Malformed_percent_encoding`.
- Empty payloads decode to `Form.empty`.
- Entries are separated by `&`.
- A field without `=` has an empty value.
- Empty field names and values are preserved.
- Repeated fields are preserved in insertion order.

## Public Contracts

Initial contracts:

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

Public `.mli` files must document these contracts with block comments.

## Examples

```ocaml
match Choku.Form.of_request request with
| Ok form -> (
    match Choku.Form.get "email" form with
    | Some email -> Choku.Response.text ("email=" ^ email ^ "\n")
    | None -> Choku.Response.text ~status:Choku.Status.bad_request "missing email\n")
| Error error ->
    Choku.Response.text ~status:Choku.Status.bad_request
      (Format.asprintf "%a\n" Choku.Form.pp_error error)
```

## Open Questions

- Should a later API add query-string parsing with the same ordered multimap
  behavior?
- Should a later validation layer build typed field converters on top of
  `Form.t`?
