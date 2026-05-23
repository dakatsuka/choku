(** HTTP body values. *)

type t
(** A request or response body.

    Bodies constructed with this module's public constructors are replayable
    buffered values. Server-created streaming request bodies are
    single-consumption and handler-scoped. *)

(** Errors returned while consuming body bytes. *)
type error = Body_too_large | Unexpected_end_of_body

exception Unexpected_end_of_body_read
(** Raised by streaming body sources when the underlying request stream ends
    before the declared body length. *)

val empty : t
(** [empty] is a zero-length body. *)

val string : string -> t
(** [string s] is a body containing [s]. *)

val to_string : t -> string
(** [to_string t] returns the buffered body bytes.

    This is a buffered compatibility helper. Code that may receive future
    streaming request bodies should prefer {!to_string_limited}.

    @raise Invalid_argument if [t] is a streaming body. *)

val to_string_limited : max_size:int -> t -> (string, error) result
(** [to_string_limited ~max_size t] returns [t]'s bytes when their length is at
    most [max_size].

    Returns [Error Body_too_large] when [t] exceeds [max_size].

    Returns [Error Unexpected_end_of_body] when a streaming body ends before its
    declared length.

    @raise Invalid_argument if [max_size] is negative. *)

val is_buffered : t -> bool
(** [is_buffered t] is [true] when [t] is backed by replayable buffered bytes.
*)

val with_source : t -> (Eio.Flow.source_ty Eio.Resource.t -> 'a) -> 'a
(** [with_source t fn] calls [fn] with an Eio source for [t]'s bytes.

    Buffered bodies create a fresh replayable source for each [with_source]
    call. Streaming bodies are single-consumption and scoped to the request
    handler.

    @raise Unexpected_end_of_body_read
      if a streaming source ends before its declared length. *)

val copy_to_sink : t -> _ Eio.Flow.sink -> unit
(** [copy_to_sink t sink] writes [t]'s bytes to [sink]. *)

val save_to_path :
  ?append:bool -> create:Eio.Fs.create -> _ Eio.Path.t -> t -> unit
(** [save_to_path ?append ~create path t] writes [t]'s bytes to [path]. *)

val pp_error : Format.formatter -> error -> unit
(** [pp_error formatter error] formats [error] for diagnostics. *)

(**/**)

module Internal : sig
  val streaming : content_length:int -> Eio.Flow.source_ty Eio.Resource.t -> t
  [@@alert internal "Camelio internal API; do not use outside the library."]
  (** [streaming ~content_length source] creates a single-consumption body
      backed by [source].

      [source] must produce at most [content_length] bytes and then report
      end-of-file. *)
end

(**/**)
