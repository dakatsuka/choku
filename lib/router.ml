module Params = struct
  type t = (string * string) list

  let empty = []

  let get name t =
    List.find_map
      (fun (param_name, value) ->
        if String.equal name param_name then Some value else None)
      t

  let to_list t = t
end

type segment = Static of string | Param of string
type pattern = Root | Segments of segment list
type route_handler = Params.t -> Request.t -> Response.t
type body_mode = Request_body_mode.t

type route_entry = {
  meth : Method.t;
  source : string;
  pattern : pattern;
  request_body_mode : body_mode;
  handler : route_handler;
}

type t = { routes : route_entry list; not_found : Handler.t }

let invalid_pattern () = invalid_arg "invalid route pattern"

let default_not_found _request =
  Response.text ~status:Status.not_found "Not Found\n"

let empty = { routes = []; not_found = default_not_found }
let not_found handler router = { router with not_found = handler }
let is_ascii_letter = function 'A' .. 'Z' | 'a' .. 'z' -> true | _ -> false
let is_name_start = function '_' -> true | c -> is_ascii_letter c

let is_name_char = function
  | '_' | '-' | '0' .. '9' -> true
  | c -> is_ascii_letter c

let valid_param_name name =
  String.length name > 0
  && is_name_start name.[0]
  && String.for_all is_name_char name

let parse_segment seen_params segment =
  if String.equal segment "" then invalid_pattern ();
  if Char.equal segment.[0] ':' then (
    let name = String.sub segment 1 (String.length segment - 1) in
    if (not (valid_param_name name)) || List.mem name seen_params then
      invalid_pattern ();
    (name :: seen_params, Param name))
  else (seen_params, Static segment)

let compile_pattern pattern =
  if String.equal pattern "" then invalid_pattern ();
  if not (Char.equal pattern.[0] '/') then invalid_pattern ();
  if String.equal pattern "/" then Root
  else
    let body = String.sub pattern 1 (String.length pattern - 1) in
    let _, segments =
      List.fold_left
        (fun (seen_params, segments) segment ->
          let seen_params, compiled_segment =
            parse_segment seen_params segment
          in
          (seen_params, compiled_segment :: segments))
        ([], [])
        (String.split_on_char '/' body)
    in
    Segments (List.rev segments)

let route ?(request_body_mode = Request_body_mode.Buffered) meth source handler
    router =
  let pattern = compile_pattern source in
  let entry = { meth; source; pattern; request_body_mode; handler } in
  { router with routes = router.routes @ [ entry ] }

let get ?request_body_mode pattern handler router =
  route ?request_body_mode Method.GET pattern handler router

let post ?request_body_mode pattern handler router =
  route ?request_body_mode Method.POST pattern handler router

let put ?request_body_mode pattern handler router =
  route ?request_body_mode Method.PUT pattern handler router

let patch ?request_body_mode pattern handler router =
  route ?request_body_mode Method.PATCH pattern handler router

let delete ?request_body_mode pattern handler router =
  route ?request_body_mode Method.DELETE pattern handler router

let options ?request_body_mode pattern handler router =
  route ?request_body_mode Method.OPTIONS pattern handler router

let path_segments path =
  if String.equal path "/" then Some []
  else if String.length path > 0 && Char.equal path.[0] '/' then
    Some (String.split_on_char '/' (String.sub path 1 (String.length path - 1)))
  else None

let rec match_segments pattern_segments path_segments params =
  match (pattern_segments, path_segments) with
  | [], [] -> Some (List.rev params)
  | Static expected :: pattern_segments, actual :: path_segments
    when String.equal expected actual ->
      match_segments pattern_segments path_segments params
  | Param name :: pattern_segments, actual :: path_segments
    when not (String.equal actual "") ->
      match_segments pattern_segments path_segments ((name, actual) :: params)
  | _ -> None

let match_pattern pattern path =
  match (pattern, path_segments path) with
  | Root, Some [] -> Some Params.empty
  | Segments pattern_segments, Some path_segments ->
      match_segments pattern_segments path_segments []
  | _ -> None

let path_of_target target =
  match String.index_opt target '?' with
  | None -> target
  | Some index -> String.sub target 0 index

let match_entry ~meth ~path route =
  let (_ : string) = route.source in
  if Method.equal route.meth meth then
    match match_pattern route.pattern path with
    | Some params -> Some (route, params)
    | None -> None
  else None

let to_handler router request =
  match
    List.find_map
      (match_entry ~meth:(Request.meth request) ~path:(Request.path request))
      router.routes
  with
  | Some (route, params) -> route.handler params request
  | None -> router.not_found request

module Internal = struct
  type matched_route = { request_body_mode : Request_body_mode.t }

  let match_route ~meth ~target router =
    let path = path_of_target target in
    router.routes
    |> List.find_map (fun route ->
        match match_entry ~meth ~path route with
        | None -> None
        | Some (route, params) ->
            let (_ : Params.t) = params in
            Some { request_body_mode = route.request_body_mode })
end
