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

  val to_list : t -> (string * string) list
  (** [to_list t] returns captured parameters in route-pattern order. *)
end

type route_handler = Params.t -> Request.t -> Response.t
(** A route handler receives route parameters and the original request. *)

val empty : t
(** [empty] is a router with no routes and the default 404 not-found handler. *)

val not_found : Handler.t -> t -> t
(** [not_found handler router] returns [router] with [handler] used when no
    route matches. *)

val route : Method.t -> string -> route_handler -> t -> t
(** [route meth pattern handler router] appends a route for [meth] and
    [pattern].

    Patterns are ["/"] or slash-prefixed non-empty segments. Segments beginning
    with [':'] capture one non-empty path segment using a parameter name made of
    ASCII letters, digits, [_], and [-], with an ASCII letter or [_] first.

    @raise Invalid_argument if [pattern] is invalid. *)

val get : string -> route_handler -> t -> t
(** [get pattern handler router] appends a [GET] route. *)

val post : string -> route_handler -> t -> t
(** [post pattern handler router] appends a [POST] route. *)

val put : string -> route_handler -> t -> t
(** [put pattern handler router] appends a [PUT] route. *)

val patch : string -> route_handler -> t -> t
(** [patch pattern handler router] appends a [PATCH] route. *)

val delete : string -> route_handler -> t -> t
(** [delete pattern handler router] appends a [DELETE] route. *)

val options : string -> route_handler -> t -> t
(** [options pattern handler router] appends an [OPTIONS] route. *)

val to_handler : t -> Handler.t
(** [to_handler router] returns a handler that checks routes in insertion order
    and invokes the router's not-found handler when no route matches. *)
