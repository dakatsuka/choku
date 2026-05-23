type t = GET | HEAD | POST | PUT | PATCH | DELETE | OPTIONS | Other of string

let equal = ( = )

let to_string = function
  | GET -> "GET"
  | HEAD -> "HEAD"
  | POST -> "POST"
  | PUT -> "PUT"
  | PATCH -> "PATCH"
  | DELETE -> "DELETE"
  | OPTIONS -> "OPTIONS"
  | Other token -> token

let is_token_char = function
  | '!' | '#' | '$' | '%' | '&' | '\'' | '*' | '+' | '-' | '.' | '^' | '_' | '`'
  | '|' | '~' ->
      true
  | '0' .. '9' | 'A' .. 'Z' | 'a' .. 'z' -> true
  | _ -> false

let is_valid_token token =
  String.length token > 0 && String.for_all is_token_char token

let of_string = function
  | "GET" -> GET
  | "HEAD" -> HEAD
  | "POST" -> POST
  | "PUT" -> PUT
  | "PATCH" -> PATCH
  | "DELETE" -> DELETE
  | "OPTIONS" -> OPTIONS
  | token when is_valid_token token -> Other token
  | _ -> invalid_arg "invalid HTTP method token"

let pp fmt t = Format.pp_print_string fmt (to_string t)
