type t = {
  meth : Method.t;
  target : string;
  path : string;
  headers : Headers.t;
  body : Body.t;
}

let path_of_target target = Request_target.path_of_origin_form target

let make ~meth ~target ~headers ~body =
  if not (Request_target.is_valid_origin_form target) then
    invalid_arg "invalid origin-form target";
  { meth; target; path = path_of_target target; headers; body }

let meth t = t.meth
let target t = t.target
let path t = t.path
let path_segments t = Request_target.path_segments_of_path t.path
let headers t = t.headers
let body t = t.body
