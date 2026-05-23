(** Buffered HTTP body values. *)

type t
(** A replayable buffered body. *)

val empty : t
(** [empty] is a zero-length body. *)

val string : string -> t
(** [string s] is a body containing [s]. *)

val to_string : t -> string
(** [to_string t] returns the buffered body bytes. *)
