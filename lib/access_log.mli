(** Handler-level HTTP server access logging.

    Access log events produced by this module's middleware are handler-level
    observations. They do not include malformed request heads, peer addresses,
    wire byte counts, response serialization failures, or other server-level
    outcomes. *)

type request = private {
  meth : Method.t;
  target : string;
  headers : Headers.t;
  protocol : string option;
}
(** Body-free request metadata captured before the wrapped handler runs. *)

type response = private { status : Status.t; headers : Headers.t }
(** Body-free response metadata captured after the wrapped handler returns. *)

(** Handler-level outcome.

    [Cancelled] is reserved for future server-level hooks. The middleware in
    this module preserves cancellation and does not emit cancellation events. *)
type outcome = Returned of response | Raised of exn | Cancelled

type event = private {
  request : request;
  outcome : outcome;
  started_at : float option;
  duration_ns : int64 option;
}
(** One access log event.

    [started_at], when present, is a Unix timestamp in seconds. [duration_ns],
    when present, is measured using a monotonic clock. *)

type sink = event -> unit
(** Event sink called by middleware.

    Non-cancellation exceptions raised by a sink are ignored. Cancellation
    raised by a sink is preserved. *)

type formatter = event -> string
(** Formats one event as a single log line without a trailing newline. *)

val status : event -> Status.t option
(** [status event] returns the response status for [Returned],
    [500 Internal Server Error] for [Raised], and [None] for [Cancelled]. *)

val middleware :
  ?clock:_ Eio.Time.clock ->
  ?mono_clock:_ Eio.Time.Mono.t ->
  sink ->
  Middleware.t
(** [middleware ?clock ?mono_clock sink] records handler-level access events.

    The middleware snapshots request method, target, headers, and protocol
    before calling the wrapped handler. It snapshots response status and headers
    after a response is returned. Request and response bodies are never exposed
    through events.

    If the wrapped handler raises a non-cancellation exception, the middleware
    emits a [Raised] event and re-raises the same exception. If the handler
    raises {!Eio.Cancel.Cancelled}, cancellation is re-raised and no event is
    emitted.

    Sink non-cancellation exceptions are ignored so access logging cannot change
    handler responses or mask handler exceptions. Sink cancellation is re-raised
    to preserve Eio cancellation semantics. *)

val format_clf_style : formatter
(** [format_clf_style event] formats [event] as a CLF-style line:

    {v - - - [timestamp] "METHOD target PROTOCOL" status - v}

    Middleware-unavailable fields are rendered as [-]. Timestamps use UTC. The
    request field escapes double quotes, backslashes, and control bytes,
    including [0x7f], using deterministic backslash escapes. *)

module Writer : sig
  type t
  (** Eio-native bounded access log writer. *)

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
  (** [create ~sw ?capacity ?overflow ?on_error ~formatter flow] starts a writer
      fiber attached to [sw].

      The writer owns a bounded queue. [capacity] defaults to [1024] and must be
      positive.

      Formatter failures are reported as [Formatter_failed] and the writer
      continues with later events. Flow write failures are reported as
      [Write_failed], close the writer, wake blocked producers and flushes, and
      make later sink calls no-ops. Writer cancellation is reported as
      [Writer_cancelled], closes the writer, and wakes blocked producers and
      flushes.

      Non-cancellation exceptions from [on_error] are ignored. Cancellation from
      [on_error] is preserved in the writer fiber. [on_error] runs in the writer
      fiber, so it must not call [sink] or [flush] on the same writer or perform
      other work that waits for the same writer fiber to make progress.

      @raise Invalid_argument if [capacity] is not positive. *)

  val sink : t -> sink
  (** [sink t event] enqueues [event] for the writer fiber.

      With [Block], a full queue applies backpressure while the writer is open.
      With [Drop], a full queue omits the new event and increments
      {!dropped_count}. After writer closure, [sink] is a no-op. *)

  val flush : t -> (unit, error) result
  (** [flush t] waits until events accepted before the flush call have been
      written or omitted due to formatter failure.

      Flush markers are never dropped. In [Drop] mode, [flush] still waits until
      its marker can be enqueued or observes writer closure. After writer
      closure, [flush] returns [Error error]. *)

  val dropped_count : t -> int
  (** [dropped_count t] returns the number of events omitted because [Drop]
      overflow found the queue full. It does not count formatter failures or
      events ignored after writer closure. *)
end
