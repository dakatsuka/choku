open Alcotest

let test_known_methods () =
  check
    (module Choku.Method)
    "GET" Choku.Method.GET
    (Choku.Method.of_string "GET");
  check string "to_string" "POST" (Choku.Method.to_string Choku.Method.POST)

let test_custom_method_preserves_case () =
  check
    (module Choku.Method)
    "custom" (Choku.Method.Other "Purge")
    (Choku.Method.of_string "Purge")

let test_invalid_method_token () =
  check_raises "space is invalid" (Invalid_argument "invalid HTTP method token")
    (fun () -> ignore (Choku.Method.of_string "BAD METHOD" : Choku.Method.t))

let () =
  run "method"
    [
      ( "method",
        [
          test_case "known methods" `Quick test_known_methods;
          test_case "custom method preserves case" `Quick
            test_custom_method_preserves_case;
          test_case "invalid method token" `Quick test_invalid_method_token;
        ] );
    ]
