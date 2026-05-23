(** URL-encoded form values. *)

type t
(** Immutable ordered form field collection. *)

(** Errors returned while reading URL-encoded form data from a request. *)
type error =
  | Missing_content_type
  | Unsupported_content_type of string
  | Malformed_percent_encoding

val empty : t
(** [empty] contains no form fields. *)

val decode : string -> (t, error) result
(** [decode body] parses an [application/x-www-form-urlencoded] payload.

    [decode] preserves repeated fields, decodes ['+'] as space, and decodes
    percent-encoded bytes. It does not validate character encoding.

    Returns [Error Malformed_percent_encoding] when [body] contains a malformed
    percent escape. *)

val of_request : Request.t -> (t, error) result
(** [of_request request] parses [request]'s body as URL-encoded form data.

    The request must have [Content-Type: application/x-www-form-urlencoded].
    Media type matching is case-insensitive and ignores parameters. *)

val get : string -> t -> string option
(** [get name t] returns the first value for [name], if present. *)

val get_all : string -> t -> string list
(** [get_all name t] returns all values for [name] in insertion order. *)

val to_list : t -> (string * string) list
(** [to_list t] returns all fields in insertion order. *)

val pp_error : Format.formatter -> error -> unit
(** [pp_error formatter error] formats [error] for diagnostics. *)
