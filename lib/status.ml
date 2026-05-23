type t = { code : int; reason : string }

let code t = t.code
let reason t = t.reason

let reason_for_code = function
  | 200 -> "OK"
  | 400 -> "Bad Request"
  | 404 -> "Not Found"
  | 413 -> "Payload Too Large"
  | 500 -> "Internal Server Error"
  | _ -> ""

let of_code code =
  if code < 100 || code > 599 then invalid_arg "invalid HTTP status code";
  { code; reason = reason_for_code code }

let ok = of_code 200
let bad_request = of_code 400
let not_found = of_code 404
let payload_too_large = of_code 413
let internal_server_error = of_code 500
