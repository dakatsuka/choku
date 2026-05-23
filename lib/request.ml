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

let validate_origin_form target =
  String.length target > 0
  && Char.equal target.[0] '/'
  && not
       (String.exists
          (function '\x00' .. '\x20' | '\x7f' -> true | _ -> false)
          target)

let make ~meth ~target ~headers ~body =
  if not (validate_origin_form target) then
    invalid_arg "invalid origin-form target";
  { meth; target; path = path_of_target target; headers; body }

let meth t = t.meth
let target t = t.target
let path t = t.path
let headers t = t.headers
let body t = t.body
