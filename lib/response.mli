(** HTTP response values. *)

type t

val make : ?headers:Headers.t -> ?body:Body.t -> Status.t -> t
(** [make ?headers ?body status] creates a response. *)

val text : ?status:Status.t -> string -> t
(** [text ?status body] creates a text/plain UTF-8 response. *)

val status : t -> Status.t
(** [status t] returns the response status. *)

val headers : t -> Headers.t
(** [headers t] returns response headers. *)

val body : t -> Body.t
(** [body t] returns the buffered response body. *)

val with_header : string -> string -> t -> t
(** [with_header name value t] sets a response header using [Headers.set]. *)
