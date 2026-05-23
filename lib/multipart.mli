(** Buffered multipart/form-data values. *)

type t
(** Immutable ordered multipart part collection. *)

(** Errors returned while reading multipart form-data from a request. *)
type error =
  | Missing_content_type
  | Unsupported_content_type of string
  | Missing_boundary
  | Malformed_body

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
end

val decode : boundary:string -> string -> (t, error) result
(** [decode ~boundary body] parses [body] as multipart data using [boundary].

    Returns [Error Missing_boundary] when [boundary] is empty and
    [Error Malformed_body] when [body] is not valid multipart syntax. *)

val of_request : Request.t -> (t, error) result
(** [of_request request] parses [request]'s body as [multipart/form-data].

    The request must have [Content-Type: multipart/form-data] with a non-empty
    [boundary] parameter. Media type matching is case-insensitive. *)

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
