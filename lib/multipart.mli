(** Buffered multipart/form-data values. *)

type t
(** Immutable ordered multipart part collection. *)

(** Errors returned while reading multipart form-data from a request. *)
type error =
  | Missing_content_type
  | Unsupported_content_type of string
  | Missing_boundary
  | Malformed_body
  | Body_too_large
  | Unexpected_end_of_body

module Part : sig
  type t
  (** One buffered multipart part. *)

  val headers : t -> Headers.t
  (** [headers t] returns the part headers in insertion order. *)

  val name : t -> string option
  (** [name t] returns the [Content-Disposition] [name] parameter, if present.
  *)

  val filename : t -> string option
  (** [filename t] returns the [Content-Disposition] [filename] parameter, if
      present. *)

  val content_type : t -> string option
  (** [content_type t] returns the part [Content-Type] header, if present. *)

  val body : t -> Body.t
  (** [body t] returns the buffered part body. *)

  val copy_to_sink : t -> _ Eio.Flow.sink -> unit
  (** [copy_to_sink t sink] writes the buffered part body to [sink]. *)

  val save_to_path :
    ?append:bool -> create:Eio.Fs.create -> _ Eio.Path.t -> t -> unit
  (** [save_to_path ?append ~create path t] writes the buffered part body to
      [path] using {!Eio.Path.save}. *)
end

module Streaming : sig
  type part
  (** Metadata for one streaming multipart part. *)

  val headers : part -> Headers.t
  (** [headers part] returns the part headers in insertion order. *)

  val name : part -> string option
  (** [name part] returns the [Content-Disposition] [name] parameter, if
      present. *)

  val filename : part -> string option
  (** [filename part] returns the [Content-Disposition] [filename] parameter, if
      present. *)

  val content_type : part -> string option
  (** [content_type part] returns the part [Content-Type] header, if present. *)

  val iter_request :
    ?max_header_size:int ->
    Request.t ->
    on_part:(part -> Eio.Flow.source_ty Eio.Resource.t -> unit) ->
    (unit, error) result
  (** [iter_request ?max_header_size request ~on_part] streams each multipart
      part in [request] to [on_part].

      The request must have [Content-Type: multipart/form-data] with a non-empty
      [boundary] parameter. Media type matching is case-insensitive.

      Each part source is valid only for the dynamic extent of its [on_part]
      callback. If [on_part] returns before consuming the source, the iterator
      drains the rest of that part before reading the next one.

      [max_header_size] defaults to [8192] bytes.

      @raise Invalid_argument if [max_header_size] is negative. *)
end

val decode : boundary:string -> string -> (t, error) result
(** [decode ~boundary body] parses [body] as multipart data using [boundary].

    Returns [Error Missing_boundary] when [boundary] is empty and
    [Error Malformed_body] when [body] is not valid multipart syntax. *)

val of_request : Request.t -> (t, error) result
(** [of_request request] parses [request]'s buffered body as
    [multipart/form-data].

    The request must have [Content-Type: multipart/form-data] with a non-empty
    [boundary] parameter. Media type matching is case-insensitive. *)

val of_request_limited : max_size:int -> Request.t -> (t, error) result
(** [of_request_limited ~max_size request] parses [request]'s body as
    [multipart/form-data] after reading at most [max_size] bytes into memory.

    This is the bounded request helper for code that may receive streaming
    request bodies.

    Returns [Error Body_too_large] when the request body exceeds [max_size] and
    [Error Unexpected_end_of_body] when a streaming request body ends before its
    declared length.

    @raise Invalid_argument if [max_size] is negative. *)

val parts : t -> Part.t list
(** [parts t] returns all parts in insertion order. *)

val get : string -> t -> Part.t option
(** [get name t] returns the first part whose field name is [name], if present.
*)

val get_all : string -> t -> Part.t list
(** [get_all name t] returns all parts whose field name is [name] in insertion
    order. *)

val pp_error : Format.formatter -> error -> unit
(** [pp_error formatter error] formats [error] for diagnostics. *)
