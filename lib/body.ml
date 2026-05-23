type t = string

let empty = ""
let string s = s
let to_string t = t
let is_buffered _ = true
let with_source t fn = fn (Eio.Flow.string_source t)
