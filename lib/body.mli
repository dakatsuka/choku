(** Buffered HTTP body values. *)

type t
(** A replayable buffered body. *)

val empty : t
(** [empty] is a zero-length body. *)

val string : string -> t
(** [string s] is a body containing [s]. *)

val to_string : t -> string
(** [to_string t] returns the buffered body bytes. *)

val is_buffered : t -> bool
(** [is_buffered t] is [true] when [t] is backed by replayable buffered bytes.
*)

val with_source : t -> (Eio.Flow.source_ty Eio.Resource.t -> 'a) -> 'a
(** [with_source t fn] calls [fn] with an Eio source for [t]'s bytes.

    Current bodies are buffered, so the source is replayable across separate
    [with_source] calls. Future streaming bodies may be single-consumption and
    scoped to the request handler. *)
