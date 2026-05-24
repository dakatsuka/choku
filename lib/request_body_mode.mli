(** Request body delivery modes.

    [Buffered] reads the full request body before invoking a handler and keeps
    it replayable. [Streaming] invokes a handler with a single-consumption body
    source. Fixed-length streaming bodies are capped to the declared
    [Content-Length]; chunked streaming bodies are decoded by the protocol
    source and capped by the configured decoded body limit. *)
type t = Buffered | Streaming

val equal : t -> t -> bool
(** [equal a b] is [true] when [a] and [b] are the same body mode. *)

val pp : Format.formatter -> t -> unit
(** [pp formatter t] formats [t] for diagnostics. *)
