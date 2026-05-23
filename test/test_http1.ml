open Alcotest

let parse_ok raw =
  match Camelio.Http1.parse_request_string raw with
  | Ok request -> request
  | Error error ->
      failf "unexpected parse error: %s" (Camelio.Http1.error_to_string error)

let parse_error raw =
  match Camelio.Http1.parse_request_string raw with
  | Ok _ -> fail "expected parse error"
  | Error error -> error

let test_parse_get () =
  let request =
    parse_ok "GET /hello?x=1 HTTP/1.1\r\nHost: example.test\r\n\r\n"
  in
  check
    (module Camelio.Method)
    "method" Camelio.Method.GET
    (Camelio.Request.meth request);
  check string "path" "/hello" (Camelio.Request.path request);
  check (option string) "host" (Some "example.test")
    (Camelio.Headers.get "host" (Camelio.Request.headers request))

let test_parse_content_length_body () =
  let request =
    parse_ok "POST /echo HTTP/1.1\r\nContent-Length: 5\r\n\r\nhello"
  in
  check string "body" "hello"
    (Camelio.Body.to_string (Camelio.Request.body request))

let test_reject_chunked () =
  check
    (module Camelio.Http1.Error)
    "error" Camelio.Http1.Unsupported_transfer_encoding
    (parse_error "POST / HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n")

let test_reject_invalid_content_length () =
  let cases =
    [
      "POST / HTTP/1.1\r\nContent-Length: +5\r\n\r\nhello";
      "POST / HTTP/1.1\r\nContent-Length: 1_0\r\n\r\nhello";
      "POST / HTTP/1.1\r\nContent-Length: 0x10\r\n\r\nhello";
      "POST / HTTP/1.1\r\nContent-Length: 5\r\nContent-Length: 6\r\n\r\nhello!";
      "POST / HTTP/1.1\r\nContent-Length: 5\r\nContent-Length: bad\r\n\r\nhello";
    ]
  in
  List.iter
    (fun raw ->
      check
        (module Camelio.Http1.Error)
        "error" Camelio.Http1.Invalid_content_length (parse_error raw))
    cases

let test_allow_identical_content_length () =
  let request =
    parse_ok
      "POST / HTTP/1.1\r\nContent-Length: 5\r\nContent-Length: 5\r\n\r\nhello"
  in
  check string "body" "hello"
    (Camelio.Body.to_string (Camelio.Request.body request))

let test_reject_malformed_header_names () =
  let cases =
    [
      "GET / HTTP/1.1\r\nBad Name: x\r\n\r\n";
      "GET / HTTP/1.1\r\n\tBad: x\r\n\r\n";
      "GET / HTTP/1.1\r\nBad\001Name: x\r\n\r\n";
    ]
  in
  List.iter
    (fun raw ->
      check
        (module Camelio.Http1.Error)
        "error" Camelio.Http1.Malformed_header (parse_error raw))
    cases

let test_reject_over_limit_body () =
  check
    (module Camelio.Http1.Error)
    "error" Camelio.Http1.Body_too_large
    (match
       Camelio.Http1.parse_request_string ~max_request_body_size:4
         "POST / HTTP/1.1\r\nContent-Length: 5\r\n\r\nhello"
     with
    | Ok _ -> fail "expected parse error"
    | Error error -> error)

let test_serialize_response () =
  let response =
    Camelio.Response.text ~status:Camelio.Status.not_found "missing\n"
  in
  check string "wire"
    "HTTP/1.1 404 Not Found\r\n\
     content-type: text/plain; charset=utf-8\r\n\
     content-length: 8\r\n\
     connection: close\r\n\
     \r\n\
     missing\n"
    (Camelio.Http1.serialize_response response)

let () =
  run "http1"
    [
      ( "http1",
        [
          test_case "parse GET" `Quick test_parse_get;
          test_case "parse Content-Length body" `Quick
            test_parse_content_length_body;
          test_case "reject chunked" `Quick test_reject_chunked;
          test_case "reject invalid Content-Length" `Quick
            test_reject_invalid_content_length;
          test_case "allow identical Content-Length" `Quick
            test_allow_identical_content_length;
          test_case "reject malformed header names" `Quick
            test_reject_malformed_header_names;
          test_case "reject over limit body" `Quick test_reject_over_limit_body;
          test_case "serialize response" `Quick test_serialize_response;
        ] );
    ]
