type t = string

let empty = ""
let string s = s
let to_string t = t
let is_buffered _ = true
let with_source t fn = fn (Eio.Flow.string_source t)

let copy_to_sink t sink =
  with_source t (fun source -> Eio.Flow.copy source sink)

let save_to_path ?append ~create path t = Eio.Path.save ?append ~create path t
