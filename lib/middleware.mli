(** Handler middleware. *)

type t = Handler.t -> Handler.t
(** Middleware transforms one handler into another handler.

    Middleware may inspect or replace the request before calling the wrapped
    handler, and may inspect or replace the response returned by it. It may also
    catch exceptions from the wrapped handler when implementing error handling
    policies. *)

val identity : t
(** [identity h] is [h]. *)

val compose : t -> t -> t
(** [compose a b h] is [a (b h)]. *)

val apply : t list -> Handler.t -> Handler.t
(** [apply [a; b; c] h] is [a (b (c h))]. *)
