# Minimal HTTP Client

## Status

Accepted

## Context

Choku's server API is now stable enough for application-server use behind a
reverse proxy. The next subsystem is an outbound HTTP Client.

The server request and response types are intentionally application-server
values. Server `Request.t` validates origin-form request targets and represents
an inbound request after parsing. Server `Response.t` represents an outbound
server response and carries server-side serialization policy such as HEAD and
body-forbidden status behavior.

The client needs different contracts: absolute URL input, authority handling,
outbound request serialization, inbound response parsing, and client-side
middleware. It should therefore introduce distinct client request and response
types instead of reusing server `Request.t` and `Response.t`.

## Goals

- Design the first HTTP Client milestone before implementation.
- Keep the client API Eio-native and direct-style.
- Introduce separate `Client.Request.t` and `Client.Response.t` types.
- Include client middleware from the first milestone.
- Keep the core transport minimal: plain HTTP/1.1, one request per connection,
  fully buffered response.
- Reuse shared protocol primitives where appropriate.
- Keep non-core client policies extensible without making them core features.

## Non-Goals

- Implementing the client in this design pass.
- TLS or certificate verification.
- Connection pooling.
- Persistent connection reuse.
- Cookies, retries, compression, proxy support, CONNECT, WebSocket, or protocol
  upgrades.
- Streaming request uploads or streaming response bodies.
- A high-level resource context, tracing system, or plugin framework.

## Proposed Design

Add a new top-level `Choku.Client` module. The client owns outbound request and
inbound response abstractions:

```ocaml
module Client : sig
  type t

  module Request : sig
    type t
  end

  module Response : sig
    type t
  end
end
```

`Client.Request.t` and `Client.Response.t` are not aliases for server
`Request.t` and `Response.t`. This avoids weakening server target validation
and avoids importing server response serialization rules into client response
parsing.

The first milestone should still reuse:

- `Method.t` for request methods;
- `Headers.t` for request and response headers;
- `Status.t` for response status;
- `Body.t` for buffered request and response bodies.

`Body.t` remains a shared byte container, but the first client only accepts
buffered bodies for outbound requests and only returns buffered response bodies.
Future streaming client work can add client-specific constructors or response
consumption APIs without changing server `Request.t` or `Response.t`.

## URL And Request Target Model

`Client.Request.make ~meth ~url ()` accepts an absolute URL string for the first
milestone and returns `(t, Error.t) result`. The URL parser should be
intentionally small and support only:

```text
http://host[:port][/path][?query]
```

The parser returns `Error.t` for unsupported schemes, missing hosts, userinfo,
fragments, spaces, control bytes, invalid ports, and malformed authority values.
Bracketed IPv6 literals are not required by the first milestone and may return
a client error.

`Client.Request.make` should reject `CONNECT` because CONNECT requires
authority-form request targets and successful responses switch to tunnel
semantics. Both are out of scope for the first milestone.

The parsed client request stores both the original URL and normalized outbound
wire components:

- scheme: initially only `http`;
- host;
- port, defaulting to 80;
- authority for the `Host` header, preserving an explicit non-default port;
- origin-form request target, defaulting to `/`.

This representation belongs inside `Client.Request` or a private
`client_target` helper. It should not relax the server's existing origin-form
`Request.t` validation.

Expose read-only accessors for middleware that signs, logs, or routes based on
the normalized wire-significant values:

```ocaml
val authority : Request.t -> string
val host : Request.t -> string
val port : Request.t -> int
val target : Request.t -> string
```

## Middleware

The first client should include middleware as a core extension point:

```ocaml
module Handler : sig
  type t = Request.t -> (Response.t, Error.t) result
end

module Middleware : sig
  type t = Handler.t -> Handler.t

  val identity : t
  val compose : t -> t -> t
  val apply : t list -> Handler.t -> Handler.t
  val follow_redirects : ?max_redirects:int -> unit -> t
end
```

