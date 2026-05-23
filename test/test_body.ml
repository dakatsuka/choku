open Alcotest

let test_body_values () =
  check string "empty" "" (Camelio.Body.to_string Camelio.Body.empty);
  check string "string" "hello"
    (Camelio.Body.to_string (Camelio.Body.string "hello"))

let () =
  run "body" [ ("body", [ test_case "body values" `Quick test_body_values ]) ]
