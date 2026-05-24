# Minimal Router DSL

## Status

Draft

## Problem

Choku's first server milestone exposes a low-level `Handler.t` contract. Users
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
- Routes may opt into streaming request bodies before the server reads the body
  when the application uses `Server.create_router`. `Router.to_handler`
  behavior remains useful for tests and server-wide body mode users with
  already-constructed requests.
- `HEAD` requests automatically fall back to matching `GET` routes unless an
  explicit `HEAD` route matches first.
- Path matches with disallowed methods return `405 Method Not Allowed` with an
  `Allow` header as specified by
  [Router HEAD And 405 Semantics](router-head-and-405.md).
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
  type body_mode = Request_body_mode.t

  val route :
    ?request_body_mode:body_mode ->
    Method.t ->
    string ->
    route_handler ->
    t ->
    t

  val get : ?request_body_mode:body_mode -> string -> route_handler -> t -> t
  val post : ?request_body_mode:body_mode -> string -> route_handler -> t -> t
  val put : ?request_body_mode:body_mode -> string -> route_handler -> t -> t
  val patch : ?request_body_mode:body_mode -> string -> route_handler -> t -> t
  val delete :
    ?request_body_mode:body_mode -> string -> route_handler -> t -> t
  val options :
    ?request_body_mode:body_mode -> string -> route_handler -> t -> t
  val to_handler : t -> Handler.t
end
```

Route-level body-mode selection is specified in
[Route-Level Body Mode](../design-docs/route-level-body-mode.md).

Public `.mli` files must document these contracts with block comments.

## Examples

```ocaml
let router =
  Choku.Router.empty
  |> Choku.Router.get "/health" (fun _params _request ->
       Choku.Response.text "ok\n")
  |> Choku.Router.get "/users/:id" (fun params _request ->
       match Choku.Router.Params.get "id" params with
       | Some id -> Choku.Response.text ("user=" ^ id ^ "\n")
       | None -> Choku.Response.text ~status:Choku.Status.bad_request "bad route\n")

let server =
  Choku.Server.create
    ~middlewares:[ add_server_header ]
    ~handler:(Choku.Router.to_handler router)
    ()
```

Route-level streaming body mode:

```ocaml
let router =
  Choku.Router.empty
  |> Choku.Router.post
       ~request_body_mode:Choku.Request_body_mode.Streaming
       "/upload"
       upload

let server = Choku.Server.create_router router
```

## Open Questions

- Should a later router milestone add regex segments or typed path converters?
- Should percent-decoding happen in `Request.path`, in `Router`, or in a future
  URI module?
- Should a later router milestone support trailing-slash routes or repeated
  slash semantics?
- Should a later milestone add a generic pre-body selector API in addition to
  the router-specific `Server.create_router` entry point?
