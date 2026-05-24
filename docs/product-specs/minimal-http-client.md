# Minimal HTTP Client

## Status

Accepted

## Problem

Choku has a practical minimal HTTP/1.1 application-server baseline. Users also
need an Eio-native outbound HTTP client for service-to-service requests, tests,
and simple integrations.

The first client milestone should be small, but it should include middleware
from the beginning. Middleware lets users implement retries, authentication,
logging, metrics, JSON codecs, and other policies outside Choku core while
keeping the built-in client focused on basic HTTP transport.

## Goals

- Provide a plain HTTP/1.1 client that works with Eio direct-style IO.
- Keep client request and response types separate from server `Request.t` and
  `Response.t`.
- Reuse shared protocol values where their contracts fit: `Method.t`,
  `Headers.t`, `Status.t`, and buffered `Body.t`.
- Support one request and one fully buffered response per connection.
- Add a client middleware stack in the first milestone.
- Keep user-visible errors explicit and testable.
- Leave room for later TLS, pooling, redirects, cookies, compression, proxy
  support, streaming responses, and streaming request uploads.

## Non-Goals

- HTTPS/TLS.
- HTTP/2 or HTTP/3.
- Connection pooling or persistent connection reuse.
- Redirect following.
- Cookies.
- Request retries.
- Compression or decompression.
- Proxy support.
- CONNECT, WebSocket, or protocol upgrades.
- Streaming response bodies in the first client milestone.
- Streaming request uploads in the first client milestone.
- A high-level JSON, form, OAuth, tracing, or metrics package.

These features may be implemented by users as middleware when possible, or by
later Choku milestones when they need transport-level support.

## Requirements

- The first client supports absolute `http://` URLs only.
- `https://` URLs return a client error instead of silently downgrading to
  plain HTTP.
- The first client rejects `CONNECT` requests because tunneling is out of
  scope.
- `Client.Request.make` validates URLs and returns an explicit client error for
  fragments, userinfo, unsupported schemes, missing hosts, control bytes,
  spaces, or malformed ports.
- Bracketed IPv6 literals are not required in the first milestone and may be
  rejected with an explicit client error.
- The request target sent on the wire is origin-form: path plus optional query.
- An empty URL path is normalized to `/`.
- The client sets `Host` from the URL authority. User-provided `Host` headers
  are ignored or replaced by the derived authority.
- The client owns HTTP/1.1 framing headers during serialization:
  `Content-Length`, `Transfer-Encoding`, `Connection`, and `Host`.
- The first client sends `Connection: close` and closes the connection after
  reading the response.
- Request bodies are buffered. `Client.Request.make` accepts `Body.t`, but the
  first milestone only supports replayable buffered bodies.
- Responses are fully buffered before `Client.request` returns.
- Response head and response body sizes are bounded by configurable limits.
- The default maximum response head size is `16_384` bytes.
- The default maximum response body size is `1_048_576` bytes.
- Negative response limits are rejected by `Client.create`.
- A zero response body limit allows only empty response bodies. A zero response
  head limit is invalid.
- `Content-Length` response bodies are read exactly to the declared length.
- `Transfer-Encoding: chunked` response bodies are decoded.
- Unsupported transfer codings return an error.
- Responses to `HEAD`, informational `1xx`, `204 No Content`, and
  `304 Not Modified` are treated as bodyless.
- Informational `1xx` response heads before a final response are tolerated and
  skipped, except `101 Switching Protocols`, which returns an unsupported
  upgrade error.
- Response body handling order is explicit:
  1. parse the response head and status;
  2. skip non-`101` informational responses before applying body framing;
  3. return an empty body for final responses to `HEAD`, `204`, and `304`,
     ignoring body framing headers for body reading;
  4. apply strict `Transfer-Encoding` and `Content-Length` validation only to
     responses that are permitted to carry a body.
- Responses containing both `Transfer-Encoding` and `Content-Length` are
  rejected.