The terminal handler is the transport call. `Client.create ?middlewares` builds
and stores a composed middleware transformer. `Client.request ~sw` applies that
transformer to the per-call transport handler, so the transport can close over
the caller-owned switch.

Middleware order should match server middleware order:

```ocaml
Middleware.apply [a; b; c] transport = a (b (c transport))
```

The first middleware in the list observes the request first and the response or
error last. This is enough for user-owned policies such as:

- adding authentication headers;
- request and response logging;
- timing and metrics;
- error mapping;
- simple retry policies for replayable requests;
- content-type helpers;
- test doubles around the transport call.

Middleware remains request/response oriented. Socket creation, DNS resolution,
timeouts, protocol parsing, and body-size limits stay in the transport layer or
client configuration.

Redirect following is an opt-in built-in middleware. It wraps the next handler
and issues a new `Client.Request.t` when the response status and method are
eligible:

- `301`, `302`, `307`, and `308` are followed only for `GET` and `HEAD`.
- `303` is followed for any method; the redirected request uses `GET`, except
  `HEAD` remains `HEAD`.
- Missing `Location` returns `Client.Error.Redirect_missing_location`.
- Exceeding `max_redirects` returns `Client.Error.Too_many_redirects`.
- `max_redirects` defaults to `5` and must be non-negative.
- Redirect locations support absolute `http://` and `https://` URLs,
  scheme-relative URLs, path-absolute references, and query-only references.
- Fragment components are stripped before constructing the next request.
- Request headers are preserved, except cross-origin redirects strip
  `Authorization`, `Cookie`, and `Proxy-Authorization`.

The first redirect implementation does not attempt full RFC 3986 relative URL
resolution. Moving URL parsing and resolution to a dedicated RFC 3986 library is
a separate design topic.

Because `Client.Request.t` is immutable, the request module should include
small replacement helpers:

```ocaml
val with_headers : Headers.t -> Request.t -> Request.t
val with_header : string -> string -> Request.t -> Request.t
val with_body : Body.t -> Request.t -> Request.t
```

Because middleware and tests may need to synthesize responses without a socket,
`Client.Response` should include:

```ocaml
val make : ?headers:Headers.t -> ?body:Body.t -> Status.t -> Response.t
```

Cancellation must not be converted to `Error.t` by core middleware helpers.
User middleware should follow the same rule.

## Client Construction And Call Flow

The client stores Eio network capability, limits, and the composed middleware
stack:

```ocaml
val create :
  ?max_response_head_size:int ->
  ?max_response_body_size:int ->
  ?mono_clock:_ Eio.Time.Mono.t ->
  ?connect_timeout:float option ->
  ?tls_handshake_timeout:float option ->
  ?request_write_timeout:float option ->
  ?response_head_timeout:float option ->
  ?response_body_timeout:float option ->
  ?middlewares:Middleware.t list ->
  net:[> Eio.Net.ty ] Eio.Resource.t ->
  unit ->
  t

val request :
  sw:Eio.Switch.t ->
  t ->
  Request.t ->
  (Response.t, Error.t) result
```

The caller owns the switch passed to `Client.request`. The client opens one TCP
connection under that switch, writes one HTTP/1.1 request, reads one response
head and body, closes the connection, and returns a buffered
`Client.Response.t`.

The transport resolves the URL host using the Eio network capability. DNS,
socket connection, and write/read failures become client errors unless they are
Eio cancellation.

Each transport attempt must close its TCP flow on success, on client error, on
non-cancellation exception mapping, and on cancellation. Cancellation is then
re-raised. The implementation should use an explicit close/finally pattern or a
per-attempt resource scope that does not close the caller-owned switch.

Default limits:

- `max_response_head_size = 16_384` bytes;
- `max_response_body_size = 1_048_576` bytes.

`Client.create` rejects negative limits and rejects
`max_response_head_size = 0`. `max_response_body_size = 0` is valid and allows
only empty response bodies.

