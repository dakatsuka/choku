(** Minimal Eio-native HTTP client. *)

type t
(** Client configuration and middleware stack. *)

module Error : sig
  type t =
    | Invalid_url of string
    | Unsupported_scheme of string
    | Connection_failed of exn
    | Malformed_response of string
    | Response_head_too_large
    | Invalid_content_length
    | Unsupported_transfer_encoding
    | Malformed_chunked_body
    | Response_body_too_large
    | Request_body_not_buffered
    | Unsupported_method of Method.t
    | Unsupported_upgrade

  val pp : Format.formatter -> t -> unit
  (** [pp formatter t] formats [t] for diagnostics. *)

  val equal : t -> t -> bool
  (** [equal a b] is [true] when [a] and [b] are the same error. *)
end

module Request : sig
  type t
  (** Outbound client request. *)

  val make :
    ?headers:Headers.t ->
    ?body:Body.t ->
    meth:Method.t ->
    url:string ->
    unit ->
    (t, Error.t) result
  (** [make ?headers ?body ~meth ~url ()] creates a client request.

      The first milestone accepts absolute [http://] URLs only and rejects
      [CONNECT]. URL validation errors are returned explicitly. *)

  val meth : t -> Method.t
  (** [meth t] returns the request method. *)

  val url : t -> string
  (** [url t] returns the original URL. *)

  val authority : t -> string
  (** [authority t] returns the normalized authority used for [Host]. *)

  val host : t -> string
  (** [host t] returns the parsed host. *)

  val port : t -> int
  (** [port t] returns the parsed port. *)

  val target : t -> string
  (** [target t] returns the origin-form request target sent on the wire. *)

  val headers : t -> Headers.t
  (** [headers t] returns user request headers. Client-owned framing headers are
      replaced during serialization. *)

  val body : t -> Body.t
  (** [body t] returns the request body. The first client transport accepts only
      buffered bodies. *)

  val with_headers : Headers.t -> t -> t
  (** [with_headers headers t] returns [t] with [headers]. *)

  val with_header : string -> string -> t -> t
  (** [with_header name value t] sets one request header using [Headers.set]. *)

  val with_body : Body.t -> t -> t
  (** [with_body body t] returns [t] with [body]. *)
end

module Response : sig
  type t
  (** Inbound client response. *)

  val make : ?headers:Headers.t -> ?body:Body.t -> Status.t -> t
  (** [make ?headers ?body status] creates a client response value. *)

  val status : t -> Status.t
  (** [status t] returns the response status. *)

  val headers : t -> Headers.t
  (** [headers t] returns response headers. *)

  val body : t -> Body.t
  (** [body t] returns the buffered response body. *)
end

module Handler : sig
  type t = Request.t -> (Response.t, Error.t) result
  (** Client handler contract. The terminal handler is the HTTP transport. *)
end

module Middleware : sig
  type t = Handler.t -> Handler.t
  (** Client middleware transforms one outbound handler into another. *)

  val identity : t
  (** [identity h] is [h]. *)

  val compose : t -> t -> t
  (** [compose a b h] is [a (b h)]. *)

  val apply : t list -> Handler.t -> Handler.t
  (** [apply [a; b; c] h] is [a (b (c h))]. *)
end

val create :
  ?max_response_head_size:int ->
  ?max_response_body_size:int ->
  ?middlewares:Middleware.t list ->
  net:'a Eio.Net.t ->
  unit ->
  t
(** [create ?max_response_head_size ?max_response_body_size ?middlewares ~net
     ()] creates a plain HTTP client.

    The default response head limit is [16_384] bytes. The default response body
    limit is [1_048_576] bytes.

    @raise Invalid_argument
      if [max_response_head_size <= 0] or [max_response_body_size < 0]. *)

val request : sw:Eio.Switch.t -> t -> Request.t -> (Response.t, Error.t) result
(** [request ~sw client request] sends one HTTP/1.1 request over one plain TCP
    connection and returns a fully buffered response.

    The caller owns [sw]. Choku closes the connection for each attempt on
    success, client error, non-cancellation exception mapping, and cancellation.
    Eio cancellation is re-raised. *)
