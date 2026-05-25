(** Minimal Eio-native HTTP client. *)

type t
(** Client configuration and middleware stack. *)

module Error : sig
  type timeout_phase =
    | Connect
    | Tls_handshake
    | Request_write
    | Response_head
    | Response_body
        (** Client transport phase whose configured timeout expired. *)

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
    | Tls_configuration_failed of string
    | Tls_handshake_failed of exn
    | Too_many_redirects
    | Redirect_missing_location
    | Timeout of timeout_phase

  val pp : Format.formatter -> t -> unit
  (** [pp formatter t] formats [t] for diagnostics. *)

  val equal : t -> t -> bool
  (** [equal a b] is [true] when [a] and [b] are the same error. *)
end

module Request : sig
  type scheme = Http | Https  (** Parsed URL scheme. *)

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

      The client accepts absolute [http://] and [https://] URLs and rejects
      [CONNECT]. URL validation errors are returned explicitly.

      The first HTTPS milestone accepts DNS host names only and rejects IP
      address literals in [https://] URLs. *)

  val scheme : t -> scheme
  (** [scheme t] returns the parsed URL scheme. *)

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

  val follow_redirects : ?max_redirects:int -> unit -> t
  (** [follow_redirects ?max_redirects ()] follows ordinary HTTP redirects by
      re-entering the wrapped handler with a new request. The default limit is
      [5]. [max_redirects] counts followed redirect responses, not total
      requests.

      [301], [302], [307], and [308] are followed only for [GET] and [HEAD].
      [303] is followed for any method by rewriting to [GET], except [HEAD]
      remains [HEAD].

      Redirects without [Location] return [Error Redirect_missing_location].
      Redirect chains longer than [max_redirects] return
      [Error Too_many_redirects].

      Redirect [Location] values may be absolute [http://] or [https://] URLs,
      scheme-relative URLs, path-absolute references, or query-only references.
      Fragment components are stripped before constructing the next request.
      Other relative references return [Error (Invalid_url _)].

      Redirects preserve request headers, except cross-origin redirects strip
      [Authorization], [Cookie], and [Proxy-Authorization].

      @raise Invalid_argument if [max_redirects < 0]. *)
end

module Tls : sig
  type t
  (** HTTPS trust policy. *)

  val system : unit -> (t, Error.t) result
  (** [system ()] loads the operating-system trust store. *)

  val ca_file : _ Eio.Path.t -> (t, Error.t) result
  (** [ca_file path] loads trust anchors from PEM certificates in [path]. *)

  val ca_dir : _ Eio.Path.t -> (t, Error.t) result
  (** [ca_dir path] loads trust anchors from PEM certificate files directly
      under [path]. *)
end

val create :
  ?tls:Tls.t ->
  ?max_response_head_size:int ->
  ?max_response_body_size:int ->
  ?mono_clock:Eio.Time.Mono.ty Eio.Resource.t ->
  ?connect_timeout:float option ->
  ?tls_handshake_timeout:float option ->
  ?request_write_timeout:float option ->
  ?response_head_timeout:float option ->
  ?response_body_timeout:float option ->
  ?middlewares:Middleware.t list ->
  net:_ Eio.Net.t ->
  unit ->
  t
(** [create ?tls ?max_response_head_size ?max_response_body_size ?mono_clock
     ?connect_timeout ?tls_handshake_timeout ?request_write_timeout
     ?response_head_timeout ?response_body_timeout ?middlewares ~net ()] creates
    an HTTP client.

    The default response head limit is [16_384] bytes. The default response body
    limit is [1_048_576] bytes.

    When [tls] is omitted, HTTPS requests use the operating-system trust store.
    Trust-store loading errors are returned when making an HTTPS request, not
    when creating an HTTP-only client.

    Timeouts default to [None], which disables them. When any timeout is
    configured, [mono_clock] must be provided. Timeout values are seconds and
    must be finite and positive.

    @raise Invalid_argument
      if [max_response_head_size <= 0], [max_response_body_size < 0], any
      timeout is non-finite or non-positive, or any timeout is configured
      without [mono_clock]. *)

val request : sw:Eio.Switch.t -> t -> Request.t -> (Response.t, Error.t) result
(** [request ~sw client request] sends one HTTP/1.1 request over one connection
    and returns a fully buffered response. [https://] requests wrap the TCP
    connection in TLS before HTTP bytes are exchanged.

    The caller owns [sw]. Choku closes the connection for each attempt on
    success, client error, non-cancellation exception mapping, and cancellation.
    Eio cancellation is re-raised. *)