Timeout settings are optional and disabled by default. When any timeout is
configured, `Client.create` requires a monotonic clock:

```ocaml
Choku.Client.create
  ~net
  ~mono_clock:(Eio.Stdenv.mono_clock env)
  ~connect_timeout:(Some 5.0)
  ~tls_handshake_timeout:(Some 5.0)
  ~request_write_timeout:(Some 5.0)
  ~response_head_timeout:(Some 10.0)
  ~response_body_timeout:(Some 30.0)
  ()
```

Timeout values must be finite and positive. The implementation converts each
configured float to `Eio.Time.Timeout.seconds mono_clock seconds` at the
operation boundary. Expiration maps to `Client.Error.Timeout phase`; Eio
cancellation from outside the timeout is still re-raised.

Timeout phases:

- `Connect`: DNS resolution and TCP connect attempts.
- `Tls_handshake`: TLS client handshake after TCP connect.
- `Request_write`: writing the serialized request bytes.
- `Response_head`: reading and parsing the final response head, including
  skipped informational heads.
- `Response_body`: reading the response body after the final head.

The transport sends `Connection: close` in the first milestone. This avoids
pooling and connection-lifetime complexity while still producing standards-
compatible HTTP/1.1 requests.

## HTTP/1.1 Serialization

The client request writer should share low-level formatting helpers with the
server only where those helpers are protocol-generic. It should not reuse server
request parsing or server response writing policy.

For outbound requests:

- write request line: `<METHOD> <origin-form-target> HTTP/1.1`;
- reject `CONNECT` before serialization;
- set `Host` from the parsed URL authority;
- set `Connection: close`;
- set `Content-Length` for buffered request bodies;
- remove user-provided `Host`, `Connection`, `Content-Length`, and
  `Transfer-Encoding` before adding client-owned framing headers;
- do not emit chunked request bodies in the first milestone.

The initial client should reject non-buffered request bodies with
`Request_body_not_buffered` before opening the connection.

## HTTP/1.1 Response Parsing

Add response-head parsing to `Http1` or to a client-focused internal module.
The parser should produce an internal response head:

```ocaml
type response_head = {
  version : string;
  status : Status.t;
  reason : string;
  headers : Headers.t;
}
```

The first milestone supports `HTTP/1.1` responses. Supporting `HTTP/1.0`
responses can be deferred unless implementation finds it simpler to accept them
without weakening error handling.

Body reading rules:

- parse each response head and status before applying body framing;
- informational `1xx` response heads before the final response are skipped
  before transfer-length validation;
- `101 Switching Protocols` is rejected as `Unsupported_upgrade`;
- final responses to `HEAD`, `204 No Content`, and `304 Not Modified` return
  empty bodies and ignore body framing headers for body reading;
- `Content-Length`: read exactly the declared number of bytes.
- `Transfer-Encoding: chunked`: decode chunks using the existing chunked
  decoder behavior where practical.
- no length and no transfer coding: read until connection close, still bounded
  by `max_response_body_size`.
- unsupported transfer codings: return `Unsupported_transfer_encoding`.
- malformed response head or body framing: return an explicit client error.

For responses that are permitted to carry a body, transfer length rules should
be strict:

- reject responses that contain both `Transfer-Encoding` and `Content-Length`;
- accept only exactly `Transfer-Encoding: chunked`;
- reject transfer-coding lists such as `gzip, chunked`;
- accept only one valid decimal `Content-Length` field;
- reject empty, negative, signed, comma-separated, duplicated, or conflicting
  content lengths;
- allow responses with no `Content-Length` and no transfer coding by reading
  until connection close.

The initial response is fully buffered before returning. Later streaming
response support can introduce a scoped API that keeps the connection lifetime
explicit.

## Error Model

Use a client-specific error type:

