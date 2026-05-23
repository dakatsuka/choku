type t = (string * string) list

let empty = []
let lower_ascii s = String.lowercase_ascii s
let same_name a b = String.equal (lower_ascii a) (lower_ascii b)

let is_token_char = function
  | '!' | '#' | '$' | '%' | '&' | '\'' | '*' | '+' | '-' | '.' | '^' | '_' | '`'
  | '|' | '~' ->
      true
  | '0' .. '9' | 'A' .. 'Z' | 'a' .. 'z' -> true
  | _ -> false

let is_valid_name name =
  String.length name > 0 && String.for_all is_token_char name

let is_valid_value value =
  not (String.exists (function '\r' | '\n' -> true | _ -> false) value)

let validate name value =
  if not (is_valid_name name) then invalid_arg "invalid HTTP header name";
  if not (is_valid_value value) then invalid_arg "invalid HTTP header value"

let add name value headers =
  validate name value;
  headers @ [ (name, value) ]

let set name value headers =
  validate name value;
  headers |> List.filter (fun (existing, _) -> not (same_name existing name))
  |> fun headers -> headers @ [ (name, value) ]

let get name headers =
  headers
  |> List.find_opt (fun (existing, _) -> same_name existing name)
  |> Option.map snd

let get_all name headers =
  headers
  |> List.filter_map (fun (existing, value) ->
      if same_name existing name then Some value else None)

let to_list headers = headers
