(** HTTP request values shared by server and future client APIs. *)

type t

val make :
  meth:Method.t -> target:string -> headers:Headers.t -> body:Body.t -> t
(** [make ~meth ~target ~headers ~body] creates a request.

    The first milestone supports origin-form targets only. [target] must be a
    non-empty string starting with ['/'].

    @raise Invalid_argument if [target] is not a valid origin-form target. *)

val meth : t -> Method.t
(** [meth t] returns the request method. *)

val target : t -> string
(** [target t] returns the raw request-target. *)

val path : t -> string
(** [path t] returns the origin-form path without the query string. *)

val headers : t -> Headers.t
(** [headers t] returns request headers. *)

val body : t -> Body.t
(** [body t] returns the buffered request body. *)
