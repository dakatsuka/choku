# Query String Support

## Status

Draft

## Context

Choku currently validates server request targets as HTTP origin-form values.
`Request.target` preserves the raw target, while `Request.path` and
`Request.path_segments` expose query-stripped path views for handlers and the
router. Query parameters are not currently parsed.

The `Form` module already implements the `application/x-www-form-urlencoded`
field model: an ordered multimap, `+` as space, percent-decoded bytes, repeated
field preservation, and explicit malformed-percent errors. Query strings need
the same small data model, without requiring handlers to parse `Request.target`
manually or tying the public API to a third-party URI type.

## Goals

- Add `Request.query_string` for the raw query component.
- Add `Request_head.query_string` with the same raw query contract for pre-body
  selectors.
- Add `Choku.Query` as an abstract ordered multimap for query parameters.
- Keep `Request.t` and `Query.t` small and explicit.
- Share URL-encoded component decoding between `Form` and `Query`.
- Leave room to use `ocaml-uri` internally later without exposing `Uri.t`.

## Non-Goals

- Replacing origin-form request-target validation with full URI parsing.
- Exposing a URI type through `Request.t`.
- Query-based routing.
- Path normalization, path percent-decoding, or route parameter decoding.
- Query parameter decoding directly from `Request_head`.

## Proposed Design

`Request.t` stores `query_string : string option` alongside the existing raw
target and query-stripped path. The value is derived from the first `?` in the
origin-form target:

- `"/items"` becomes `None`;
- `"/items?"` becomes `Some ""`;
- `"/items?page=1"` becomes `Some "page=1"`;
- `"/items?a?b"` becomes `Some "a?b"`.

`Request_head.t` stores the same `query_string : string option` value. This
keeps generic pre-body selectors from reparsing `Request_head.target` when body
mode selection depends on raw query presence or value.

`Query.t` is an abstract ordered multimap represented internally as
`(string * string) list`. Its accessors mirror `Form`:

- `get` returns the first matching value;
- `get_all` returns all values in insertion order;
- `to_list` returns every pair in insertion order.

`Query.decode raw_query` parses the raw query component without a leading `?`.
It uses the same URL-encoded field parser as `Form.decode`: entries are split
on `&`, each entry is split at the first `=`, missing `=` means an empty value,
and both names and values decode `+` as space and `%HH` as the represented byte.
A leading `?` in the supplied string is treated literally as part of the first
parameter name. Empty entries produced by `&` are preserved as empty-name,
empty-value parameters: `"&"` decodes to `[("", ""); ("", "")]`, and `"a&"`
decodes to `[("a", ""); ("", "")]`. The entire empty raw query string is the
one exception and decodes to `Query.empty`.

Decoded query names and values are byte strings. They may contain spaces,
controls, or NUL bytes if those bytes were percent-encoded in the raw request
target. Choku does not validate or transcode character encodings in this
milestone.

`Query.of_request request` parses `Request.query_string request`, using
`Query.empty` when the request has no query component.

The shared parser lives in a private module so public `Form.error` and
`Query.error` remain independent API contracts even though they currently share
the same malformed-percent behavior.

## Contracts

The first implementation should add:

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

All public functions and types in `query.mli` and `request.mli` must have block
comments. `request_head.mli` must document the symmetric raw query accessor.

## Alternatives Considered

- Expose `Uri.t`: rejected because Choku's server request target contract is
  origin-form and because public APIs should not force a third-party URI
  representation on handlers.
- Parse all request-target components with `Uri.of_string`: rejected for this
  pass because RFC3986 URI-reference parsing can interpret `//name` as
  authority, while Choku currently treats slash-prefixed origin-form targets as
  paths.
- Reuse `Form.t` directly for queries: rejected because forms and queries are
  separate HTTP concepts and may need different helpers later.
- Add `Request.query : t -> (Query.t, Query.error) result`: rejected to avoid a
  module dependency cycle and to keep fallible parsing in `Query`.

## Third-Party Review

A context-free design review found that empty entries produced by `&` were
underspecified, that product behavior should explicitly use the first `?` as
the path/query separator, and that accidental leading `?` input to
`Query.decode` should have defined behavior. The design now preserves empty
entries as empty-name, empty-value parameters, documents first-`?` splitting,
and treats a leading `?` passed to `Query.decode` as literal parameter-name
text. The review also asked to document decoded control-byte behavior and the
pre-body selector impact of query access; both are now explicit.

## Validation

Implementation should follow Explore -> Red -> Green -> Refactor:

- add `query.mli` and request contracts;
- add `test/test_query.ml` and extend `test/test_request.ml` before
  implementation;
- cover absent query, empty query, repeated parameters, empty names and values,
  `+` decoding, percent decoding, malformed percent escapes, and accessors;
- run `dune fmt`, focused tests, and `dune runtest`.

## Open Questions

- Should `ocaml-uri` become an internal dependency when Choku needs broader URI
  parsing for client redirects or server absolute-form support?
