(** HTTP method values. *)

type t = GET | HEAD | POST | PUT | PATCH | DELETE | OPTIONS | Other of string

val to_string : t -> string
(** [to_string t] returns the method token for [t]. *)

val of_string : string -> t
(** [of_string token] parses an HTTP method token.

    Known uppercase methods map to their constructors. Other valid method tokens
    become [Other token] and preserve the original case.

    @raise Invalid_argument if [token] is not a valid HTTP token. *)

val pp : Format.formatter -> t -> unit
(** [pp] formats a method token. *)

val equal : t -> t -> bool
(** [equal a b] is [true] when [a] and [b] are the same method value. *)
