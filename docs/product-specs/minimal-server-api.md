# Minimal Server API

## Status

Accepted

## Problem

Choku needs a compact public API that lets OCaml 5.4 users run an Eio-native
HTTP application server while leaving room for HTTP Client, TLS, and future
protocol versions. The API should keep core HTTP values explicit and small
without becoming a full web framework.

## Goals

- Users can provide a plain OCaml handler function for HTTP requests.
- Users can wrap handlers with middleware for cross-cutting behavior.
- Users can use the built-in router when method-and-path dispatch is useful.
- Users can choose buffered or streaming request body delivery.
- Users can return buffered or streaming responses.
- Handler tests can run without opening a network socket.
- Shared HTTP primitives remain compatible with future HTTP Client design where
  their contracts fit.

## Non-Goals

- HTTP Client APIs.
- TLS support.
- HTTP/2 or HTTP/3 support.
- Web framework features such as controllers, templates, sessions, or dependency
  injection.
- Static file serving, SSE helpers, compression, range requests, or upload
  storage policy.
- Reverse proxy or edge-server behavior.

## Requirements

- The public handler contract is a function that receives a `Request.t` and
  returns a `Response.t`.
- Middleware is a first-class transformation from handler to handler.
- Middleware list order is normative: applying `[a; b]` to handler `h` produces
  `a (b h)`, so `a` observes the request first and response last.
- Server startup accepts an Eio switch, Eio network capability, socket address,
  and server value.
- The caller owns the Eio switch passed to the server. Choku attaches listener
  resources and connection fibers to that switch, but does not close it.
- Applications may use Eio capabilities captured by closure inside handlers.
- The API must not expose `Lwt.t`, `Async.Deferred.t`, `cohttp` types, or
  callback-based scheduling.
- Future HTTP Client, HTTP/2, and HTTP/3 designs should reuse shared
  lower-level protocol values only where their contracts fit.
- Request bodies are buffered and replayable by default.
- `Server.create ?request_body_mode:Buffered` reads the full request body before
  invoking the handler and provides a replayable `Body.t`.
- `Server.create ?request_body_mode:Streaming` invokes the handler with a
  single-consumption `Body.t` backed by a source capped to the declared
  `Content-Length` or decoded chunked body limit.
- `Server.create_router` selects request body delivery from router route
  metadata before request body delivery.
- `Server.create_with_request_body_selector` selects request body delivery from
  `Request_head.t` before request body delivery for handler-backed custom
  dispatchers.
- The default maximum request body size is `1_048_576` bytes and can be
  overridden with `Server.create ?max_request_body_size`.
- The maximum request head size and request head timeout can be configured with
  `?max_request_head_size` and `?request_head_timeout`.
- Over-limit request bodies do not invoke the handler when the overflow is
  discovered before handler invocation and produce `413 Payload Too Large` with
  `connection: close` when a response can still be written.
- Uncaught non-cancellation handler exceptions before response writing produce a
  `500 Internal Server Error` response with `content-type:
  text/plain; charset=utf-8`, `connection: close`, and body
  `Internal Server Error\n`; the server closes the connection afterward.
- Exceptions matching `Eio.Cancel.Cancelled _` remain cancellation and are not
  converted into HTTP 500.
- `Response.text` creates buffered text responses.
- `Response.stream` creates callback-scoped streaming responses.
- Streaming response callbacks run after the handler returns, while the server
  serializes the response.
- Streaming response callbacks are single-consumption and must write exactly
  `~content_length` bytes when a content length is provided.
- `Server.handle` invokes the composed handler with an already-built
  `Request.t`; it does not run route-level or generic pre-body body-mode
  selection.

## Public Contracts

Core handler contracts:

```ocaml
module Handler : sig
  type t = Request.t -> Response.t
end

module Middleware : sig
  type t = Handler.t -> Handler.t
end
```

Server construction:

