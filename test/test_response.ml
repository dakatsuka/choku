open Alcotest

let test_text_response () =
  let response = Camelio.Response.text "hello" in
  check int "status" 200
    (Camelio.Status.code (Camelio.Response.status response));
  check string "body" "hello"
    (Camelio.Body.to_string (Camelio.Response.body response));
  check (option string) "content type" (Some "text/plain; charset=utf-8")
    (Camelio.Headers.get "content-type" (Camelio.Response.headers response))

let test_with_header_sets () =
  let response =
    Camelio.Response.text "hello"
    |> Camelio.Response.with_header "x-test" "one"
    |> Camelio.Response.with_header "X-Test" "two"
  in
  check (list string) "single latest value" [ "two" ]
    (Camelio.Headers.get_all "x-test" (Camelio.Response.headers response))

let test_with_header_rejects_injection () =
  check_raises "bad name" (Invalid_argument "invalid HTTP header name")
    (fun () ->
      ignore
        (Camelio.Response.text "hello"
         |> Camelio.Response.with_header "Bad Name" "x"
          : Camelio.Response.t));
  check_raises "newline value" (Invalid_argument "invalid HTTP header value")
    (fun () ->
      ignore
        (Camelio.Response.text "hello"
         |> Camelio.Response.with_header "x-test" "ok\r\nInjected: yes"
          : Camelio.Response.t))

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
