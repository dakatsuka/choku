type t = {
  meth : Method.t;
  target : string;
  path : string;
  headers : Headers.t;
  body : Body.t;
}

let path_of_target target =
  match String.index_opt target '?' with
  | None -> target
  | Some index -> String.sub target 0 index

let make ~meth ~target ~headers ~body =
  if not (Request_target.is_valid_origin_form target) then
    invalid_arg "invalid origin-form target";
  { meth; target; path = path_of_target target; headers; body }

let meth t = t.meth
let target t = t.target
let path t = t.path
let headers t = t.headers
let body t = t.body
