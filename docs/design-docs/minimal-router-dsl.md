# Minimal Router DSL

## Status

Draft

## Context

Camelio now has a minimal HTTP/1.1 server where `Server.run` invokes a low-level
`Handler.t = Request.t -> Response.t`. The next layer should make small
applications easier to write while preserving the core design: the server only
needs a handler, and routing remains optional.

The earlier API discussion intentionally deferred a Hono/Sinatra-style DSL until
the handler and middleware contracts existed. This design adds a first router
that is deliberately smaller than a full web framework and leaves room for
regex paths, typed converters, route groups, and per-route middleware later.

## Goals

- Add `Camelio.Router` as an optional layer above `Handler.t`.
- Keep `Server` unchanged.
- Keep route matching deterministic and easy to test without sockets.
- Keep path parameters out of `Request.t` so shared HTTP values remain useful to
  a future HTTP client.
- Use per-module tests in `test/test_router.ml`.

## Non-Goals

- Changing `Handler.t`, `Server.t`, or middleware semantics.
- Adding regex matching, typed parameters, mounts, route groups, or per-route
  middleware.
- Adding URI parsing, percent-decoding, normalization, or query routing.
- Adding 405 generation or automatic `HEAD` fallback.

## Proposed Design

`Router.t` is an immutable value containing:

- a list of compiled route entries in insertion order;
- a not-found `Handler.t`.

Each route entry stores:

- `Method.t`;
- the original pattern string for diagnostics and future introspection;
- a compiled path pattern;
- a route handler.

The route handler type is router-specific:

```ocaml
type route_handler = Params.t -> Request.t -> Response.t
```

This lets parameterized routes expose captures without adding route-specific
metadata to `Request.t`. `Router.to_handler router` returns a plain
`Handler.t`, so the server and middleware layers do not need to know the router
exists.

Route registration appends entries. `Router.to_handler` checks entries in the
same order they were registered and invokes the first method and pattern match.
This makes shadowing explicit:

```ocaml
Router.empty
|> Router.get "/users/:id" show_user
|> Router.get "/users/me" show_me
```

In this example `/users/me` is handled by `show_user` because it was registered
first. Users who want the static route to win must register it first.

## Path Pattern Contract

The first router supports a small path pattern grammar:

```text
pattern       = "/" | "/" segment *( "/" segment )
segment       = static | parameter
static        = one or more characters except "/"
parameter     = ":" name
name          = ASCII letter or "_" followed by ASCII letters, digits, "_" or "-"
```

Static segments match exactly. Parameter segments match one non-empty path
segment and bind the raw segment text to the parameter name. The first router
does not support empty path segments in route patterns. As a result, `"/"` is
the only pattern that may end with `/`; patterns such as `"/users/"` and
`"/users//posts"` are invalid. The root pattern `"/"` matches only `"/"`.

Invalid patterns raise `Invalid_argument` during registration. Invalid patterns
include:

- an empty string;
- a pattern that does not start with `/`;
- an empty segment, including trailing slashes outside the root pattern;
- a segment containing an empty parameter name;
- a parameter name outside the allowed grammar;
- duplicate parameter names in the same pattern.

The router matches against `Request.path`, not `Request.target`, so query
strings are ignored. The router does not percent-decode, normalize dot
segments, collapse repeated slashes, or reject encoded slashes. Request paths
with empty segments may still exist, but they only match if a future router
milestone explicitly adds empty-segment pattern support.

## Contracts

The first implementation should add:

```ocaml
module Router : sig
  type t

  module Params : sig
    type t

    val empty : t
    val get : string -> t -> string option
    val to_list : t -> (string * string) list
  end

  type route_handler = Params.t -> Request.t -> Response.t

  val empty : t
  val not_found : Handler.t -> t -> t
  val route : Method.t -> string -> route_handler -> t -> t
  val get : string -> route_handler -> t -> t
  val post : string -> route_handler -> t -> t
  val put : string -> route_handler -> t -> t
  val patch : string -> route_handler -> t -> t
  val delete : string -> route_handler -> t -> t
  val options : string -> route_handler -> t -> t
  val to_handler : t -> Handler.t
end
```

All public functions and types in `router.mli` must have block comments.

`Router.empty` uses a default not-found handler equivalent to:

```ocaml
fun _request ->
  Response.text ~status:Status.not_found "Not Found\n"
```

`Router.not_found handler router` returns a router with the same routes and a
replacement not-found handler.

`Router.route meth pattern handler router` validates and compiles `pattern`,
then appends it to the route list. Convenience functions call `route` with the
corresponding `Method.t` constructor.

`Router.Params.to_list` preserves the pattern order of captured parameters.
`Router.Params.get` returns the first value for a name, though duplicate names
are rejected at pattern compile time.

## Alternatives Considered

- Store route params in `Request.t`: rejected because route parameters are not
  HTTP protocol data and would couple shared HTTP request values to the router.
- Make `Router.get` accept `Handler.t`: rejected for this milestone because
  parameterized routes would have no clear place to expose captures.
- Add regex paths immediately: rejected because regular expression syntax,
  capture naming, dependency choice, and performance behavior deserve a
  separate design.
- Generate 405 responses when a path matches another method: deferred to avoid
  committing to method-table behavior before route introspection exists.

## Third-Party Review

Initial context-free review found that trailing-slash and empty-segment
semantics were inconsistent. This design now makes empty route-pattern segments
invalid except for the root pattern `"/"`.

The same review found no need for an ADR because this is a narrow optional
module rather than a major architectural change.

## Validation

Implementation should follow Explore -> Red -> Green -> Refactor:

- add `lib/router.mli` with contracts first;
- add `test/test_router.ml` before implementation;
- test static route matching, method matching, first-match order, parameter
  captures, query ignoring, default not-found, custom not-found, invalid
  patterns including empty segments, and `Params` accessors;
- run `dune build @all`, `dune runtest`, `dune build @fmt`, `dune build
  @check`, `dune build @install`, and `opam lint camelio.opam`;
- request context-free implementation review after the code is written.

## Open Questions

- Should a future router expose route introspection for documentation or
  OpenAPI generation?
- Should a later milestone add regex routes or typed path converters first?
