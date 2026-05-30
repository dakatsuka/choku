# Access Log Middleware

## Status

Draft

## Context

Choku applications need access logs that fit Eio's direct-style IO and Choku's
handler/middleware model. A simple middleware can observe successful handler
responses and handler exceptions, but it cannot observe peer addresses,
request-head parse failures, response serialization failures, or wire byte
counts. Those require a later server-level hook.

The first access log design therefore targets handler-level access events and
provides an Eio-native writer that keeps formatted log writes out of request
fibers.

## Goals

- Add a top-level `Choku.Access_log` module.
- Represent handler-level access events without exposing request or response
  bodies.
- Keep middleware composition compatible with existing `Middleware.t`.
- Let users plug in custom formatters and event sinks.
- Provide an Eio-native bounded writer with explicit backpressure or drop
  behavior.
- Keep logging failures from changing handler responses or masking handler
  exceptions.
- Provide a CLF-style formatter for familiar access log output.

## Non-Goals

- General-purpose application logging.
- Direct dependency on `Logs`, OpenTelemetry, or any logging backend.
- Server-level events for malformed request heads, request-head timeouts,
  connection accept failures, response stream failures, or final wire byte
  counts.
- File opening, log rotation, or filesystem path management.
- Redaction, sampling, trace context propagation, or metrics aggregation.

## Proposed Design

Add `lib/access_log.mli` and `lib/access_log.ml`, re-exported as
`Choku.Access_log`.

The public event is a body-free snapshot:

```ocaml
type request = private {
  meth : Method.t;
  target : string;
  headers : Headers.t;
  protocol : string option;
}

type response = private {
  status : Status.t;
  headers : Headers.t;
}

type outcome =
  | Returned of response
  | Raised of exn
  | Cancelled

type event = private {
  request : request;
  outcome : outcome;
  started_at : float option;
  duration_ns : int64 option;
}
```

`request` is copied from the incoming `Request.t` before the wrapped handler is
called. The middleware sets `protocol = Some "HTTP/1.1"` because it only runs
inside the current HTTP/1.1 server path. A future server-level hook can populate
other protocol strings.

`response` is copied from the returned `Response.t` after the wrapped handler
returns. Only status and headers are copied. Bodies are deliberately excluded so
formatters and sinks cannot accidentally consume a streaming body.

`Cancelled` is included in the public outcome type for future server-level
events, but the first middleware preserves cancellation without logging an
event. This avoids turning cancellation into ordinary access-log data while
keeping the event shape extensible.

`status event` derives a status for formatter convenience:

- `Returned response` returns `Some response.status`;
- `Raised _` returns `Some Status.internal_server_error`;
- `Cancelled` returns `None`.

The `Raised _` status is an access-log convention matching Choku's default
server behavior for uncaught handler exceptions before response writing. It is
not proof that bytes were written on the wire.

## Middleware

The middleware has the existing middleware shape:

```ocaml
val middleware :
  ?clock:_ Eio.Time.clock ->
  ?mono_clock:_ Eio.Time.Mono.t ->
  sink ->
  Middleware.t
```

When `clock` is supplied, the middleware records `started_at` with
`Eio.Time.now clock` before invoking the wrapped handler. The value is a Unix
timestamp in seconds, matching Eio's wall-clock API and formatter needs.

When `mono_clock` is supplied, the middleware records monotonic start and finish
values around the wrapped handler with `Eio.Time.Mono.now`. It stores the
elapsed span as `duration_ns : int64 option`. The implementation should use
`Mtime.span` arithmetic and `Mtime.Span.to_uint64_ns`. If the unsigned
nanosecond value exceeds `Int64.max_int`, store `duration_ns = None`.

Handler result handling:

- On `Response.t`, build `Returned response_snapshot`, call the sink, then
  return the response.
- On non-cancellation exception, build `Raised exn`, call the sink, then
  re-raise the same exception with its backtrace preserved where practical.
- On `Eio.Cancel.Cancelled _`, re-raise cancellation without calling the sink.

Sink non-cancellation exceptions are swallowed. If both the handler and sink
raise non-cancellation exceptions, the handler exception wins. If a sink raises
`Eio.Cancel.Cancelled _`, the middleware preserves cancellation rather than
treating it as logging failure. This keeps access logging observational without
breaking Eio cancellation semantics.

