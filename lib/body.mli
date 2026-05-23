(** Buffered HTTP body values. *)

type t
(** A replayable buffered body. *)

(** Errors returned while consuming body bytes. *)
type error = Body_too_large

val empty : t
(** [empty] is a zero-length body. *)

val string : string -> t
(** [string s] is a body containing [s]. *)

val to_string : t -> string
(** [to_string t] returns the buffered body bytes. *)

val to_string_limited : max_size:int -> t -> (string, error) result
(** [to_string_limited ~max_size t] returns [t]'s bytes when their length is at
    most [max_size].

    Returns [Error Body_too_large] when [t] exceeds [max_size].

    @raise Invalid_argument if [max_size] is negative. *)

val is_buffered : t -> bool
(** [is_buffered t] is [true] when [t] is backed by replayable buffered bytes.
*)

val with_source : t -> (Eio.Flow.source_ty Eio.Resource.t -> 'a) -> 'a
(** [with_source t fn] calls [fn] with an Eio source for [t]'s bytes.

    Current bodies are buffered, so the source is replayable across separate
    [with_source] calls. Future streaming bodies may be single-consumption and
    scoped to the request handler. *)

val copy_to_sink : t -> _ Eio.Flow.sink -> unit
(** [copy_to_sink t sink] writes [t]'s bytes to [sink]. *)

val save_to_path :
  ?append:bool -> create:Eio.Fs.create -> _ Eio.Path.t -> t -> unit
(** [save_to_path ?append ~create path t] writes [t]'s bytes to [path] using
    {!Eio.Path.save}. *)

val pp_error : Format.formatter -> error -> unit
(** [pp_error formatter error] formats [error] for diagnostics. *)
