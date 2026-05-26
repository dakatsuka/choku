let is_valid_origin_form target =
  String.length target > 0
  && Char.equal target.[0] '/'
  && not
       (String.exists
          (function '\x00' .. '\x20' | '\x7f' | '#' -> true | _ -> false)
          target)

let path_of_origin_form target =
  match String.index_opt target '?' with
  | None -> target
  | Some index -> String.sub target 0 index

let query_string_of_origin_form target =
  match String.index_opt target '?' with
  | None -> None
  | Some index ->
      Some (String.sub target (index + 1) (String.length target - index - 1))

let path_segments_of_path path =
  if String.equal path "/" then []
  else String.split_on_char '/' (String.sub path 1 (String.length path - 1))
