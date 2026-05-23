# HTTP Request Limits And Timeouts

## Status

Draft

## Context

Camelio currently bounds request bodies with `max_request_body_size`, rejects
unsupported transfer encodings, and closes connections after each response. The
HTTP/1.1 request-head reader still has two security-relevant gaps:

- request-line and header bytes are buffered until `\r\n\r\n` with no explicit
  maximum;
- a client can hold a connection open by slowly sending an incomplete request
  head.

These are protocol-layer concerns. Middleware and handlers run only after
`Request.t` has been constructed, so they cannot protect the parser from
unbounded header growth or slowloris-style header reads.

## Goals

- Bound memory used while reading the request line and headers.
- Bound the elapsed time spent waiting for a complete request head.
- Reject oversized request heads before handler invocation.
- Return 408 for request-head read timeout before handler invocation.
- Preserve existing body-size and route-level body-mode behavior.
- Keep defaults simple and configurable for both `Server.create` and
  `Server.create_router`.

## Non-Goals

- HTTP/1.1 keep-alive idle timeout; Camelio currently closes each connection.
- Full request body read timeout.
- Per-route timeout policy.
- Header count limits.
- HTTP/2 or HTTP/3 settings.
- Slow upload bandwidth policy for streaming request bodies.

## Proposed Design

Add request-head controls to `Server.create` and `Server.create_router`:

```ocaml
val create :
  ?max_request_body_size:int ->
  ?max_request_head_size:int ->
  ?request_head_timeout:float option ->
  ?request_body_mode:request_body_mode ->
  ?middlewares:Middleware.t list ->
  handler:Handler.t ->
  unit ->
  t

val create_router :
  ?max_request_body_size:int ->
  ?max_request_head_size:int ->
  ?request_head_timeout:float option ->
  ?middlewares:Middleware.t list ->
  Router.t ->
  t
```

`max_request_head_size` counts the bytes buffered while searching for the
request-head terminator, including the terminating `\r\n\r\n` if present. The
default should be `65_536` bytes. A negative value is invalid. A value of `0`
means no request-head bytes can be read and is allowed only if the first read
would immediately exceed the limit; practically, it rejects all non-empty
requests. If this edge case is not useful, implementation may reject
non-positive values instead.

`request_head_timeout` is the maximum time, in seconds, to receive a complete
request head. `Some seconds` must be positive. `None` disables this timeout.
The default should be `Some 30.0`. This is short enough to mitigate slowloris
behavior for direct deployments but still generous for normal clients.

`Server.t` should store both settings. `Server.max_request_body_size` remains
unchanged. A follow-up accessor for request-head settings is optional and not
required for this milestone.

## Protocol Semantics

If the request head grows beyond `max_request_head_size` before a complete
terminator is found, the server returns:

```text
HTTP/1.1 431 Request Header Fields Too Large
connection: close
```

This uses the existing `Status.request_header_fields_too_large` constant if
available; otherwise that status constant should be added.

If `request_head_timeout` expires before the complete request head is received,
the server returns:

```text
HTTP/1.1 408 Request Timeout
connection: close
```

In both cases, the handler must not run and route-level body-mode selection must
not occur.

Malformed request heads that fit within the size and timeout limits keep the
existing 400 behavior. Body-size violations keep the existing 413 behavior.

## Implementation Shape

Extend `Http1.error` with:

```ocaml
| Request_head_too_large
| Request_head_timeout
```

Map those errors in `Http1.response_for_error`.

Change `Server.read_request_head` to accept:

```ocaml
~max_request_head_size:int ->
?request_head_timeout:float ->
_ Eio.Flow.source ->
(request_head_read, Http1.error) result
```

The read loop should check the accumulated buffer size after each read and
return `Request_head_too_large` once it exceeds the configured maximum. The
timeout should wrap the full "read until headers complete" operation with
`Eio.Time.Timeout.run`.

Because `Eio.Time.Timeout.run` needs a clock, `Server.run` should pass an
`Eio.Stdenv.mono_clock env`-derived clock capability into the request-reading
path.
The current `Server.run` receives only `net`, not `env`, so there are two viable
implementation options:

- add `?clock:_ Eio.Time.clock` or `?mono_clock:_ Eio.Time.Mono.t` to
  `Server.run`;
- store an optional timeout value in `Server.t` and apply it only when
  `Server.run` is given a clock-capable runtime.

The first option is more explicit but changes the `run` call site. The second
option is awkward because timeout enforcement requires a clock. The preferred
design is to add an optional monotonic clock argument to `Server.run`:

```ocaml
val run :
  sw:Eio.Switch.t ->
  net:'a Eio.Net.t ->
  mono_clock:'b Eio.Time.Mono.t ->
  addr:Eio.Net.Sockaddr.stream ->
  t ->
  unit
```

This is a public API break for callers of `Server.run`. To avoid that break, a
compatibility alternative is:

```ocaml
val run :
  sw:Eio.Switch.t ->
  net:'a Eio.Net.t ->
  ?mono_clock:'b Eio.Time.Mono.t ->
  addr:Eio.Net.Sockaddr.stream ->
  t ->
  unit
```

Eio documents monotonic clocks as the better choice for timeouts and measuring
intervals. If `mono_clock` is omitted and `request_head_timeout = Some _`,
implementation should raise `Invalid_argument` before listening. If
`mono_clock` is omitted and the timeout is disabled, behavior remains available
for test adapters.

## Testing Strategy

Parser-level tests:

- request head at exactly the size limit succeeds;
- request head over the size limit returns `Request_head_too_large`;
- malformed but under-limit request head still returns the existing error.

Server-level network tests:

- oversized request head returns 431 and does not run the handler;
- request-head timeout returns 408 and does not run the handler;
- timeout disabled allows existing tests to keep using simple flow helpers;
- `Server.create_router` applies the same limits before route matching.

The slowloris test should open a client connection, send an incomplete request
head, wait longer than the configured timeout, then observe a 408 response and
connection close.

## Alternatives Considered

- Enforce limits in middleware: rejected because middleware runs after request
  construction.
- Only add size limits and no timeout: rejected because slowloris attacks can
  hold resources without exceeding size limits.
- Make request-head timeout server-wide and non-optional with no escape hatch:
  rejected because tests and embedded adapters may not always have a clock
  capability available.

## Validation

Implementation should run:

- `dune build @fmt`
- `dune exec test/test_http1.exe`
- `dune exec test/test_server.exe`
- `CAMELIO_RUN_NETWORK_TESTS=1 dune exec test/test_server.exe`
- `dune build @all`
- `dune runtest`
- `dune build @check`
- `dune build @install`
- `opam lint camelio.opam`

## Open Questions

- Should `max_request_head_size` allow `0`, or reject non-positive values?
- Is adding optional `?mono_clock` to `Server.run` acceptable, or should timeout
  support wait for a larger server runtime API revision?
