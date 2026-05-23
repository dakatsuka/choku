(** HTTP response status values. *)

type t

val code : t -> int
(** [code t] returns the three-digit status code. *)

val reason : t -> string
(** [reason t] returns the reason phrase. Unknown valid codes have an empty
    reason phrase. *)

val of_code : int -> t
(** [of_code code] returns a status for [code].

    @raise Invalid_argument if [code] is outside 100 through 599. *)

val ok : t
val bad_request : t
val not_found : t
val payload_too_large : t
val internal_server_error : t
