# Implement Access Log Middleware

## Status

Completed

## Objective

Add the first `Choku.Access_log` public API: handler-level access log events,
middleware, CLF-style formatting, and an Eio-native bounded writer.

## Context

- [Access Log Middleware Product Spec](../../product-specs/access-log.md)
- [Access Log Middleware Design](../../design-docs/access-log.md)
- [Minimal Server, Handler, and Middleware API](../../design-docs/minimal-server-handler-middleware-api.md)
- [Testing Support](../../design-docs/testing-support.md)

## Clarifications

- `Writer.flush` is part of the first public API. The product spec already
  defines its behavior, and it is needed for deterministic tests and graceful
  shutdown paths.
- The first implementation will not add `Access_log.clf_middleware`; users will
  compose `Writer.create`, `Writer.sink`, and `middleware` explicitly.
- Formatter failures will call `on_error` once per failed event. Rate limiting
  or coalescing is deferred until there is operational evidence.
- Server-level access log hooks for malformed request heads, peer addresses,
  wire byte counts, and response streaming failures are out of scope.

## Contract First

Create `lib/access_log.mli` with documented public contracts before filling in
implementation details:

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
```

The `.mli` contract comments must document handler-level event scope, body-free
snapshots, cancellation behavior, sink exception handling, writer closure,
overflow behavior, `flush`, and `dropped_count`.

## Steps

- [x] Explore: inspect existing specs, design docs, module layout, middleware
      shape, and test harness.
- [x] Design review: confirm that context-free design review feedback is already
      recorded in the Access Log design document.
- [x] Red: add `test/test_access_log.ml` covering snapshots, middleware,
      formatter behavior, writer overflow, writer errors, and flush semantics.
- [x] Green: implement `lib/access_log.mli`, `lib/access_log.ml`, and re-export
      `Choku.Access_log`.
- [x] Refactor: keep queue and writer state small, explicit, and documented by
      tests.
- [x] Static checks: run formatters and static analysis tools, then fix
      findings.
- [x] Code review: request context-free third-party review after implementation.
- [x] Re-review: fix review findings and repeat review until it passes.

## Decisions

- No ADR is required. This adds a documented middleware subsystem without
  changing server architecture or ownership boundaries.
- The first event source is middleware-level only and snapshots request/response
  metadata without exposing bodies.
- `Raised _` maps to `Status.internal_server_error` through `status`, matching
  Choku's existing uncaught-handler behavior but not claiming bytes were written.
- The default writer capacity is `1024`, and non-positive capacities raise
  `Invalid_argument`.
- The writer uses an explicit bounded queue with `Eio.Mutex.t` and
  `Eio.Condition.t`, not `Eio.Stream.t`, because `Drop` needs non-blocking
  enqueue behavior.
- CLF-style timestamps use UTC and the documented
  `[10/Oct/2000:13:55:36 +0000]` shape.
- `on_error` runs in the writer fiber and is documented as non-reentrant for the
  same writer. Flow write failures close and wake waiters before invoking
  `on_error` so callbacks can observe closure.

## Verification

- PASS: `dune build @fmt`
- PASS: `dune exec test/test_access_log.exe`
- PASS: `dune runtest`
- PASS: `dune build @check`

## Completion Notes

Added `Choku.Access_log` with body-free handler-level event snapshots,
middleware, status derivation, CLF-style formatting, and an Eio-native bounded
writer with `Block`/`Drop` overflow policies, flush support, dropped-event
counting, formatter/write/cancellation error reporting, and queue wakeup on
closure.

Added focused access-log tests covering middleware snapshots, handler
exceptions, sink failure/cancellation behavior, clock fields, formatter output,
writer flushing, formatter failure continuation, overflow behavior, write
failure closure, write-failure callback ordering, writer cancellation, and
capacity validation.

Context-free code review found one medium issue: `on_error` could deadlock when
re-entering the same writer on write failure. The implementation now closes and
wakes waiters before invoking `on_error` for write failures, and the public
contract documents same-writer callback re-entry as unsupported. Re-review
passed with only residual low-risk test-coverage notes.

## Commit

Pending. Expected message: `feat(access-log): add middleware and writer`
