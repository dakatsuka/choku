(** URL query parameter values. *)

type t
(** Immutable ordered query parameter collection. *)

(** Errors returned while decoding query parameters. *)
type error = Malformed_percent_encoding

val empty : t
(** [empty] contains no query parameters. *)

val decode : string -> (t, error) result
(** [decode raw_query] parses a raw query string without a leading [?].

    [decode] preserves repeated parameters, decodes ['+'] as space, and decodes
    percent-encoded bytes. It does not validate character encoding.

    Empty query strings decode to {!empty}. Empty entries produced by [&] are
    preserved as empty-name, empty-value parameters.

    Returns [Error Malformed_percent_encoding] when [raw_query] contains a
    malformed percent escape. *)

val of_request : Request.t -> (t, error) result
(** [of_request request] parses the query string from [request].

    Requests without a query string decode to {!empty}. *)

val get : string -> t -> string option
(** [get name t] returns the first value for [name], if present. *)

val get_all : string -> t -> string list
(** [get_all name t] returns all values for [name] in insertion order. *)

val to_list : t -> (string * string) list
(** [to_list t] returns all parameters in insertion order. *)

val pp_error : Format.formatter -> error -> unit
(** [pp_error formatter error] formats [error] for diagnostics. *)
