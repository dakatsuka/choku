type t = Handler.t -> Handler.t

let identity : t = fun handler -> handler
let compose (a : t) (b : t) : t = fun handler -> a (b handler)

let apply (middlewares : t list) (handler : Handler.t) : Handler.t =
  List.fold_right
    (fun middleware wrapped -> middleware wrapped)
    middlewares handler