```ocaml
module Error : sig
  type t =
    | Invalid_url of string
    | Unsupported_scheme of string
    | Connection_failed of exn
    | Malformed_response of string
    | Response_head_too_large
    | Invalid_content_length
    | Unsupported_transfer_encoding
    | Malformed_chunked_body
    | Response_body_too_large
    | Request_body_not_buffered
    | Unsupported_method of Method.t
    | Unsupported_upgrade
end
```

The exact constructors may be adjusted during implementation, but errors should
distinguish URL validation, connection establishment, response-head parsing,
body framing, and configured limits.

Exceptions matching Eio cancellation remain cancellation.

## Module Boundaries

Suggested implementation modules:

- `client.ml` / `client.mli`: public `Choku.Client` API, configuration,
  middleware composition, and top-level request function.
- `client_request.ml`: client request value and URL normalization.
- `client_response.ml`: client response value.
- `client_middleware.ml`: client middleware helpers if the nested module grows.
- `http1_client.ml`: HTTP/1.1 client request writer and response reader, kept
  internal until its contracts are useful elsewhere.

Depending on final code size, the first implementation can keep nested client
modules in `client.ml` and split later. Public `.mli` documentation must still
make the contracts clear.

## Contracts

- Server `Request.t` and `Response.t` remain server/application values.
- Client `Request.t` and `Response.t` are separate abstract types.
- Shared `Method.t`, `Headers.t`, `Status.t`, and buffered `Body.t` are reused.
- Client middleware is a first-class handler transformation.
- Middleware order is `a (b transport)` for `[a; b]`.
- The initial transport opens one plain TCP connection per request.
- The initial transport sends `Connection: close`.
- The initial transport returns a fully buffered response.
- Core client does not implement redirects, retries, cookies, compression,
  proxy behavior, TLS, or pooling.

## Alternatives Considered

- Reuse server `Request.t` for client requests: rejected because the server
  type validates origin-form targets and lacks URL authority, scheme, and
  connection-target information.
- Reuse server `Response.t` for client responses: rejected because server
  responses encode outbound server serialization policy, while client responses
  are parsed inbound values.
- Defer middleware: rejected because middleware is the smallest useful
  extension point for keeping retries, auth, logging, and codecs out of core.
- Add connection pooling immediately: rejected because pooling makes response
  lifetimes, cancellation, error recovery, and middleware semantics more complex
  than the first milestone needs.
- Add TLS immediately: rejected because TLS selection and verification policy
  need a separate transport design.

## Third-Party Review

Initial context-free review found six issues:

- response parsing missed no-body and informational response rules;
- `CONNECT` could be serialized incorrectly despite being out of scope;
- per-attempt connection cleanup was underspecified;
- response transfer-length precedence was ambiguous;
- middleware lacked accessors for normalized authority and request target;
- response limit defaults and validation were unspecified.

The design was revised to skip informational responses, reject `101`, treat
`HEAD`/`204`/`304` as bodyless, reject `CONNECT`, require explicit flow cleanup
for each attempt, define strict response framing rules, add request authority
and target accessors, and specify response limit defaults and validation.

Re-review found one remaining contradiction between bodyless response handling
and strict transfer-length rejection. The design now defines processing order:
skip informational responses first, return empty bodies for final `HEAD`/`204`/
`304` responses, and apply strict transfer-length validation only to responses
that may carry a body. Final re-review passed.

## Validation

Design validation:

- context-free review before implementation;
- documentation build checks.

Implementation validation for the later milestone:

- unit tests for URL parsing and client request construction;
- unit tests for client middleware order and error propagation;
- unit tests for HTTP/1.1 response-head parsing;
- unit tests for response body framing and limits;
- integration tests against an Eio local TCP server;
- regression tests for cancellation preservation.

## Open Questions

- Should convenience helpers such as `Client.get` be included in the first
  implementation, or should users construct `Client.Request.t` explicitly?
- Should client middleware receive a small immutable context for timing,
  request ID, or attempt count, or should that remain user-owned state captured
  by closure?
