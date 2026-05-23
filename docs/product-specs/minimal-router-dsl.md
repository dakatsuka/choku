# Minimal Router DSL

## Status

Draft

## Problem

Camelio's first server milestone exposes a low-level `Handler.t` contract. Users
can already build small servers with pattern matching, but real applications
need a small routing layer that maps methods and paths to endpoint handlers
without making routing mandatory for the server.

## Goals

- Provide an optional router that compiles to `Handler.t`.
- Support method-specific route registration such as `Router.get "/health"`.
- Support deterministic first-match route selection.
- Support simple named path parameters without changing `Request.t`.
- Keep middleware composition at the existing `Handler.t` layer.
- Preserve compatibility with a future richer routing DSL.

## Non-Goals

- Regular expression route patterns.
- Host, scheme, header, query-string, or body-based routing.
- Automatic `HEAD` handling for `GET` routes.
- Automatic `405 Method Not Allowed` responses.
- Route groups, nested routers, mounts, filters, or per-route middleware.
- URL generation.
- Percent-decoding or path normalization.
- HTTP client, TLS, HTTP/2, or HTTP/3 behavior.

## Requirements

- `Router.t` is an immutable route collection.
- `Router.to_handler router` returns a normal `Handler.t`.
- Middleware remains outside the router: users may pass `Router.to_handler
  router` to `Server.create ~middlewares`.
- Routes are tested in insertion order. The first route whose method and path
  pattern match handles the request.
- Routing uses `Request.path`, so query strings do not affect route selection.
- Static path patterns match exactly.
- Named parameter segments use `:name` and match one non-empty path segment.
- Empty route-pattern segments are invalid except for the root pattern `/`, so
  `/users/` and `/users//posts` are rejected during registration.
- Route parameters are exposed through `Router.Params.t`, not by mutating or
  extending `Request.t`.
- Missing routes return a configurable not-found handler, defaulting to `404 Not
  Found` with a text body.
- Invalid route patterns raise `Invalid_argument` during route registration.

## Public Contracts

Initial contracts:

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

Public `.mli` files must document these contracts with block comments.

## Examples

```ocaml
let router =
  Camelio.Router.empty
  |> Camelio.Router.get "/health" (fun _params _request ->
       Camelio.Response.text "ok\n")
  |> Camelio.Router.get "/users/:id" (fun params _request ->
       match Camelio.Router.Params.get "id" params with
       | Some id -> Camelio.Response.text ("user=" ^ id ^ "\n")
       | None -> Camelio.Response.text ~status:Camelio.Status.bad_request "bad route\n")

let server =
  Camelio.Server.create
    ~middlewares:[ add_server_header ]
    ~handler:(Camelio.Router.to_handler router)
    ()
```

## Open Questions

- Should a later router milestone add regex segments or typed path converters?
- Should a later router milestone provide automatic `HEAD` or `405 Method Not
  Allowed` behavior?
- Should percent-decoding happen in `Request.path`, in `Router`, or in a future
  URI module?
- Should a later router milestone support trailing-slash routes or repeated
  slash semantics?