```ocaml
module Server : sig
  type t
  type request_body_mode = Request_body_mode.t = Buffered | Streaming

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

  val create_with_request_body_selector :
    ?keep_alive:bool ->
    ?max_request_body_size:int ->
    ?max_request_head_size:int ->
    ?request_head_timeout:float option ->
    request_body_mode:(Request_head.t -> request_body_mode) ->
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
end
```

The public `.mli` files are the authoritative API contracts. Product specs
describe behavior and compatibility expectations, not every helper function.

The server exposes abstract `Request.t`, `Request_head.t`, `Response.t`, and
`Body.t` types with constructors/accessors for method, target, path, path
segments, query string, headers, status, and body values. Bodies constructed
directly with `Body.string` are buffered and replayable. Server-created request
streaming bodies and response-stream writer bodies are single-consumption.

`Request.path_segments` exposes `Request.path` as URL path segments without the
leading slash for direct handler pattern matching. It preserves empty segments
and raw segment text; it does not percent-decode, normalize dot segments, or
collapse repeated slashes.

`Request.query_string` exposes the raw query component without the leading `?`,
if the request target contains one. Decoded query parameter behavior is
specified by [Query String Support](query-string.md). `Request_head` exposes
the same raw query string before body delivery.

`Request.t` and `Response.t` are server/application oriented. HTTP Client uses
separate client request and response types, while sharing lower-level protocol
values such as `Method.t`, `Headers.t`, `Status.t`, and buffered `Body.t` where
their contracts fit.

Header lookup is case-insensitive. Header insertion order is preserved.
`Headers.add` appends, `Headers.set` removes case-insensitive matches and
appends the replacement, `Headers.remove` removes case-insensitive matches,
`Headers.get` returns the first matching value, and `Response.with_header` uses
`Headers.set`. `Response.add_header` uses `Headers.add` for repeated response
fields such as `Set-Cookie`.

HTTP method tokens are case-sensitive. Invalid method tokens, invalid status
codes outside 100 through 599, invalid header names or values, and invalid
server request targets raise `Invalid_argument`. Standard response statuses are
available as named `Status.t` values, while `Status.of_code` remains available
for custom valid codes. Applications can inspect a status code's class with
`Status.class_`.

The current server supports plain HTTP connections only. It must not promise
HTTPS or TLS behavior, but protocol code is designed around Eio flows so future
TLS transport support can be introduced without changing handler contracts.

The current server supports HTTP/1.1 only. It must not promise HTTP/2 or HTTP/3
behavior, but the handler and middleware APIs avoid depending on HTTP/1.1
connection details so later protocol versions can target the same shared
request/response contract where appropriate.

## Examples

Minimal handler:

```ocaml
let hello _request =
  Choku.Response.text "hello"
```

Middleware shape:

```ocaml
let add_server_header next request =
  request
  |> next
  |> Choku.Response.with_header "server" "choku"
```

Router-backed server:

```ocaml
let router =
  Choku.Router.empty
  |> Choku.Router.get "/" (fun _ctx -> Choku.Response.text "hello")

let server = Choku.Server.create_router router
```

Streaming response:

```ocaml
let stream_report _request =
  Choku.Response.stream (fun sink ->
      List.iter (fun line -> Eio.Flow.copy_string line sink) report_lines)
```

Future client compatibility keeps server and client request/response values
separate:

```ocaml
(* Illustrative only; Client is not part of the server API milestone. *)
let outbound_request =
  Choku.Client.Request.make
    ~meth:Choku.Method.GET
    ~url:"http://example.test/"
    ()
```

## Open Questions

- Which URI or request-target helpers, if any, should be shared between server
  requests and client request construction after the client API has settled?
- Which TLS abstraction, if any, should be used by future server-side TLS
  support?
- What body, trailer, multiplexing, and lifecycle abstractions are needed before
  HTTP/2 or HTTP/3 can be designed?
