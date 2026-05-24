type t = {
  meth : Method.t;
  target : string;
  path : string;
  headers : Headers.t;
}

let make ~meth ~target ~headers =
  if not (Request_target.is_valid_origin_form target) then
    invalid_arg "invalid origin-form target";
  { meth; target; path = Request_target.path_of_origin_form target; headers }

let meth t = t.meth
let target t = t.target
let path t = t.path
let headers t = t.headers
