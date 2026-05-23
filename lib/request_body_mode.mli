(** Request body delivery modes.

    [Buffered] reads the full request body before invoking a handler and keeps
    it replayable. [Streaming] invokes a handler with a single-consumption body
    source capped to the request's declared [Content-Length]. *)
type t = Buffered | Streaming

val equal : t -> t -> bool
(** [equal a b] is [true] when [a] and [b] are the same body mode. *)

val pp : Format.formatter -> t -> unit
(** [pp formatter t] formats [t] for diagnostics. *)
