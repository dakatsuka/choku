type t = Buffered | Streaming

let equal = ( = )

let pp formatter = function
  | Buffered -> Format.pp_print_string formatter "Buffered"
  | Streaming -> Format.pp_print_string formatter "Streaming"