Middleware ordering follows the existing `Middleware.apply` contract. Users who
want to log responses produced by error-mapping middleware should place access
logging before that middleware in the list, because `[a; b]` becomes
`a (b handler)`.

## Writer

`Access_log.Writer` owns an internal bounded queue and a writer fiber attached
to a caller-provided Eio switch:

```ocaml
module Writer : sig
  type t

  type error =
    | Formatter_failed of exn
    | Write_failed of exn
    | Writer_cancelled of exn

  type overflow = Block | Drop

  val create :
    sw:Eio.Switch.t ->
    ?capacity:int ->
    ?overflow:overflow ->
    ?on_error:(error -> unit) ->
    formatter:formatter ->
    Eio.Flow.sink_ty Eio.Resource.t ->
    t

  val sink : t -> sink
  val flush : t -> (unit, error) result
  val dropped_count : t -> int
end
```

The queue stores commands rather than only events:

```ocaml
type command =
  | Event of event
  | Flush of (unit, error) result Eio.Promise.u
```

The writer state is protected by an `Eio.Mutex.t`:

```ocaml
type state =
  | Open
  | Closed of error
```

The default queue capacity is `1024` events.

`sink writer event` first checks the state:

- `Closed _`: no-op.
- `Open` with `Block`: enqueue the event, blocking until queue capacity is
  available.
- `Open` with `Drop`: enqueue when there is capacity; otherwise increment the
  dropped counter and omit the event.

The writer fiber loops over commands. For `Event event`, it calls the formatter,
appends a newline, and writes to the supplied Eio flow. Formatting and writing
happen only in this fiber, never in request fibers when users compose middleware
with `Writer.sink`.

Formatter failure and flow write failure have different semantics:

- Formatter failure: call `on_error (Formatter_failed exn)` if present, omit
  that event, and continue processing later commands.
- Flow write failure: transition state to `Closed (Write_failed exn)`, resolve
  queued and future flushes with `Error (Write_failed exn)`, wake any blocked
  producers, call `on_error` if present, and stop writing.
- Writer fiber cancellation or finalization from switch cancellation:
  transition state to `Closed (Writer_cancelled exn)`, resolve queued and future
  flushes with `Error (Writer_cancelled exn)`, wake blocked producers, and stop
  writing.

Non-cancellation exceptions from `on_error` are ignored. Cancellation from
`on_error` is preserved in the writer fiber and closes the writer through the
writer-cancellation path above. Because `on_error` runs in the writer fiber, it
must not call `Writer.sink` or `Writer.flush` on the same writer, and it should
not perform other blocking work that depends on the same writer making progress.
For flow write failures, the writer transitions to `Closed` and wakes blocked
producers and flushes before invoking `on_error`.

`flush writer` enqueues a `Flush` command and waits on its promise. The writer
resolves the flush with:

- `Ok ()` after all earlier accepted events have been formatted and written or
  omitted due to formatter failure;
- `Error error` if the writer is already closed or closes before reaching the
  flush command.

`Flush` commands are never dropped. In `Drop` mode, `flush` still waits until
its marker can be enqueued or observes writer closure. If the writer is already
closed, `flush` returns immediately with `Error error`. `flush` does not prevent
later calls to `sink` from enqueueing more events.

`dropped_count writer` returns the number of events omitted because `Drop`
overflow found the queue full. It does not count formatter failures or writes
omitted after writer closure.

## Queue Implementation

Use a small bounded queue instead of `Eio.Stream.t`. `Eio.Stream.add` provides
the right blocking behavior for `Block`, but it does not provide a non-blocking
add operation for `Drop`.

The queue should use:

- `Queue.t`;
- `Eio.Mutex.t`;
- `Eio.Condition.t` for not-empty and not-full notifications;
- an integer capacity;
- explicit closed-state checks before blocking.

The implementation must not block forever in `Block` mode after the writer has
closed. A sink waiting for capacity must re-check writer state when woken.
Writer closure must broadcast both not-empty and not-full conditions so the
writer fiber, blocked producers, and flush callers can all observe closure.

## CLF-Style Formatter

`format_clf_style event` returns one line without a trailing newline. The writer
adds the newline.

The formatter emits fields in CLF order where middleware-level data exists:

```text
- - - [timestamp] "METHOD target PROTOCOL" status -
```

Field policy:

