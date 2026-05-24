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

let () =
  run "response"
    [
      ( "response",
        [
          test_case "text response" `Quick test_text_response;
          test_case "with_header uses set" `Quick test_with_header_sets;
          test_case "with_header rejects injection" `Quick
            test_with_header_rejects_injection;
        ] );
    ]
