(** Minimal Eio HTTP server. *)

type t

(** Request body delivery mode.

    [Buffered] reads the full request body before invoking the handler and keeps
    it replayable. [Streaming] invokes the handler with a single-consumption
    body source capped to the request's declared [Content-Length]. *)
type request_body_mode = Buffered | Streaming

val create :
  ?max_request_body_size:int ->
  ?request_body_mode:request_body_mode ->
  ?middlewares:Middleware.t list ->
  handler:Handler.t ->
  unit ->
  t
(** [create ?max_request_body_size ?request_body_mode ?middlewares ~handler ()]
    creates a server.

    [max_request_body_size] defaults to [1_048_576] bytes. [middlewares] are
    applied with [Middleware.apply] exactly once. [request_body_mode] defaults
    to [Buffered]. *)

val max_request_body_size : t -> int
(** [max_request_body_size t] returns the configured body limit. *)

val handle : t -> Request.t -> Response.t
(** [handle t request] invokes the composed handler. This is primarily useful
    for tests and protocol adapters. *)

val run :
  sw:Eio.Switch.t ->
  net:'a Eio.Net.t ->
  addr:Eio.Net.Sockaddr.stream ->
  t ->
  unit
(** [run ~sw ~net ~addr server] accepts HTTP connections on [addr] using Eio.

    The caller owns [sw]. Camelio attaches listener resources and connection
    fibers to that switch, but does not close it. The call runs until [sw] is
    cancelled or the listening socket fails. *)
