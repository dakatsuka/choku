type t = (string * string) list

type error =
  | Missing_content_type
  | Unsupported_content_type of string
  | Malformed_percent_encoding

let empty = []

let get name t =
  List.find_map
    (fun (field_name, value) ->
      if String.equal name field_name then Some value else None)
    t

let get_all name t =
  List.filter_map
    (fun (field_name, value) ->
      if String.equal name field_name then Some value else None)
    t

let to_list t = t

let decode body =
  match Url_encoded.decode body with
  | Ok fields -> Ok fields
  | Error Url_encoded.Malformed_percent_encoding ->
      Error Malformed_percent_encoding

let trim_ascii s =
  let length = String.length s in
  let is_space = function ' ' | '\t' -> true | _ -> false in
  let rec first index =
    if index >= length then length
    else if is_space s.[index] then first (index + 1)
    else index
  in
  let rec last index =
    if index < 0 then -1
    else if is_space s.[index] then last (index - 1)
    else index
  in
  let first = first 0 in
  let last = last (length - 1) in
  if last < first then "" else String.sub s first (last - first + 1)

let media_type content_type =
  let media_type =
    match String.index_opt content_type ';' with
    | None -> content_type
    | Some index -> String.sub content_type 0 index
  in
  media_type |> trim_ascii |> String.lowercase_ascii

let of_request request =
  match Headers.get "content-type" (Request.headers request) with
  | None -> Error Missing_content_type
  | Some content_type ->
      if
        String.equal (media_type content_type)
          "application/x-www-form-urlencoded"
      then decode (Body.to_string (Request.body request))
      else Error (Unsupported_content_type content_type)

let pp_error formatter = function
  | Missing_content_type ->
      Format.pp_print_string formatter "missing content-type"
  | Unsupported_content_type content_type ->
      Format.fprintf formatter "unsupported content-type: %s" content_type
  | Malformed_percent_encoding ->
      Format.pp_print_string formatter "malformed percent encoding"
