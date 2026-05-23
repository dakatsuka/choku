(** Minimal Eio HTTP server. *)

type t

(** Request body delivery mode.

    [Buffered] reads the full request body before invoking the handler and keeps
    it replayable. [Streaming] invokes the handler with a single-consumption
    body source capped to the request's declared [Content-Length]. *)
type request_body_mode = Request_body_mode.t = Buffered | Streaming

val create :
  ?max_request_body_size:int ->
  ?max_request_head_size:int ->
  ?request_head_timeout:float option ->
  ?request_body_mode:request_body_mode ->
  ?middlewares:Middleware.t list ->
  handler:Handler.t ->
  unit ->
  t
(** [create ?max_request_body_size ?max_request_head_size ?request_head_timeout
     ?request_body_mode ?middlewares ~handler ()] creates a server.

    [max_request_body_size] defaults to [1_048_576] bytes.
    [max_request_head_size] defaults to [65_536] bytes. [request_head_timeout]
    defaults to [None]. [middlewares] are applied with [Middleware.apply]
    exactly once. [request_body_mode] defaults to [Buffered]. *)

val create_router :
  ?max_request_body_size:int ->
  ?max_request_head_size:int ->
  ?request_head_timeout:float option ->
  ?middlewares:Middleware.t list ->
  Router.t ->
  t
(** [create_router ?max_request_body_size ?max_request_head_size
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
    body-mode selection because the body has already been constructed. *)

val run :
  sw:Eio.Switch.t ->
  net:'a Eio.Net.t ->
  ?mono_clock:'b Eio.Time.Mono.t ->
  addr:Eio.Net.Sockaddr.stream ->
  t ->
  unit
(** [run ~sw ~net ~addr server] accepts HTTP connections on [addr] using Eio.

    The caller owns [sw]. Camelio attaches listener resources and connection
    fibers to that switch, but does not close it. The call runs until [sw] is
    cancelled or the listening socket fails.

    [mono_clock] is required when [server] was created with
    [request_head_timeout = Some _].

    @raise Invalid_argument
      if request-head timeout is enabled and [mono_clock] is omitted. *)
