open Alcotest

let test_known_status () =
  check int "code" 404 (Camelio.Status.code Camelio.Status.not_found);
  check string "reason" "Not Found"
    (Camelio.Status.reason Camelio.Status.not_found)

let test_unknown_status () =
  let status = Camelio.Status.of_code 599 in
  check int "code" 599 (Camelio.Status.code status);
  check string "reason" "" (Camelio.Status.reason status)

let test_invalid_status () =
  check_raises "invalid low" (Invalid_argument "invalid HTTP status code")
    (fun () -> ignore (Camelio.Status.of_code 99 : Camelio.Status.t))

let () =
  run "status"
    [
      ( "status",
        [
          test_case "known status" `Quick test_known_status;
          test_case "unknown valid status" `Quick test_unknown_status;
          test_case "invalid status" `Quick test_invalid_status;
        ] );
    ]
