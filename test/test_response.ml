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

let () =
  run "response"
    [
      ( "response",
        [
          test_case "text response" `Quick test_text_response;
          test_case "with_header uses set" `Quick test_with_header_sets;
        ] );
    ]
