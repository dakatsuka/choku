open Alcotest

let test_known_methods () =
  check
    (module Camelio.Method)
    "GET" Camelio.Method.GET
    (Camelio.Method.of_string "GET");
  check string "to_string" "POST" (Camelio.Method.to_string Camelio.Method.POST)

let test_custom_method_preserves_case () =
  check
    (module Camelio.Method)
    "custom" (Camelio.Method.Other "Purge")
    (Camelio.Method.of_string "Purge")

let test_invalid_method_token () =
  check_raises "space is invalid" (Invalid_argument "invalid HTTP method token")
    (fun () ->
      ignore (Camelio.Method.of_string "BAD METHOD" : Camelio.Method.t))

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
