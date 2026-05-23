type t = { code : int; reason : string }

let code t = t.code
let reason t = t.reason

let reason_for_code = function
  | 100 -> "Continue"
  | 101 -> "Switching Protocols"
  | 102 -> "Processing"
  | 103 -> "Early Hints"
  | 200 -> "OK"
  | 201 -> "Created"
  | 202 -> "Accepted"
  | 203 -> "Non-Authoritative Information"
  | 204 -> "No Content"
  | 205 -> "Reset Content"
  | 206 -> "Partial Content"
  | 207 -> "Multi-Status"
  | 208 -> "Already Reported"
  | 226 -> "IM Used"
  | 300 -> "Multiple Choices"
  | 301 -> "Moved Permanently"
  | 302 -> "Found"
  | 303 -> "See Other"
  | 304 -> "Not Modified"
  | 305 -> "Use Proxy"
  | 307 -> "Temporary Redirect"
  | 308 -> "Permanent Redirect"
  | 400 -> "Bad Request"
  | 401 -> "Unauthorized"
  | 402 -> "Payment Required"
  | 403 -> "Forbidden"
  | 404 -> "Not Found"
  | 405 -> "Method Not Allowed"
  | 406 -> "Not Acceptable"
  | 407 -> "Proxy Authentication Required"
  | 408 -> "Request Timeout"
  | 409 -> "Conflict"
  | 410 -> "Gone"
  | 411 -> "Length Required"
  | 412 -> "Precondition Failed"
  | 413 -> "Payload Too Large"
  | 414 -> "URI Too Long"
  | 415 -> "Unsupported Media Type"
  | 416 -> "Range Not Satisfiable"
  | 417 -> "Expectation Failed"
  | 418 -> "I'm a teapot"
  | 421 -> "Misdirected Request"
  | 422 -> "Unprocessable Content"
  | 423 -> "Locked"
  | 424 -> "Failed Dependency"
  | 425 -> "Too Early"
  | 426 -> "Upgrade Required"
  | 428 -> "Precondition Required"
  | 429 -> "Too Many Requests"
  | 431 -> "Request Header Fields Too Large"
  | 451 -> "Unavailable For Legal Reasons"
  | 500 -> "Internal Server Error"
  | 501 -> "Not Implemented"
  | 502 -> "Bad Gateway"
  | 503 -> "Service Unavailable"
  | 504 -> "Gateway Timeout"
  | 505 -> "HTTP Version Not Supported"
  | 506 -> "Variant Also Negotiates"
  | 507 -> "Insufficient Storage"
  | 508 -> "Loop Detected"
  | 510 -> "Not Extended"
  | 511 -> "Network Authentication Required"
  | _ -> ""

let of_code code =
  if code < 100 || code > 599 then invalid_arg "invalid HTTP status code";
  { code; reason = reason_for_code code }

let continue_ = of_code 100
let switching_protocols = of_code 101
let processing = of_code 102
let early_hints = of_code 103
let ok = of_code 200
let created = of_code 201
let accepted = of_code 202
let non_authoritative_information = of_code 203
let no_content = of_code 204
let reset_content = of_code 205
let partial_content = of_code 206
let multi_status = of_code 207
let already_reported = of_code 208
let im_used = of_code 226
let multiple_choices = of_code 300
let moved_permanently = of_code 301
let found = of_code 302
let see_other = of_code 303
let not_modified = of_code 304
let use_proxy = of_code 305
let temporary_redirect = of_code 307
let permanent_redirect = of_code 308
let bad_request = of_code 400
let unauthorized = of_code 401
let payment_required = of_code 402
let forbidden = of_code 403
let not_found = of_code 404
let method_not_allowed = of_code 405
let not_acceptable = of_code 406
let proxy_authentication_required = of_code 407
let request_timeout = of_code 408
let conflict = of_code 409
let gone = of_code 410
let length_required = of_code 411
let precondition_failed = of_code 412
let payload_too_large = of_code 413
let uri_too_long = of_code 414
let unsupported_media_type = of_code 415
let range_not_satisfiable = of_code 416
let expectation_failed = of_code 417
let im_a_teapot = of_code 418
let misdirected_request = of_code 421
let unprocessable_content = of_code 422
let locked = of_code 423
let failed_dependency = of_code 424
let too_early = of_code 425
let upgrade_required = of_code 426
let precondition_required = of_code 428
let too_many_requests = of_code 429
let request_header_fields_too_large = of_code 431
let unavailable_for_legal_reasons = of_code 451
let internal_server_error = of_code 500
let not_implemented = of_code 501
let bad_gateway = of_code 502
let service_unavailable = of_code 503
let gateway_timeout = of_code 504
let http_version_not_supported = of_code 505
let variant_also_negotiates = of_code 506
let insufficient_storage = of_code 507
let loop_detected = of_code 508
let not_extended = of_code 510
let network_authentication_required = of_code 511
