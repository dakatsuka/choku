(** HTTP header fields. *)

type t
(** Header collection preserving insertion order. Field-name lookup is
    case-insensitive. *)

val empty : t
(** [empty] has no fields. *)

val add : string -> string -> t -> t
(** [add name value headers] appends a new field after existing fields.

    @raise Invalid_argument
      if [name] is not a valid HTTP field name or [value] contains CR or LF. *)

val set : string -> string -> t -> t
(** [set name value headers] removes all fields whose names match [name]
    case-insensitively, then appends [(name, value)] at the end.

    @raise Invalid_argument
      if [name] is not a valid HTTP field name or [value] contains CR or LF. *)

val get : string -> t -> string option
(** [get name headers] returns the first matching value in insertion order. *)

val get_all : string -> t -> string list
(** [get_all name headers] returns all matching values in insertion order. *)

val to_list : t -> (string * string) list
(** [to_list headers] returns fields in insertion order. *)

val is_valid_name : string -> bool
(** [is_valid_name name] is [true] when [name] is a valid HTTP token. *)

val is_valid_value : string -> bool
(** [is_valid_value value] is [true] when [value] contains no CR or LF. *)
