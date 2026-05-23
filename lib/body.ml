type t = string
type error = Body_too_large

let empty = ""
let string s = s
let to_string t = t

let to_string_limited ~max_size t =
  if max_size < 0 then invalid_arg "negative max_size";
  if String.length t > max_size then Error Body_too_large else Ok t

let is_buffered _ = true
let with_source t fn = fn (Eio.Flow.string_source t)

let copy_to_sink t sink =
  with_source t (fun source -> Eio.Flow.copy source sink)

let save_to_path ?append ~create path t = Eio.Path.save ?append ~create path t

let pp_error formatter = function
  | Body_too_large -> Format.pp_print_string formatter "body too large"
