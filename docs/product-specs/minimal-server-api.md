# Minimal Server API

## Status

Draft

## Problem

Camelio needs an initial public API that lets OCaml 5.4 users run a small
Eio-native HTTP server before higher-level routing DSLs exist.

## Goals

- Users can provide a plain OCaml handler function for HTTP requests.
- Users can wrap handlers with middleware for cross-cutting behavior.
- The first API remains compatible with a future routing DSL.
- Shared HTTP value types remain compatible with a future HTTP client.
- Handler tests can run without opening a network socket.

## Non-Goals

- Route declaration DSLs such as `get "/path" handler`.
- Regex path matching.
- HTTP client APIs.
- TLS support.
- HTTP/2 or HTTP/3 support.
- Web framework features such as controllers, templates, sessions, or dependency
  injection.

## Requirements

- The public handler contract is a function that receives a `Request.t` and
  returns a `Response.t`.
- Middleware is a first-class transformation from handler to handler.
- Middleware list order is normative: applying `[a; b]` to handler `h` produces
  `a (b h)`, so `a` observes the request first and response last.
- Server startup accepts an Eio switch, Eio network capability, socket address,
  and handler-backed server value.
- The caller owns the Eio switch passed to the server. Camelio attaches listener
  resources and connection fibers to that switch, but does not close it.
- Applications may use Eio capabilities captured by closure inside handlers.
- The API must not expose `Lwt.t`, `Async.Deferred.t`, `cohttp` types, or
  callback-based scheduling.
- A future Router DSL must be able to compile to the same handler contract.
- A future HTTP client must be able to reuse shared HTTP types for methods,
  headers, status, request bodies, and response bodies.
- Future HTTP/2 and HTTP/3 implementations must be able to reuse the handler and
  middleware contract when their protocol semantics can be represented as shared
  request and response values.
- First-milestone request bodies are buffered and replayable. Streaming bodies
  are deferred behind abstract body types.
- Uncaught non-cancellation handler exceptions before response writing produce a
  `500 Internal Server Error` response with `content-type:
  text/plain; charset=utf-8`, `connection: close`, and body
  `Internal Server Error\n`; the server closes the connection afterward.
- Exceptions matching `Eio.Cancel.Cancelled _` remain cancellation and are not
  converted into HTTP 500.

## Public Contracts

Initial contracts:

```ocaml
module Handler : sig
  type t = Request.t -> Response.t
end

module Middleware : sig
  type t = Handler.t -> Handler.t
end
```

Public `.mli` files must document these contracts with block comments.

The first milestone also exposes abstract `Request.t`, `Response.t`, and
`Body.t` types with constructors/accessors for method, target, path, headers,
status, and buffered body values.

Header lookup is case-insensitive. `Request.path` is derived from valid
origin-form request targets by removing the query string. Unsupported
request-target forms are rejected before handler invocation.
Header insertion order is preserved. `Headers.add` appends, `Headers.set`
removes case-insensitive matches and appends the replacement, `Headers.get`
returns the first matching value, and `Response.with_header` uses `Headers.set`.
HTTP method tokens are case-sensitive. Invalid method tokens, invalid status
codes outside 100 through 599, and invalid `Request.make` targets raise
`Invalid_argument`.

The first milestone supports plain HTTP server connections only. It must not
promise HTTPS or TLS behavior, but protocol code should be designed around Eio
flows so future TLS transport support can be introduced without changing handler
contracts.

The first milestone supports HTTP/1.1 only. It must not promise HTTP/2 or HTTP/3
behavior, but the handler and middleware APIs should avoid depending on HTTP/1.1
connection details so later protocol versions can target the same shared
request/response contract where appropriate.

## Examples

Minimal handler:

```ocaml
let hello _request =
  Response.text "hello"
```

Middleware shape:

```ocaml
let add_server_header next request =
  request
  |> next
  |> Response.with_header "server" "camelio"
```

Future router compatibility:

```ocaml
let app =
  Router.empty
  |> Router.get "/" hello
  |> Router.to_handler
```

`Router` is illustrative only and is not part of the first server milestone.

Future client compatibility:

```ocaml
(* Illustrative only; Client is not part of the first server milestone. *)
let upstream_request =
  Request.make
    ~meth:Method.GET
    ~target:"/"
    ~headers:Headers.empty
    ~body:Body.empty
```

## Open Questions

- What default maximum request body size should the server enforce?
- Which request-target constructors should be added when HTTP Client support is
  designed?
- Which TLS library or abstraction should be used by future client/server
  transport support?
- What body, trailer, multiplexing, and lifecycle abstractions are needed before
  HTTP/2 or HTTP/3 can be designed?
- Should middleware order ever support alternate composition helpers beyond
  explicit list order?
