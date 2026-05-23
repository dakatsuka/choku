# Route-Level Body Mode

## Status

Implemented

## Context

`Server.create ?request_body_mode` currently selects request body delivery mode
for the whole server. `Buffered` is convenient for JSON, URL-encoded forms, and
small multipart requests. `Streaming` is required for large multipart uploads.

Real applications often need both modes in the same server:

- `GET /health` and ordinary JSON/form endpoints should stay buffered and
  replayable.
- `POST /upload` should receive a single-consumption streaming body.

The current router compiles to `Handler.t`, which runs after the HTTP server has
already decided whether to buffer or stream the request body. Route-level body
mode therefore cannot be implemented purely inside `Router.to_handler`; the
HTTP/1.1 request head must be matched before body reading begins.

## Goals

- Let applications choose `Buffered` or `Streaming` per route.
- Preserve `Server.create` default behavior and `Router.to_handler`.
- Keep routing optional; direct `Handler.t` users should not need the router.
- Avoid reading request bodies before the route policy is known.
- Keep route matching semantics consistent with `Router.to_handler`.
- Keep unmatched routes safe and predictable.

## Non-Goals

- Per-route middleware, route groups, mounts, filters, or 405 handling.
- Body-mode selection based on headers, query strings, or request body content.
- Changing `Handler.t`.
- Making streaming request bodies replayable.

## Design

Move the shared body-mode type into a server-independent module, while keeping
the current `Server` constructors available for compatibility:

```ocaml
module Request_body_mode : sig
  type t = Buffered | Streaming
end

module Server : sig
  type request_body_mode = Request_body_mode.t =
    | Buffered
    | Streaming
end
```

This avoids a `Router` -> `Server` dependency when `Server.create_router` also
needs to accept `Router.t`.

Extend router route registration with an optional body mode:

```ocaml
module Router : sig
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
end
```

If omitted, the route uses `Buffered`. This mirrors the current server default
and keeps existing router code semantically stable.

`Router.to_handler` remains available and ignores pre-body routing concerns
because it receives an already-built `Request.t`. It continues to be useful for
tests and for users who are happy with server-wide body mode.

Add a server entry point that accepts a router directly:

```ocaml
module Server : sig
  val create_router :
    ?max_request_body_size:int ->
    ?middlewares:Middleware.t list ->
    Router.t ->
    t
end
```

`Server.create_router router` lets the HTTP protocol layer ask the router for
the matching route's body mode after parsing the request head and before reading
the body. It then builds the `Request.t` with the selected body mode and invokes
the same matched route handler.

This design deliberately keeps route-level body mode attached to the router
entry point rather than overloading `Server.create ~handler`. A plain
`Handler.t` does not contain enough structured routing information to select
body mode before body reading.

## Matching And Fallback Semantics

The route selected for body mode must be the same route that handles the
request. Matching uses the existing router semantics:

- method and path pattern match;
- query strings are ignored through `Request.path`-equivalent path extraction;
- routes are checked in insertion order;
- first match wins.

Unmatched requests should use `Buffered`. The body is then read according to the
server's existing buffered policy before the router's not-found handler runs.
This avoids surprising not-found handlers with a streaming body and preserves
today's default behavior. Unmatched request bodies are still subject to
`max_request_body_size`; an oversized unmatched request is rejected with the
existing payload-too-large behavior before the not-found handler runs.

Invalid request heads, unsupported transfer encodings, invalid content lengths,
and over-limit bodies keep the existing server behavior. A route marked
`Streaming` still rejects declared bodies over `max_request_body_size` before
invoking the handler.

## Middleware And `Server.handle`

`Server.create_router ?middlewares router` should apply middleware exactly once
around the final router handler, matching:

```ocaml
Server.create ~middlewares ~handler:(Router.to_handler router) ()
```

for already-constructed requests.

Middleware cannot affect route-level body-mode selection. Body-mode selection
happens after request-head parsing and before body reading. Middleware receives
the constructed `Request.t` after the body has already been delivered as
buffered or streaming according to the matched route policy.

