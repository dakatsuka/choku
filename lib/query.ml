type t = (string * string) list
type error = Malformed_percent_encoding

let empty = []

let get name t =
  List.find_map
    (fun (param_name, value) ->
      if String.equal name param_name then Some value else None)
    t

let get_all name t =
  List.filter_map
    (fun (param_name, value) ->
      if String.equal name param_name then Some value else None)
    t

let to_list t = t

let decode raw_query =
  match Url_encoded.decode raw_query with
  | Ok params -> Ok params
  | Error Url_encoded.Malformed_percent_encoding ->
      Error Malformed_percent_encoding

let of_request request =
  match Request.query_string request with
  | None -> Ok empty
  | Some raw_query -> decode raw_query

let pp_error formatter = function
  | Malformed_percent_encoding ->
      Format.pp_print_string formatter "malformed percent encoding"
