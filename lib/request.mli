(** HTTP server request values. *)

type t

val make :
  meth:Method.t -> target:string -> headers:Headers.t -> body:Body.t -> t
(** [make ~meth ~target ~headers ~body] creates a request.

    The first milestone supports origin-form targets only. [target] must be a
    slash-prefixed path with an optional query string. It must not contain a
    fragment marker, control bytes, spaces, or DEL.

    @raise Invalid_argument if [target] is not a valid origin-form target. *)

val meth : t -> Method.t
(** [meth t] returns the request method. *)

val target : t -> string
(** [target t] returns the raw request-target. *)

val path : t -> string
(** [path t] returns the origin-form path without the query string. *)

val path_segments : t -> string list
(** [path_segments t] returns {!path} split into raw URL path segments without
    the leading slash.

    The root path ["/"] returns the empty list. Empty segments are preserved.
    Segments are not percent-decoded, normalized, or otherwise interpreted. *)

val headers : t -> Headers.t
(** [headers t] returns request headers. *)

val body : t -> Body.t
(** [body t] returns the request body.

    The body may be buffered or streaming depending on server and route
    configuration. Use {!Body.is_buffered} or {!Body.with_source} when the
    delivery mode matters. *)