- The first client accepts only a single valid decimal `Content-Length` field.
  Empty, negative, signed, comma-separated, duplicated, or conflicting content
  lengths are rejected. A response with no `Content-Length` and no transfer
  coding is allowed and is read until connection close.
- The first client accepts only exactly `Transfer-Encoding: chunked`.
  Transfer-coding lists such as `gzip, chunked` are rejected.
- Malformed response heads, invalid status lines, invalid content lengths, and
  malformed chunked bodies return errors.
- Each transport attempt closes its TCP flow on success, client error,
  non-cancellation exception mapping, and cancellation. Cancellation is still
  re-raised instead of converted into a client error.
- Cancellation remains Eio cancellation and is not converted into client
  errors.
- Middleware list order is normative: applying `[a; b]` to the transport call
  produces `a (b transport)`, so `a` observes the request first and response or
  error last.
- Middleware can inspect or replace `Client.Request.t` before calling the next
  layer.
- Middleware can inspect or replace successful `Client.Response.t` values.
- Middleware can observe or map client errors, but must preserve Eio
  cancellation.

## Public Contracts

Expected API shape:

```ocaml
module Client : sig
  type t

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

    val pp : Format.formatter -> t -> unit
  end

  module Request : sig
    type t

    val make :
      ?headers:Headers.t ->
      ?body:Body.t ->
      meth:Method.t ->
      url:string ->
      unit ->
      (t, Error.t) result

    val meth : t -> Method.t
    val url : t -> string
    val authority : t -> string
    val host : t -> string
    val port : t -> int
    val target : t -> string
    val headers : t -> Headers.t
    val body : t -> Body.t
    val with_headers : Headers.t -> t -> t
    val with_header : string -> string -> t -> t
    val with_body : Body.t -> t -> t
  end

  module Response : sig
    type t

    val make : ?headers:Headers.t -> ?body:Body.t -> Status.t -> t
    val status : t -> Status.t
    val headers : t -> Headers.t
    val body : t -> Body.t
  end

  module Handler : sig
    type t = Request.t -> (Response.t, Error.t) result
  end

  module Middleware : sig
    type t = Handler.t -> Handler.t

    val identity : t
    val compose : t -> t -> t
    val apply : t list -> Handler.t -> Handler.t
  end

  val create :
    ?max_response_head_size:int ->
    ?max_response_body_size:int ->
    ?middlewares:Middleware.t list ->
    net:[> Eio.Net.ty ] Eio.Resource.t ->
    unit ->
    t

  val request :
    sw:Eio.Switch.t ->
    t ->
    Request.t ->
    (Response.t, Error.t) result
end
```

The exact names may change during implementation, but the first milestone must
preserve these product-level contracts:

- client request and response types are separate from server request and
  response types;
- middleware wraps the outbound call as a first-class value;
- middleware can inspect normalized authority, host, port, and origin-form
  target through request accessors;
- the core transport is plain HTTP/1.1, one request per connection, fully
  buffered response;
- non-core policy features stay outside the transport.

## Examples

Simple request:

```ocaml
let fetch sw net =
  let client = Choku.Client.create ~net () in
  match
    Choku.Client.Request.make
      ~meth:Choku.Method.GET
      ~url:"http://example.test/status"
      ()
  with
  | Error error -> Error error
  | Ok request -> Choku.Client.request ~sw client request
```

Middleware that adds a bearer token:

```ocaml
let bearer token next request =
  request
  |> Choku.Client.Request.with_header "authorization" ("Bearer " ^ token)
  |> next
```

Middleware order:

```ocaml
let client =
  Choku.Client.create
    ~net
    ~middlewares:[ log_request; bearer token; map_errors ]
    ()
```

`log_request` sees the request first. `map_errors` is closest to the transport.
Middleware should use `Client.Request.authority` and `Client.Request.target`
when it needs wire-significant request values; user-provided framing headers may
be replaced by the transport.

## Open Questions

- Should the first implementation expose convenience functions such as
  `Client.get`, or keep only `Client.request` until the core contract settles?
- Should client middleware receive a small request context in addition to
  `Client.Request.t`, or is the request value enough for the first milestone?
