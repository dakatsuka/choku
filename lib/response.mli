(** HTTP server response values. *)

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
    response bodies are single-consumption. Open files or allocate other
    stream-scoped resources inside [write] so their lifetime covers response
    serialization.

    When [content_length] is omitted, the HTTP/1.1 server writes the response
    with [Transfer-Encoding: chunked]. When [content_length] is provided,
    [write] must write exactly that many bytes; writing fewer or more bytes is
    treated as a streaming failure and closes the connection.

    The HTTP/1.1 server owns [Content-Length], [Transfer-Encoding], and
    [Connection] while serializing responses. Values for those headers in
    [headers] are replaced.

    [write] is not invoked for [HEAD] responses or for statuses that cannot
    carry a response body, such as [1xx], [204], and [304].

    @raise Invalid_argument if [content_length] is negative. *)

val status : t -> Status.t
(** [status t] returns the response status. *)

val headers : t -> Headers.t
(** [headers t] returns response headers. *)

val body : t -> Body.t
(** [body t] returns the response body. *)

val with_header : string -> string -> t -> t
(** [with_header name value t] sets a response header using [Headers.set]. *)

val add_header : string -> string -> t -> t
(** [add_header name value t] appends a response header using [Headers.add]. *)
