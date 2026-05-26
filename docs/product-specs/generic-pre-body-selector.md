# Generic Pre-Body Selector

## Status

Accepted

## Problem

`Server.create_router` can choose buffered or streaming request-body delivery
before reading the body because `Router.t` carries structured route metadata.
Applications that do not use `Router.t` still sometimes need the same pre-body
choice. Examples include:

- streaming only requests under an upload path while using a custom dispatcher;
- streaming based on `Content-Type`;
- keeping health checks and ordinary JSON/form endpoints buffered.

Choku should expose a small, stable request-head view and a generic selector API
without requiring applications to use the built-in router.

## Goals

- Let handler-backed servers choose `Buffered` or `Streaming` after parsing the
  request head and before reading the request body.
- Keep `Handler.t = Request.t -> Response.t`.
- Preserve existing `Server.create ?request_body_mode` behavior.
- Avoid exposing HTTP/1.1 parser internals as public API.
- Provide enough request-head information for method, path, target, raw query,
  and header based body-mode selection.
- Keep selector behavior consistent with route-level body mode.

## Non-Goals

- Selecting body mode from request body bytes.
- Per-route middleware or routing features.
- Decoded query parsing, path normalization, or percent-decoding.
- Per-route body-size limits.
- Per-route timeout policy.
- Changing `Router.t` route-level body mode behavior.
- Replacing `Server.create_router`.

## Requirements

- Add a public `Request_head.t` representing a parsed request head before body
  delivery.
- `Request_head.t` exposes method, target, query-stripped path, raw query
  string, and headers.
- `Request_head.t` contains no body and no protocol-specific connection state.
- `Request_head.make` validates the same origin-form target subset as
  `Request.make` so selectors can be unit-tested without a socket.
- Add a handler-backed server constructor that accepts a selector:

```ocaml
val create_with_request_body_selector :
  ?keep_alive:bool ->
  ?max_request_body_size:int ->
  ?max_request_head_size:int ->
  ?request_head_timeout:float option ->
  request_body_mode:(Request_head.t -> Request_body_mode.t) ->
  ?middlewares:Middleware.t list ->
  handler:Handler.t ->
  unit ->
  Server.t
```

- The selector is invoked exactly once per request after request-head parsing
  succeeds and before request body framing is consumed.
- If the selector returns `Buffered`, Choku reads the full request body before
  invoking the handler.
- If the selector returns `Streaming`, Choku invokes the handler with a
  single-consumption streaming request body.
- The selected mode is still subject to `max_request_body_size` and existing
  body-framing validation.
- If the selector raises `Eio.Cancel.Cancelled _`, Choku preserves
  cancellation.
- If the selector raises any other exception, Choku returns the existing
  `500 Internal Server Error` response when possible and closes the connection.
- If a selector fails for a `HEAD` request, Choku writes the 500 response head
  without body bytes, following normal HEAD response suppression.
- Middleware runs after request-body delivery and cannot affect selector
  decisions.
- `Server.handle` does not run selectors because it receives an already-built
  `Request.t`.
- `Server.create_router` keeps using router route metadata. Generic selectors
  are for handler-backed servers that do not use `Router.t`.

## Public Contracts

Expected API shape:

```ocaml
module Request_head : sig
  type t

  val make : meth:Method.t -> target:string -> headers:Headers.t -> t
  val meth : t -> Method.t
  val target : t -> string
  val path : t -> string
  val query_string : t -> string option
  val headers : t -> Headers.t
end

module Server : sig
  val create_with_request_body_selector :
    ?keep_alive:bool ->
    ?max_request_body_size:int ->
    ?max_request_head_size:int ->
    ?request_head_timeout:float option ->
    request_body_mode:(Request_head.t -> Request_body_mode.t) ->
    ?middlewares:Middleware.t list ->
    handler:Handler.t ->
    unit ->
    t
end
```

`Request_head` is exposed through the top-level `Choku.Request_head` module.

No selector argument is added to `Server.create` in this milestone. Keeping a
separate constructor avoids ambiguous interactions with the existing
`?request_body_mode` argument.

## Examples

Stream only upload paths:

```ocaml
let request_body_mode head =
  match Choku.Request_head.(meth head, path head) with
  | Choku.Method.POST, "/upload" -> Choku.Request_body_mode.Streaming
  | _ -> Choku.Request_body_mode.Buffered

let server =
  Choku.Server.create_with_request_body_selector
    ~request_body_mode
    ~handler
    ()
```

Stream multipart uploads based on headers:

```ocaml
let request_body_mode head =
  match Choku.Headers.get "content-type" (Choku.Request_head.headers head) with
  | Some value when String.starts_with ~prefix:"multipart/form-data" value ->
      Choku.Request_body_mode.Streaming
  | _ ->
      Choku.Request_body_mode.Buffered
```

## Open Questions

None.
