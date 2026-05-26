# Query String Support

## Status

Draft

## Problem

Handlers can inspect `Request.target`, but applications need a small and
predictable way to read URL query strings without depending on Choku's internal
request-target representation or exposing a third-party URI type.

## Goals

- Expose the raw query string from server requests.
- Expose the same raw query string from pre-body request heads.
- Provide a `Choku.Query` ordered multimap for decoded query parameters.
- Preserve repeated parameter order.
- Decode `+` as space and percent-encoded bytes.
- Return structured parse errors instead of raising for malformed user input.
- Keep the public API independent of any URI parsing library used internally.

## Non-Goals

- Replacing `Request.target`, `Request.path`, or `Request.path_segments` with a
  full URI representation.
- Query-based routing.
- URI normalization, dot-segment removal, path percent-decoding, or repeated
  slash collapsing.
- Typed parameter conversion or validation.
- Exposing `Uri.t` or another third-party URI type in Choku's public API.

## Requirements

- `Request.query_string request` returns the raw query component without the
  leading `?`.
- Requests without `?` return `None`.
- Requests with a trailing `?` return `Some ""`, preserving the distinction
  between an absent query component and an empty query component.
- The first `?` separates path from query, so `"/items?a?b"` returns
  `Some "a?b"`.
- `Request_head.query_string` follows the same raw query contract as
  `Request.query_string`.
- `Query.t` is an immutable ordered multimap of parameter names to values.
- `Query.decode` parses a raw query string.
- `Query.decode` expects input without a leading `?`; a leading `?` in the
  supplied string is treated as part of the first parameter name.
- `Query.of_request` parses `Request.query_string`; requests without a query
  string decode as `Query.empty`.
- Empty query strings decode to `Query.empty`.
- Entries are separated by `&`.
- Empty entries produced by `&` are preserved as empty-name, empty-value
  parameters, except that the entire empty query string decodes to `Query.empty`.
- A parameter without `=` has an empty value.
- Empty parameter names and values are preserved.
- Repeated parameters are preserved in insertion order.
- Parameter names and values decode `+` as space and decode percent-encoded
  bytes.
- Character encoding is not validated or transcoded. Decoded query names and
  values may contain bytes such as spaces or controls that are rejected in the
  raw request target unless percent-encoded.
- Malformed percent escapes return `Malformed_percent_encoding`.

## Public Contracts

Initial contracts:

```ocaml
module Query : sig
  type t

  type error = Malformed_percent_encoding

  val empty : t
  val decode : string -> (t, error) result
  val of_request : Request.t -> (t, error) result
  val get : string -> t -> string option
  val get_all : string -> t -> string list
  val to_list : t -> (string * string) list
  val pp_error : Format.formatter -> error -> unit
end

module Request : sig
  val query_string : t -> string option
end

module Request_head : sig
  val query_string : t -> string option
end
```

Public `.mli` files must document these contracts with block comments.

## Examples

```ocaml
match Choku.Query.of_request request with
| Ok query -> (
    match Choku.Query.get "page" query with
    | Some page -> Choku.Response.text ("page=" ^ page ^ "\n")
    | None -> Choku.Response.text "page=1\n")
| Error error ->
    Choku.Response.text ~status:Choku.Status.bad_request
      (Format.asprintf "%a\n" Choku.Query.pp_error error)
```

## Open Questions

- Should a later API add an internal `ocaml-uri` dependency for broader URI
  parsing while keeping `Choku.Query` as the public surface?
