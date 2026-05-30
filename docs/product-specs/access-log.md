# Access Log Middleware

## Status

Draft

## Problem

Applications running Choku as an HTTP server need a standard way to emit access
logs without each application reimplementing request timing, response status
capture, log formatting, and Eio-safe output handling.

Access logging should be useful out of the box, but it should not force one log
format or one observability stack on applications. Many users will want
Common-Log-Format-style lines for compatibility with existing tools, while
others will want JSON, structured application logs, or OpenTelemetry integration.

The first built-in access logging surface should therefore expose a small event
model and Eio-native writer. CLF-style output should be one formatter over that
event model, not the only logging path.

## Goals

- Provide a built-in `Choku.Access_log` module for HTTP server access logs.
- Let users add access logging through ordinary Choku middleware.
- Keep request handling Eio-native by avoiding blocking filesystem or terminal
  writes in request fibers by default.
- Provide a bounded Eio writer that writes formatted access log lines from a
  dedicated fiber.
- Let users choose whether a full log queue applies backpressure or drops new
  events.
- Provide a CLF-style formatter for users who want familiar access log lines.
- Let applications provide custom formatters, including JSON formatters, without
  depending on another logging package.
- Preserve handler behavior when logging sinks or background log writes fail.
- Keep OpenTelemetry-specific support out of the core package so Choku does not
  depend on an OpenTelemetry library.

## Non-Goals

- General-purpose application logging.
- A logging facade that replaces `Logs`, OpenTelemetry, or application-owned
  log infrastructure.
- Server-level access logging for malformed request heads, request-head
  timeouts, protocol parse errors, or connection accept errors in this
  milestone.
- Exact Common Log Format parity in the middleware-only milestone.
- Remote peer address, authenticated user, HTTP version negotiation, wire byte
  counts, or final serializer failure reporting.
- Access log sampling, redaction policy, correlation IDs, trace/span context, or
  log rotation.
- Writing logs to files by path. Applications own file opening and pass an Eio
  sink to Choku.

## Requirements

- Access logging is exposed as `Choku.Access_log`.
- `Access_log.event` represents one handler-level request outcome.
- Events contain body-free request and response snapshots. They must not expose
  `Request.t`, `Response.t`, or `Body.t` values.
- The event includes:
  - request method, target, headers, and optional protocol string;
  - the response status and headers when the wrapped handler returned one;
  - an explicit outcome for returned responses, non-cancellation exceptions, and
    cancellation;
  - optional request start wall-clock time;
  - optional handler duration in nanoseconds.
- If the wrapped handler returns a response, the event outcome is `Returned`
  with a response snapshot.
- If the wrapped handler raises a non-cancellation exception, the middleware
  emits an event with outcome `Raised exn` and re-raises the same exception.
- If the wrapped handler raises `Eio.Cancel.Cancelled _`, the middleware must
  preserve cancellation. It must not convert cancellation into a response or a
  non-cancellation exception.
- The first middleware does not emit cancellation events. The `Cancelled`
  outcome is reserved for future server-level access log hooks that can observe
  connection cancellation as an access outcome.
- The access log middleware must not read or consume request or response bodies,
  and its event type must not make body consumption possible.
- Middleware ordering affects what the access log observes. To log responses
  after application error mapping, users should put access logging before the
  error-mapping middleware in the `middlewares` list, because Choku applies
  `[a; b]` as `a (b handler)`.
- The middleware accepts an event sink. A sink is ordinary OCaml code, so users
  can write JSON, call `Logs`, enqueue to another system, or collect events in
  tests.
- Non-cancellation exceptions raised by a sink must not change the response
  returned by the wrapped handler and must not mask a handler exception.
- If a sink raises `Eio.Cancel.Cancelled _`, the middleware must preserve
  cancellation rather than treating it as logging failure.
- The middleware accepts an optional wall clock. When provided, events include a
  request start timestamp suitable for formatter use.
- The middleware accepts an optional monotonic clock. When provided, events
  include handler duration in nanoseconds. Duration must be measured with the
  monotonic clock, not wall-clock time.
- If a measured duration cannot fit in a signed 64-bit nanosecond value, the
  middleware records `duration_ns = None`.
- `Access_log.Writer.create` creates an Eio-native writer attached to a caller
  supplied switch.
- The writer accepts events through `Access_log.Writer.sink writer`.
- The writer formats events and writes one newline-terminated line per event to
  an application-supplied Eio flow sink.
- The writer must perform flow writes in its own fiber, not in request handler
  fibers.
- The writer queue is bounded. Capacity defaults to a documented positive value.
- The default writer capacity is `1024` events.
- If the queue is full and overflow policy is `Block`, calls to the writer sink
  wait until there is capacity.
- If the queue is full and overflow policy is `Drop`, the new event is omitted.
- Dropped events caused by `Drop` overflow are counted and can be inspected.
- Formatter failures are reported to an optional error callback as
  `Formatter_failed exn`. The failed event is omitted and the writer continues
  with later events.
- Flow write failures are reported to an optional error callback as
  `Write_failed exn` and close the writer.
- Writer fiber cancellation is reported to an optional error callback as
  `Writer_cancelled exn` and closes the writer.
