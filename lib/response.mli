(** HTTP response values. *)

type t

val make : ?headers:Headers.t -> ?body:Body.t -> Status.t -> t
(** [make ?headers ?body status] creates a response. *)

val text : ?status:Status.t -> string -> t
(** [text ?status body] creates a text/plain UTF-8 response. *)

val stream :
  ?status:Status.t ->
  ?headers:Headers.t ->
  ?content_length:int ->
  (Eio.Flow.sink_ty Eio.Resource.t -> unit) ->
  t
(** [stream ?status ?headers ?content_length write] creates a streaming response
    whose body is produced by [write].

    [write] is invoked by the server while serializing the response. The sink
    passed to [write] is valid only for that callback invocation. Streaming
    response bodies are single-consumption.

    @raise Invalid_argument if [content_length] is negative. *)

val status : t -> Status.t
(** [status t] returns the response status. *)

val headers : t -> Headers.t
(** [headers t] returns response headers. *)

val body : t -> Body.t
(** [body t] returns the response body. *)

val with_header : string -> string -> t -> t
(** [with_header name value t] sets a response header using [Headers.set]. *)
