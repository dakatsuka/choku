(** Minimal Eio HTTP server. *)

type t

(** Request body delivery mode.

    [Buffered] reads the full request body before invoking the handler and keeps
    it replayable. [Streaming] invokes the handler with a single-consumption
    body source. Fixed-length streaming bodies are capped to the declared
    [Content-Length]; chunked streaming bodies are decoded by the protocol
    source and capped by the configured decoded body limit. *)
type request_body_mode = Request_body_mode.t = Buffered | Streaming

val create :
  ?keep_alive:bool ->
  ?max_request_body_size:int ->
  ?max_request_head_size:int ->
  ?request_head_timeout:float option ->
  ?request_body_mode:request_body_mode ->
  ?middlewares:Middleware.t list ->
  handler:Handler.t ->
  unit ->
  t
(** [create ?keep_alive ?max_request_body_size ?max_request_head_size
     ?request_head_timeout ?request_body_mode ?middlewares ~handler ()] creates
    a server.

    [keep_alive] defaults to [true]. [max_request_body_size] defaults to
    [1_048_576] bytes. [max_request_head_size] defaults to [65_536] bytes.
    [request_head_timeout] defaults to [None]. [middlewares] are applied with
    [Middleware.apply] exactly once. [request_body_mode] defaults to [Buffered].
*)

val create_with_request_body_selector :
  ?keep_alive:bool ->
  ?max_request_body_size:int ->
  ?max_request_head_size:int ->
  ?request_head_timeout:float option ->
  request_body_mode:(Request_head.t -> request_body_mode) ->
  ?middlewares:Middleware.t list ->
  handler:Handler.t ->
  unit ->
  t
(** [create_with_request_body_selector ?keep_alive ?max_request_body_size
     ?max_request_head_size ?request_head_timeout ~request_body_mode
     ?middlewares ~handler ()] creates a handler-backed server whose request
    body delivery mode is selected from the parsed request head before body
    delivery.

    The selector runs once per successfully parsed request head, before the
    request body is read and before middleware or handler execution. It may
    inspect method, target, path, query string, and headers through
    {!Request_head}.

    If the selector raises a non-cancellation exception, the server writes
    [500 Internal Server Error] when possible and closes the connection. HEAD
    requests still suppress response body bytes. [Eio.Cancel.Cancelled _]
    propagates as cancellation. *)

val create_router :
  ?keep_alive:bool ->
  ?max_request_body_size:int ->
  ?max_request_head_size:int ->
  ?request_head_timeout:float option ->
  ?middlewares:Middleware.t list ->
  Router.t ->
  t
(** [create_router ?keep_alive ?max_request_body_size ?max_request_head_size
     ?request_head_timeout ?middlewares router] creates a server from [router].

    Route-level request body modes are selected after request-head parsing and
    before request body delivery. Routes without an explicit body mode and
    unmatched requests use [Buffered]. [middlewares] wrap the final router
    handler exactly once and cannot affect body-mode selection. *)

val max_request_body_size : t -> int
(** [max_request_body_size t] returns the configured body limit. *)

val handle : t -> Request.t -> Response.t
(** [handle t request] invokes the composed handler. This is primarily useful
    for tests and protocol adapters.

    For servers created with {!create_router}, [handle] invokes the router
    handler with the already-built [request]; it does not perform route-level
    body-mode selection because the body has already been constructed. Servers
    created with {!create_with_request_body_selector} likewise do not run the
    selector from [handle]. *)

val run :
  sw:Eio.Switch.t ->
  net:'a Eio.Net.t ->
  ?mono_clock:'b Eio.Time.Mono.t ->
  addr:Eio.Net.Sockaddr.stream ->
  t ->
  unit
(** [run ~sw ~net ~addr server] accepts HTTP connections on [addr] using Eio.

    The caller owns [sw]. Choku attaches listener resources and connection
    fibers to that switch, but does not close it. Each accepted HTTP/1.1
    connection may process multiple sequential requests when keep-alive is
    enabled. The call runs until [sw] is cancelled or the listening socket
    fails.

    [mono_clock] is required when [server] was created with
    [request_head_timeout = Some _].

    @raise Invalid_argument
      if request-head timeout is enabled and [mono_clock] is omitted. *)

val run_listener :
  sw:Eio.Switch.t ->
  ?mono_clock:'b Eio.Time.Mono.t ->
  socket:'a Eio.Net.listening_socket ->
  t ->
  unit
(** [run_listener ~sw ~socket server] accepts HTTP connections from an existing
    Eio listening socket.

    This is useful for test harnesses and embedders that need to bind a socket,
    inspect its actual address with [Eio.Net.listening_addr], and then start
    serving without a port-selection race. The caller owns both [sw] and
    [socket]. Choku attaches connection fibers to the server loop and runs until
    [sw] is cancelled or the listening socket fails.

    [mono_clock] is required when [server] was created with
    [request_head_timeout = Some _].

    @raise Invalid_argument
      if request-head timeout is enabled and [mono_clock] is omitted. *)