- After the writer is closed, calls to the writer sink are no-ops even when
  overflow policy is `Block`.
- Error callback non-cancellation exceptions are ignored so logging failure
  never propagates into request fibers. Error callbacks run in the writer fiber
  and must not call `Writer.sink` or `Writer.flush` on the same writer.
  Error callback cancellation is preserved in the writer fiber.
- The writer exposes a flush operation so tests and graceful shutdown paths can
  wait until events queued before the flush call have been written or learn that
  the writer closed after a write failure.
- `Access_log.format_clf_style` formats one event as a CLF-style line.
- The CLF-style formatter uses `-` for fields unavailable to middleware, such as
  remote host, RFC 1413 identity, authenticated user, and response byte count.
- The CLF-style formatter uses the event wall-clock timestamp when present and
  `-` when absent. Timestamps are formatted in UTC as
  `[10/Oct/2000:13:55:36 +0000]`.
- The CLF-style request field uses the request method, request target, and
  the event protocol when present. Middleware-created events use `HTTP/1.1`.
- The CLF-style formatter escapes request-target bytes that cannot safely appear
  inside the quoted request field: `"` as `\"`, `\` as `\\`, and control bytes
  including `0x7f` as `\xHH`.
- The first milestone does not log handler-preceding server errors such as
  malformed request heads or request-head timeout responses. A later server-level
  access log hook may add those events.

## Public Contracts

Expected public API:

```ocaml
module Access_log : sig
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

  type sink = event -> unit
  type formatter = event -> string

  val status : event -> Status.t option

  val middleware :
    ?clock:_ Eio.Time.clock ->
    ?mono_clock:_ Eio.Time.Mono.t ->
    sink ->
    Middleware.t

  val format_clf_style : formatter

  module Writer : sig
    type t

    type error =
      | Formatter_failed of exn
      | Write_failed of exn
      | Writer_cancelled of exn

    type overflow =
      | Block
      | Drop

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
end
```

`capacity` defaults to `1024` and must be positive. `create` raises
`Invalid_argument` for non-positive capacities.

`status event` returns the returned response status for `Returned`, `500
Internal Server Error` for `Raised`, and `None` for `Cancelled`.

`Writer.flush writer` waits until events accepted by `Writer.sink writer`
before the flush call have either been written or, under `Drop`, have already
been dropped. Flush markers are never dropped; in `Drop` mode, `flush` still
waits until its marker can be enqueued or observes writer closure. It returns
`Error error` when the writer has already closed because of a flow write failure
or writer cancellation. It does not prevent later events from being enqueued.
If a flow write fails, the writer closes and wakes blocked producers and flushes
before invoking `on_error`.

The public `.mli` file must document that middleware events are handler-level
events, not complete server access events.

## Examples

CLF-style access logs to standard error:

```ocaml
Eio_main.run @@ fun env ->
Eio.Switch.run @@ fun sw ->
let access_log =
  Choku.Access_log.Writer.create ~sw
    ~formatter:Choku.Access_log.format_clf_style
    (Eio.Stdenv.stderr env)
in
let server =
  Choku.Server.create_router
    ~middlewares:
      [
        Choku.Access_log.middleware
          ~clock:(Eio.Stdenv.clock env)
          ~mono_clock:(Eio.Stdenv.mono_clock env)
          (Choku.Access_log.Writer.sink access_log);
      ]
    router
in
Choku.Server.run ~sw
  ~net:(Eio.Stdenv.net env)
  ~mono_clock:(Eio.Stdenv.mono_clock env)
  ~addr:(`Tcp (Eio.Net.Ipaddr.V4.loopback, 8080))
  server
```

Custom JSON-style formatter:

```ocaml
let format_json_access_log event =
  let module Access_log = Choku.Access_log in
  let status =
    event
    |> Access_log.status
    |> Option.map Choku.Status.code
    |> Option.map string_of_int
    |> Option.value ~default:"null"
  in
  let request = event.Access_log.request in
  let meth = Choku.Method.to_string request.meth in
  let target = request.target in
  Printf.sprintf
    {|{"method":%S,"target":%S,"status":%s}|}
    meth target status

let access_log =
  Choku.Access_log.Writer.create ~sw
    ~formatter:format_json_access_log
    (Eio.Stdenv.stderr env)

let server =
  Choku.Server.create
    ~middlewares:
      [ Choku.Access_log.middleware (Choku.Access_log.Writer.sink access_log) ]
    ~handler
    ()
```

Backpressure-sensitive deployments can choose whether logging slows requests or
drops events:

```ocaml
let access_log =
  Choku.Access_log.Writer.create ~sw
    ~capacity:4096
    ~overflow:Choku.Access_log.Writer.Drop
    ~formatter:Choku.Access_log.format_clf_style
    (Eio.Stdenv.stderr env)
```

## Open Questions

- Should the first implementation expose a convenience
  `Access_log.clf_middleware` helper that creates both middleware and writer, or
  is the explicit writer plus middleware composition clearer?
- Should formatter failures call `on_error` once per failed event, or should
  the writer suppress repeated formatter failures until a successful write
  occurs?
- What server-level access log hook should later capture malformed request
  heads, peer addresses, wire byte counts, and response streaming failures?
