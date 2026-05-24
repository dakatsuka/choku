# HTTP/1.1 Persistent Connections

## Status

Accepted

## Context

Choku currently accepts a TCP connection, reads one HTTP/1.1 request, writes one
response with `Connection: close`, and shuts the connection down. That matched
the initial minimal milestone, but HTTP/1.1 persistent connections are the
default behavior expected by reverse proxies and load balancers.

The next milestone should make Choku usable as a simple backend application
server behind nginx, ALB, ELB, or similar infrastructure without adding edge
server features.

## Goals

- Support sequential reuse of HTTP/1.1 connections.
- Preserve the direct `Handler.t = Request.t -> Response.t` contract.
- Keep Eio resource ownership simple: one accepted connection remains one Eio
  fiber under the caller-owned switch.
- Reuse existing request parsing, body delivery, and response serialization
  paths where possible.
- Close conservatively when request body consumption or error handling makes
  reuse unsafe.

## Non-Goals

- Parallel processing of pipelined requests.
- A pipelining scheduler or response reorder buffer.
- HTTP/1.0 keep-alive.
- Chunked or streaming responses.
- Connection upgrade, CONNECT tunneling, WebSocket, TLS, HTTP/2, or HTTP/3.
- A public per-connection request limit.
- A public keep-alive idle timeout separate from `request_head_timeout`.

## Proposed Design

Add `keep_alive` to `Server.t` and constructors:

```ocaml
val create :
  ?keep_alive:bool ->
  ...

val create_router :
  ?keep_alive:bool ->
  ...
```

`keep_alive` defaults to `true`. Users can set `~keep_alive:false` to keep the
previous close-after-response behavior.

Replace the single-request `handle_connection` body with a connection loop:

```ocaml
let rec connection_loop state flow =
  match read_request ?mono_clock server flow with
  | End_of_connection ->
      ()
  | Error error ->
      write_response ~connection:Close flow (Http1.response_for_error error)
  | Ok request ->
      let response, handler_outcome = handle_request request in
      let decision = decide_connection server request response handler_outcome in
      write_response ~connection:decision flow response;
      match decision with
      | Close -> ()
      | Keep_open -> connection_loop state flow
```

The loop remains sequential. If a client pipelines bytes, Choku may already have
some bytes in the read buffer while handling the first request, but it still
does not invoke the next handler until the previous response is written.

## Buffered Prefix Handling

Current request-head reading can read body-prefix bytes beyond `\r\n\r\n`.
Persistent connections also need to preserve bytes beyond the current body,
because one socket read may contain the next pipelined request head.

Introduce a small connection-local reader:

```ocaml
type connection_reader = {
  flow : Eio.Flow.source_ty Eio.Resource.t;
  buffer : Buffer.t;
}
```

Reads first consume `buffer`, then the live flow. Request-head scanning appends
only the bytes after the current header terminator back into `buffer`. Fixed
body and chunked body readers consume only their framed body bytes and leave any
following bytes in `buffer` for the next loop iteration.

If EOF occurs before any bytes of a request head are read, the reader returns an
internal `End_of_connection` result and the server closes quietly. If EOF occurs
after a partial request head has been buffered, the existing malformed-header
error path is used.

This is internal only. No public request-head or connection type is exposed.

## Connection Header Tokens

`Connection` values are parsed as comma-separated tokens across all repeated
header fields. Token matching is case-insensitive after optional whitespace is
trimmed. Any `close` token requests connection close. Other tokens, including
`keep-alive`, do not force reuse; reuse still depends on Choku's internal
connection decision.

For responses, Choku inspects the handler response for a `close` token before
serialization, then overwrites the final wire `Connection` header with either
`keep-alive` or `close` based on the connection decision. This preserves the
handler's ability to request close while keeping wire output consistent with
what the server will actually do next.

## Connection Decision

Use an internal decision type:

```ocaml
type connection_decision = Keep_open | Close
```

The decision is `Close` when:

- `server.keep_alive = false`;
- the request has `Connection: close`;
- the response has `Connection: close`;
- request body mode for this request is `Streaming`;
- request parsing, body framing, or request body-size validation failed;
- uncaught non-cancellation handler exception produced the default 500;
- a streaming body protocol exception escaped the handler and was mapped to an
  error response.

Otherwise the decision is `Keep_open`.

When `Keep_open`, response serialization writes `Connection: keep-alive`. When
`Close`, response serialization writes `Connection: close`.

## Timeouts

`request_head_timeout` continues to wrap each request-head read. On persistent
connections this also bounds the idle time spent waiting for the next request.
If it expires between requests, Choku writes the existing 408 response and
closes when possible.

This milestone does not add a separate keep-alive idle timeout API. A later
milestone may split these controls if users need different first-request and
idle-request behavior.

Because `request_head_timeout` defaults to `None`, a direct deployment without a
fronting proxy can keep connection fibers idle indefinitely. This milestone keeps
that source-compatible default, but deployment documentation should recommend a
finite timeout for directly exposed servers.

## Streaming Request Bodies

Streaming request bodies are handler-scoped and single-consumption. Choku does
not currently track whether a streaming handler fully consumed the source, and
the close-oriented server has not needed to drain unread bytes. To keep the
first persistent-connection milestone safe, every request delivered in
`Streaming` mode closes after its response.

Buffered routes on a router-backed server may still keep the connection open.
Route-level streaming routes close only for requests that matched a streaming
route.

## Contracts

- HTTP/1.1 keep-alive is enabled by default.
- `~keep_alive:false` preserves one-response-per-connection behavior.
- `Connection: close` is respected on both request and response.
- `Connection` close detection uses case-insensitive token semantics across
  comma lists and repeated fields.
- `Connection: keep-alive` is written only when Choku will read another request
  on the connection.
- Error responses close the connection.
- Streaming request-body responses close the connection.
- Request processing on a connection is sequential and ordered.
- EOF before any bytes of the next request closes quietly.

## Alternatives Considered

- Keep close-after-response as the default: rejected because this milestone is
  specifically to make Choku a practical HTTP/1.1 backend application server.
- Add `keep_alive_timeout` now: deferred to keep the API small. Existing
  `request_head_timeout` already provides a conservative idle bound when users
  opt in.
- Drain streaming request bodies to preserve reuse: rejected for this milestone
  because it can hide application bugs and complicates cancellation and upload
  backpressure semantics.
- Support HTTP/1.0 keep-alive: rejected because Choku's public milestone is
  HTTP/1.1 only.

## Third-Party Review

Reviewed by a context-free sub-agent before implementation. Feedback tightened
the design around graceful EOF before a next request, comma-separated and
repeated `Connection` token semantics, direct-deployment timeout guidance, and
high-value keep-alive regression tests.

## Validation

- Unit tests for connection header decision and serialization if exposed through
  existing `Http1` helpers.
- Network tests proving two buffered GET requests can share one connection.
- Network tests proving buffered fixed-length and chunked POST requests can be
  followed by another request on the same connection.
- Network tests proving `Connection: close`, `~keep_alive:false`, parse errors,
  handler exceptions, and streaming request modes close the connection.
- Timeout test proving `request_head_timeout` applies while waiting for a second
  request on a persistent connection.
- Tests for HEAD reuse, graceful EOF after a reusable response, connection token
  casing/comma/repeated-field handling, and pipelined bytes following a
  fixed-length body in the same socket read.

## Open Questions

None.
