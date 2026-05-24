# HTTP/1.1 Persistent Connections

## Status

Accepted

## Problem

Choku currently closes each HTTP/1.1 connection after one response. That is
simple, but it makes Choku less suitable as an application server behind nginx,
ALB, ELB, or similar reverse proxies that can reuse backend HTTP/1.1
connections.

Choku should support the HTTP/1.1 persistent connection default without growing
into a fully featured edge server.

## Goals

- Reuse plain HTTP/1.1 backend connections for ordinary buffered requests.
- Preserve Choku's small direct-style Eio server API.
- Keep request handling sequential per connection.
- Respect `Connection: close` from requests and responses.
- Keep error handling conservative by closing connections after protocol or
  handler failures.
- Make keep-alive optional for users who need the previous close-after-response
  behavior.

## Non-Goals

- Concurrent request processing on one HTTP/1.1 connection.
- Explicit support for HTTP/1.1 request pipelining beyond sequential processing
  in wire order.
- HTTP/1.0 keep-alive.
- Chunked response bodies.
- Response streaming.
- Connection upgrade, CONNECT tunneling, or WebSocket.
- TLS, HTTP/2, or HTTP/3.
- A separate public keep-alive idle timeout setting in this milestone.
- A public maximum-requests-per-connection setting in this milestone.

## Requirements

- `Server.create` and `Server.create_router` expose `?keep_alive:bool`.
- `keep_alive` defaults to `true`.
- When `keep_alive = false`, Choku preserves the previous behavior: one
  request-response exchange per accepted connection, `Connection: close` in the
  response, then close.
- When `keep_alive = true`, Choku may process multiple HTTP/1.1 requests on the
  same connection.
- Requests on a connection are processed sequentially in wire order.
- Choku does not start handling request N+1 until request N has produced and
  written its response.
- Responses on reusable connections include `Connection: keep-alive`.
- Responses that will close the connection include `Connection: close`.
- `Connection` header fields are interpreted as case-insensitive comma-separated
  tokens across all repeated fields.
- A request with any `close` connection token causes Choku to write one response
  and then close.
- If a handler explicitly sets any response `Connection` field containing a
  `close` token, Choku writes that response and then closes. The server still
  owns final wire serialization of the `Connection` header.
- If a client closes a persistent connection before sending any bytes of the
  next request, Choku closes quietly without writing a synthetic error response.
- If a client closes after sending a partial next request head, Choku treats that
  as malformed request framing and writes the existing 400 response when
  possible.
- Protocol parse errors, unsupported versions, invalid request targets,
  malformed headers, invalid body framing, request-head limits, request-head
  timeout, and request body-size errors close the connection after the error
  response when a response can be written.
- Uncaught non-cancellation handler exceptions close the connection after the
  synthesized 500 response.
- `Eio.Cancel.Cancelled _` remains cancellation and is not converted into an
  HTTP response.
- Buffered fixed-length and buffered chunked request bodies are eligible for
  connection reuse after the response because the server has consumed their
  bodies before invoking the handler.
- Streaming request bodies are not reused in this milestone. If a route or
  server uses `Streaming`, Choku writes one response with `Connection: close`
  and closes the connection.
- `request_head_timeout`, when configured, applies to each request-head read on
  a persistent connection, including idle time between requests.
- Because `request_head_timeout` defaults to `None`, direct deployments that are
  not protected by nginx, ALB, ELB, or similar infrastructure should configure a
  finite timeout to avoid idle keep-alive connections holding fibers
  indefinitely.
- Existing `Response.t` serialization remains buffered and `Content-Length`
  based. Choku does not need chunked responses to support this milestone.

## Public Contracts

Expected API shape:

```ocaml
val create :
  ?keep_alive:bool ->
  ?max_request_body_size:int ->
  ?max_request_head_size:int ->
  ?request_head_timeout:float option ->
  ?request_body_mode:request_body_mode ->
  ?middlewares:Middleware.t list ->
  handler:Handler.t ->
  unit ->
  t

val create_router :
  ?keep_alive:bool ->
  ?max_request_body_size:int ->
  ?max_request_head_size:int ->
  ?request_head_timeout:float option ->
  ?middlewares:Middleware.t list ->
  Router.t ->
  t
```

No public connection object, connection pool, pipelining API, request counter,
or keep-alive timeout API is introduced.

## Examples

Default application-server behavior:

```ocaml
let server = Choku.Server.create ~handler ()
```

Close-after-response compatibility:

```ocaml
let server = Choku.Server.create ~keep_alive:false ~handler ()
```

## Open Questions

None.
