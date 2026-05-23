(** Request handler contract. *)

type t = Request.t -> Response.t
(** A request handler runs inside the Eio fiber serving one HTTP request.

    The handler receives a request value and returns a response description. It
    may perform Eio operations directly using capabilities captured by closure.
    It must not depend on Lwt, Async, or another scheduler. *)
