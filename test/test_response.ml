open Alcotest

let test_text_response () =
  let response = Choku.Response.text "hello" in
  check int "status" 200 (Choku.Status.code (Choku.Response.status response));
  check string "body" "hello"
    (Choku.Body.to_string (Choku.Response.body response));
  check (option string) "content type" (Some "text/plain; charset=utf-8")
    (Choku.Headers.get "content-type" (Choku.Response.headers response))

let test_with_header_sets () =
  let response =
    Choku.Response.text "hello"
    |> Choku.Response.with_header "x-test" "one"
    |> Choku.Response.with_header "X-Test" "two"
  in
  check (list string) "single latest value" [ "two" ]
    (Choku.Headers.get_all "x-test" (Choku.Response.headers response))

let test_with_header_rejects_injection () =
  check_raises "bad name" (Invalid_argument "invalid HTTP header name")
    (fun () ->
      ignore
        (Choku.Response.text "hello"
         |> Choku.Response.with_header "Bad Name" "x"
          : Choku.Response.t));
  check_raises "newline value" (Invalid_argument "invalid HTTP header value")
    (fun () ->
      ignore
        (Choku.Response.text "hello"
         |> Choku.Response.with_header "x-test" "ok\r\nInjected: yes"
          : Choku.Response.t))

let test_stream_response () =
  let response =
    Choku.Response.stream ~content_length:5 (fun sink ->
        Eio.Flow.copy_string "hello" sink)
  in
  check int "status" 200 (Choku.Status.code (Choku.Response.status response));
  check bool "stream body" false
    (Choku.Body.is_buffered (Choku.Response.body response));
  check_raises "streaming body cannot be read"
    (Invalid_argument "streaming body cannot be read with Body.to_string")
    (fun () -> ignore (Choku.Body.to_string (Choku.Response.body response)))

let test_stream_rejects_negative_content_length () =
  check_raises "negative content length"
    (Invalid_argument "negative content_length") (fun () ->
      ignore
        (Choku.Response.stream ~content_length:(-1) (fun _ -> ())
          : Choku.Response.t))

let () =
  run "response"
    [
      ( "response",
        [
          test_case "text response" `Quick test_text_response;
          test_case "with_header uses set" `Quick test_with_header_sets;
          test_case "with_header rejects injection" `Quick
            test_with_header_rejects_injection;
          test_case "stream response" `Quick test_stream_response;
          test_case "stream rejects negative content length" `Quick
            test_stream_rejects_negative_content_length;
        ] );
    ]
