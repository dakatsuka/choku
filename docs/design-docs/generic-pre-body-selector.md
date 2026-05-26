# Generic Pre-Body Selector

## Status

Accepted

## Context

Choku already has the internal shape needed for pre-body request body-mode
selection. `Server.t` stores a function from parsed HTTP/1.1 request head to
`Request_body_mode.t`; `Server.create` installs a constant function, and
`Server.create_router` installs a router-based matcher.

That internal function currently receives `Http1.request_head`, which is a
protocol module type and not a stable public API. A generic public selector
needs a shared request-head view that is independent of HTTP/1.1 parser
internals.

## Goals

- Expose a stable request-head value for pre-body decisions.
- Let non-router applications select request body mode before body delivery.
- Reuse the existing server read pipeline.
- Keep router route-level body mode unchanged.
- Avoid overloading `Server.create` with conflicting optional arguments.

## Non-Goals

- Implementing the selector in this design pass.
- Request body inspection before selecting body mode.
- Exposing HTTP parser internals.
- Per-route or per-selector body limits.
- Middleware-driven body-mode selection.

## Proposed Design

Add a public `Request_head` module:

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
```

`Request_head.t` mirrors the request metadata available before body delivery:
method, raw origin-form target, query-stripped path, raw query string, and
headers. It deliberately does not expose body framing, decoded query parameters,
host parsing, connection state, or protocol version.

`Request_head.make` should validate the same origin-form target subset as
`Request.make`. It should not enforce the HTTP/1.1 server-specific `Host`
requirement because tests and future protocol adapters may construct heads that
are already known to be valid in their context. The server-created value comes
after HTTP/1.1 request-head validation, including the existing Host checks.

## Server API

Add a separate constructor:

```ocaml
val Server.create_with_request_body_selector :
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

This is intentionally separate from `Server.create` because `Server.create`
already has `?request_body_mode:request_body_mode`. Adding another optional
selector argument would require precedence rules when both are present. A
separate constructor keeps existing code clear and source-compatible.

Internally, the server should represent selector outcomes explicitly:

```ocaml
type request_body_mode_decision =
  | Body_mode of Request_body_mode.t
  | Selector_failed
```

or equivalently with a result type that preserves cancellation. The important
contract is that non-cancellation selector exceptions are caught before body
reading so the connection path can write the default 500 response and close.

The constructor should adapt from `Http1.request_head` to `Request_head.t`:

```ocaml
let request_body_mode http1_head =
  let head =
    Request_head.make
      ~meth:http1_head.meth
      ~target:http1_head.target
      ~headers:http1_head.headers
  in
  try Body_mode (selector head) with
  | Eio.Cancel.Cancelled _ as exn -> raise exn
  | _ -> Selector_failed
```

The adaptation should not fail for a server-parsed head. If it does, treat it as
an internal invariant violation and return the same 500/close behavior used for
selector exceptions.

## Selector Semantics

The selector is invoked:

- after request-head parsing and validation;
- before fixed-length or chunked body bytes are consumed;
- before middleware or handler invocation;
- once per request on a persistent connection.

The selector may inspect:

- `Request_head.meth`;
- `Request_head.target`;
- `Request_head.path`;
- `Request_head.query_string`;
- `Request_head.headers`.

The selector must not depend on request body bytes. It should normally be a
small pure function. It may raise, but non-cancellation exceptions produce the
default 500 response and close the connection. `Eio.Cancel.Cancelled _`
continues to mean cancellation.

Selector failures happen before a `Request.t` exists. The server should still
use the parsed request method to apply normal HEAD response-body suppression:
failing `HEAD` selectors write only the 500 response head, not
`Internal Server Error\n` bytes.

Returned modes reuse existing behavior:

- `Buffered` reads the whole request body before handler invocation;
- `Streaming` validates declared size before handler invocation and exposes a
  single-consumption body source.

Existing body framing errors, body-size errors, and request-head errors keep
their current status codes and close behavior.

## Router Interaction

`Server.create_router` remains the preferred API when using `Router.t`. The
router has richer metadata and can guarantee that body-mode selection matches
the final route handler, including route insertion order, automatic `HEAD`
fallback, and 405 behavior.

The generic selector constructor is for users who provide their own dispatcher
inside a normal handler. Choku does not attempt to prove that the selector and
the handler dispatch logic agree.

## `Server.handle`

`Server.handle` receives an already-built `Request.t`; the body has already been
chosen and constructed. It therefore does not run the selector. Unit tests for
selector logic should call the selector directly with `Request_head.make`, while
integration behavior should be tested through `Server.run`.

## Contracts

- `Request_head.t` is a stable public value type.
- `Request_head` is exported from the top-level `Choku` module.
- `Request_head.path` derives from `target` using the same query-stripping rule
  as `Request.path`.
- `Server.create_with_request_body_selector` applies middleware exactly once
  around the handler, like `Server.create`.
- Selectors run before body delivery and before middleware.
- Selector exceptions map to 500/close, except cancellation.
- Selector exceptions for `HEAD` requests suppress the 500 response body.
- Selectors are not invoked when request-head validation or request body framing
  fails before selection.
- Router route-level body mode remains unchanged.

## Alternatives Considered

- Add `?request_body_mode_selector` to `Server.create`: rejected because it
  conflicts conceptually with the existing `?request_body_mode` argument and
  requires precedence rules.
- Expose `Http1.request_head`: rejected because selector API should not expose
  protocol parser internals.
- Require users to use `Router.t`: rejected because custom dispatchers may still
  need pre-body selection.
- Put selectors in middleware: rejected because middleware runs after body
  delivery.

## Third-Party Review

Context-free review found that selector exceptions need an explicit internal
result path because the current server calls body-mode selection before the
handler exception boundary. The design now requires catching non-cancellation
selector exceptions before body reads, returning 500/close, and preserving
cancellation. The same review required documenting HEAD body suppression for
selector failures and top-level `Choku.Request_head` export.

## Validation

Implementation should add tests for:

- `Request_head.make` target validation and path derivation;
- selector chooses buffered for one path and streaming for another;
- selector can inspect method and headers;
- selector runs once per request, including persistent connections;
- selector runs before body bytes are consumed;
- selector is not invoked for malformed request heads or invalid body framing
  discovered before selection;
- selector non-cancellation exception produces 500 and close;
- selector non-cancellation exception on `HEAD` writes no response body;
- selector non-cancellation exception closes a keep-alive connection after the
  500 response;
- selector cancellation propagates;
- middleware cannot affect selector decisions and still wraps the final handler
  exactly once;
- `Server.handle` does not run selectors;
- `Choku.Request_head` is publicly available from an external test;
- existing `Server.create` and `Server.create_router` behavior remains
  unchanged.

## Open Questions

None.