`Server.handle` remains a handler-level test/protocol-adapter helper. When
called on a server created with `Server.create_router`, it invokes the router
handler with the already-built `Request.t`. It does not and cannot perform
pre-body body-mode selection because the request body has already been
constructed.

## Usage

```ocaml
let upload params request =
  let user_id = Camelio.Router.Params.get "id" params in
  match Camelio.Multipart.Streaming.iter_request request ~on_part:save_part with
  | Ok () -> Camelio.Response.text "uploaded\n"
  | Error error ->
      Camelio.Response.text ~status:Camelio.Status.bad_request
        (Format.asprintf "%a\n" Camelio.Multipart.pp_error error)

let router =
  Camelio.Router.empty
  |> Camelio.Router.get "/health" (fun _params _request ->
       Camelio.Response.text "ok\n")
  |> Camelio.Router.post
       ~request_body_mode:Camelio.Request_body_mode.Streaming
       "/users/:id/avatar"
       upload

let server = Camelio.Server.create_router router
```

Routes without `~request_body_mode` stay buffered:

```ocaml
let router =
  Camelio.Router.empty
  |> Camelio.Router.post "/login" login_form
  |> Camelio.Router.post
       ~request_body_mode:Camelio.Request_body_mode.Streaming
       "/upload"
       upload
```

Direct handler users keep using server-wide mode:

```ocaml
let server =
  Camelio.Server.create
    ~request_body_mode:Camelio.Server.Streaming
    ~handler
    ()
```

## Implementation Shape

The router needs an internal pre-body matcher. It should share the same compiled
route entries used by `Router.to_handler` so body-mode selection and handler
selection cannot drift.

The protocol layer should parse the request head, derive the same path string
that `Request.path` would expose, ask the router for the matching route policy,
read or expose the body accordingly, then invoke the selected route handler.

Implementation should avoid exposing HTTP/1.1 parser internals as public router
API. If an internal bridge is needed, keep it hidden under an internal module or
server/router private function.

## Alternatives Considered

- Add `?request_body_mode` to middleware: rejected because middleware runs after
  the request body has already been delivered.
- Store body mode in `Request.t`: rejected because the choice must happen before
  `Request.t` is fully constructed.
- Make `Router.to_handler` enforce route body mode: rejected because it receives
  an already-built request and cannot influence buffering.
- Add a generic `request_body_mode_selector : Request_head.t -> mode` to
  `Server.create`: possible later, but it would require exposing a stable
  pre-body request-head type. The router-specific entry point is narrower.
- Make unmatched routes streaming: rejected because not-found handlers should
  remain simple and replayable by default.

## Third-Party Review

Context-free review found a blocking dependency-cycle risk in the first API
sketch: `Router` depended on `Server.request_body_mode` while `Server` gained a
`create_router : Router.t -> t` entry point. The design now moves the shared
mode type to `Request_body_mode.t` and leaves `Server.request_body_mode` as a
compatibility alias.

The same review asked for clearer `Server.handle`, middleware, unmatched
oversized request, and matcher-parity contracts. Those are now specified above
and included in the validation plan. Re-review found no remaining blockers.

## Validation

Implementation includes tests for:

- `Router.to_handler` remains backward-compatible and buffered-mode agnostic.
- `Server.create_router` uses buffered bodies for routes without explicit mode.
- a route marked `Streaming` receives a non-buffered body.
- a buffered route and a streaming route can coexist on one server.
- first-match route order also controls body-mode selection.
- unmatched requests use buffered body mode and not-found handler behavior.
- oversized unmatched requests are rejected before the not-found handler runs.
- middleware wraps router handling exactly once and cannot affect body-mode
  selection.
- `Server.handle` on a router-created server invokes the router handler with
  the already-constructed request and does not attempt body-mode selection.
- internal pre-body matcher behavior matches `Router.to_handler` for insertion
  order, parameter captures, root routes, static routes, method mismatch, and
  query-string ignoring.
- over-limit bodies are rejected before route handler invocation in both modes.
- malformed request heads keep existing HTTP/1.1 error behavior.

Network tests should cover at least one server with both a buffered route and a
streaming multipart upload route.

## Open Questions

- Should a later generic selector API be added for users who do not want
  `Router.t` but still need pre-body body-mode selection?