- remote host, RFC 1413 identity, authenticated user, and byte count are `-`;
- timestamp is formatted from `started_at` when present, otherwise `-`;
- method uses `Method.to_string`;
- target is the raw request target snapshot;
- protocol uses `event.request.protocol`, defaulting to `HTTP/1.1` for
  middleware-created events;
- status uses `Access_log.status`, or `-` for `Cancelled`.

Timestamps use UTC and the CLF timestamp shape
`[10/Oct/2000:13:55:36 +0000]`.

The request field is quoted. The formatter must escape `"` as `\"`, `\` as
`\\`, and control bytes including `0x7f` as `\xHH` so a target cannot break the
log line. The formatter should not percent-decode, normalize, or redact the
target.

Timestamp formatting should use an existing dependency if practical. Choku
already depends on `ptime.clock.os` through the client TLS stack; if a stable
formatter is available without widening the dependency set, use it. Otherwise
keep the first timestamp formatter small and documented.

## Contracts

Public interfaces must document:

- access log events are handler-level events;
- event request/response snapshots do not expose bodies;
- middleware cancellation is preserved and not logged in this milestone;
- sink exceptions are ignored;
- sink cancellation is preserved;
- writer flow write failure closes the writer;
- writer cancellation closes the writer and wakes blocked producers/flushes;
- error callbacks are non-reentrant for the same writer;
- `Block` applies backpressure only while the writer is open;
- `Drop` increments `dropped_count` when the queue is full;
- `flush` markers are never dropped;
- `flush` returns `Error Writer.error` after writer closure.

## Alternatives Considered

- Store `Request.t` and `Response.t` directly in events: rejected because they
  expose bodies, including streaming bodies, to formatters and sinks.
- Make `Access_log` a general logging facade: rejected because Choku should not
  replace application-owned logging infrastructure.
- Depend on `Logs`: rejected for the first milestone because users can bridge
  events into `Logs`, and core access logging only needs formatter/sink
  contracts.
- Write directly from middleware: rejected as the recommended path because
  blocking writes in request fibers conflict with the Eio-native access log
  goal.
- Treat formatter and flow write failures the same: rejected because formatter
  failures can be isolated to one event, while flow write failures usually mean
  the output sink is no longer usable.

## Third-Party Review

Context-free review of the product spec found that storing full `Request.t` and
`Response.t` in access events would be unsafe because those values expose
bodies. It also found that status/response/error fields should be replaced by
an outcome variant, writer close/flush semantics needed to prevent hangs,
duration should use monotonic nanoseconds rather than wall-clock floats, drop
overflow should be observable, and examples should avoid direct blocking writes
from request fibers. The product spec and this design use body-free snapshots,
an outcome variant, explicit writer closure semantics, `duration_ns`, a dropped
counter, and writer-backed examples.

A second context-free design review found that sink cancellation must not be
swallowed, writer cancellation/finalization must close the writer and wake
waiters, writer errors should distinguish formatter failure from write failure
and cancellation, flush markers must not be dropped, CLF timestamp and escaping
policy should be deterministic, and default capacity should be explicit. This
design now preserves cancellation, uses `Writer.error`, closes on writer
cancellation, treats flush markers as non-droppable, fixes CLF timestamp and
escaping policy, and sets default capacity to `1024`.

## Validation

- Unit tests for snapshot construction from `Request.t` and `Response.t` without
  exposing bodies.
- Middleware tests for returned responses, raised non-cancellation exceptions,
  cancellation preservation, sink exception swallowing, middleware ordering, and
  optional clock fields.
- Writer tests for successful writes, newline handling, `Block`, `Drop`,
  `dropped_count`, formatter failure continuation, flow write failure closure,
  sink no-op after closure, and `flush` success/error behavior.
- Formatter tests for CLF-style success, missing timestamp, raised outcome,
  cancelled outcome, quote/backslash/control escaping, and absent protocol.
- Run `dune build @fmt`, `dune exec test/test_access_log.exe`, `dune runtest`,
  and `dune build @check`.

## Open Questions

- Should `Writer.flush` be part of the first public API, or should tests use an
  internal helper until graceful shutdown requirements are clearer?
- Should formatter failure reporting be rate-limited or coalesced to avoid
  repeated `on_error` calls for a broken formatter?
- What shape should the later server-level access log hook use for peer address,
  request-head errors, wire byte counts, and response streaming failures?
