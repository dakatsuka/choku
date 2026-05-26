module Params = struct
  type t = (string * string) list

  let empty = []

  let get name t =
    List.find_map
      (fun (param_name, value) ->
        if String.equal name param_name then Some value else None)
      t

  let get_or ~default name t =
    match get name t with Some value -> value | None -> default

  let to_list t = t
end

module Context = struct
  type t = { params : Params.t; request : Request.t }

  let make ~params ~request = { params; request }
end

type segment = Static of string | Param of string
type pattern = Root | Segments of segment list
type route_handler = Context.t -> Response.t
type body_mode = Request_body_mode.t

type route_entry = {
  meth : Method.t;
  pattern : pattern;
  request_body_mode : body_mode;
  handler : route_handler;
}

type path_match = { route : route_entry; params : Params.t }
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

let route ?(request_body_mode = Request_body_mode.Buffered) meth pattern_text
    handler router =
  let pattern = compile_pattern pattern_text in
  let entry = { meth; pattern; request_body_mode; handler } in
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
    Some (Request_target.path_segments_of_path path)
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

let match_path ~path route =
  match match_pattern route.pattern path with
  | Some params -> Some { route; params }
  | None -> None

let path_matches ~path routes = List.filter_map (match_path ~path) routes

let find_method meth matches =
  List.find_map
    (fun { route; params } ->
      if Method.equal route.meth meth then Some (route, params) else None)
    matches

let select_route ~meth matches =
  match find_method meth matches with
  | Some _ as matched -> matched
  | None when Method.equal meth Method.HEAD -> find_method Method.GET matches
  | None -> None

let add_unique value values =
  if List.exists (String.equal value) values then values else values @ [ value ]

let add_allowed_method values meth =
  let values = add_unique (Method.to_string meth) values in
  if Method.equal meth Method.GET then add_unique "HEAD" values else values

let allow_header_value matches =
  matches
  |> List.fold_left
       (fun allowed { route; params = _ } ->
         add_allowed_method allowed route.meth)
       []
  |> String.concat ", "

let method_not_allowed matches =
  Response.text ~status:Status.method_not_allowed "Method Not Allowed\n"
  |> Response.with_header "allow" (allow_header_value matches)

let to_handler router request =
  let matches = path_matches ~path:(Request.path request) router.routes in
  match select_route ~meth:(Request.meth request) matches with
  | Some (route, params) -> route.handler (Context.make ~params ~request)
  | None ->
      if List.is_empty matches then router.not_found request
      else method_not_allowed matches

module Internal = struct
  type matched_route = { request_body_mode : Request_body_mode.t }

  let match_route ~meth ~target router =
    let path = path_of_target target in
    let matches = path_matches ~path router.routes in
    match select_route ~meth matches with
    | None -> None
    | Some (route, params) ->
        let (_ : Params.t) = params in
        Some { request_body_mode = route.request_body_mode }
end
