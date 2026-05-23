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

let hex_value = function
  | '0' .. '9' as c -> Some (Char.code c - Char.code '0')
  | 'A' .. 'F' as c -> Some (Char.code c - Char.code 'A' + 10)
  | 'a' .. 'f' as c -> Some (Char.code c - Char.code 'a' + 10)
  | _ -> None

let decode_component component =
  let length = String.length component in
  let buffer = Buffer.create length in
  let rec loop index =
    if index >= length then Ok (Buffer.contents buffer)
    else
      match component.[index] with
      | '+' ->
          Buffer.add_char buffer ' ';
          loop (index + 1)
      | '%' -> (
          if index + 2 >= length then Error Malformed_percent_encoding
          else
            match
              (hex_value component.[index + 1], hex_value component.[index + 2])
            with
            | Some high, Some low ->
                Buffer.add_char buffer (Char.chr ((high * 16) + low));
                loop (index + 3)
            | _ -> Error Malformed_percent_encoding)
      | c ->
          Buffer.add_char buffer c;
          loop (index + 1)
  in
  loop 0

let split_field field =
  match String.index_opt field '=' with
  | None -> (field, "")
  | Some index ->
      let name = String.sub field 0 index in
      let value =
        String.sub field (index + 1) (String.length field - index - 1)
      in
      (name, value)

let decode_field field =
  let name, value = split_field field in
  match decode_component name with
  | Error error -> Error error
  | Ok name -> (
      match decode_component value with
      | Error error -> Error error
      | Ok value -> Ok (name, value))

let decode body =
  if String.equal body "" then Ok empty
  else
    body |> String.split_on_char '&'
    |> List.fold_left
         (fun result field ->
           match result with
           | Error _ as error -> error
           | Ok fields -> (
               match decode_field field with
               | Ok field -> Ok (field :: fields)
               | Error _ as error -> error))
         (Ok [])
    |> Result.map List.rev

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
