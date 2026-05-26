(** Parsed request metadata available before request body delivery. *)

type t

val make : meth:Method.t -> target:string -> headers:Headers.t -> t
(** [make ~meth ~target ~headers] creates a request-head value.

    [target] uses the same origin-form subset as {!Request.make}: a
    slash-prefixed path with an optional query string and no fragment marker,
    control bytes, spaces, or DEL.

    This constructor does not require or validate the HTTP/1.1 [Host] header.

    @raise Invalid_argument if [target] is not a valid origin-form target. *)

val meth : t -> Method.t
(** [meth t] returns the request method. *)

val target : t -> string
(** [target t] returns the raw request-target. *)

val path : t -> string
(** [path t] returns the origin-form path without the query string. *)

val query_string : t -> string option
(** [query_string t] returns the raw query component without the leading [?], if
    the request target has one.

    Returns [None] when the target has no query component. Returns [Some ""]
    when the target ends with [?]. *)

val headers : t -> Headers.t
(** [headers t] returns request headers. *)
