(** Optional method-and-path router that compiles to {!Handler.t}. *)

type t
(** Immutable route collection. *)

module Params : sig
  type t
  (** Captured path parameters for a matched route. *)

  val empty : t
  (** [empty] contains no captured parameters. *)

  val get : string -> t -> string option
  (** [get name t] returns the first captured value for [name], if present. *)

  val get_or : default:string -> string -> t -> string
  (** [get_or ~default name t] returns the first captured value for [name], or
      [default] if [name] is absent. *)

  val to_list : t -> (string * string) list
  (** [to_list t] returns captured parameters in route-pattern order. *)
end

module Context : sig
  type t = private { params : Params.t; request : Request.t }
  (** Context for a matched route.

      [params] contains the captured route parameters. [request] is the original
      request passed to the router. Context values are constructed by the router
      during dispatch. *)
end

type route_handler = Context.t -> Response.t
(** A route handler receives context for the matched route. *)

type body_mode = Request_body_mode.t
(** Request body delivery mode for a route. *)

val empty : t
(** [empty] is a router with no routes and the default 404 not-found handler. *)

val not_found : Handler.t -> t -> t
(** [not_found handler router] returns [router] with [handler] used when no
    route path matches.

    Path matches for disallowed methods use Choku's automatic
    [405 Method Not Allowed] response instead. *)

val route :
  ?request_body_mode:body_mode -> Method.t -> string -> route_handler -> t -> t
(** [route ?request_body_mode meth pattern handler router] appends a route for
    [meth] and [pattern].

    Patterns are ["/"] or slash-prefixed non-empty segments. Segments beginning
    with [':'] capture one non-empty path segment using a parameter name made of
    ASCII letters, digits, [_], and [-], with an ASCII letter or [_] first.

    [request_body_mode] defaults to [Request_body_mode.Buffered].

    @raise Invalid_argument if [pattern] is invalid. *)

val get : ?request_body_mode:body_mode -> string -> route_handler -> t -> t
(** [get pattern handler router] appends a [GET] route. *)

val post : ?request_body_mode:body_mode -> string -> route_handler -> t -> t
(** [post pattern handler router] appends a [POST] route. *)

val put : ?request_body_mode:body_mode -> string -> route_handler -> t -> t
(** [put pattern handler router] appends a [PUT] route. *)

val patch : ?request_body_mode:body_mode -> string -> route_handler -> t -> t
(** [patch pattern handler router] appends a [PATCH] route. *)

val delete : ?request_body_mode:body_mode -> string -> route_handler -> t -> t
(** [delete pattern handler router] appends a [DELETE] route. *)

val options : ?request_body_mode:body_mode -> string -> route_handler -> t -> t
(** [options pattern handler router] appends an [OPTIONS] route. *)

val to_handler : t -> Handler.t
(** [to_handler router] returns a handler that checks routes in insertion order
    and invokes the router's not-found handler when no route path matches.

    [HEAD] requests first match explicit [HEAD] routes, then fall back to
    matching [GET] routes. Requests whose path matches at least one route but
    whose method is not allowed receive [405 Method Not Allowed] with an [Allow]
    header. *)

(**/**)

module Internal : sig
  type matched_route = { request_body_mode : Request_body_mode.t }
  (** Pre-body route match result used by server integration. *)

  val match_route : meth:Method.t -> target:string -> t -> matched_route option
  [@@alert internal "Choku internal API; do not use outside the library."]
  (** [match_route ~meth ~target router] returns the first route matching [meth]
      and the query-stripped [target], if any. [HEAD] requests fall back to a
      matching [GET] route when no explicit [HEAD] route matches. *)
end

(**/**)
