open Alcotest

let test_known_status () =
  check int "code" 404 (Camelio.Status.code Camelio.Status.not_found);
  check string "reason" "Not Found"
    (Camelio.Status.reason Camelio.Status.not_found)

let test_standard_status_constants () =
  let cases =
    [
      (Camelio.Status.continue_, 100, "Continue");
      (Camelio.Status.created, 201, "Created");
      (Camelio.Status.no_content, 204, "No Content");
      (Camelio.Status.moved_permanently, 301, "Moved Permanently");
      (Camelio.Status.temporary_redirect, 307, "Temporary Redirect");
      (Camelio.Status.unauthorized, 401, "Unauthorized");
      (Camelio.Status.forbidden, 403, "Forbidden");
      (Camelio.Status.method_not_allowed, 405, "Method Not Allowed");
      (Camelio.Status.conflict, 409, "Conflict");
      (Camelio.Status.uri_too_long, 414, "URI Too Long");
      (Camelio.Status.too_many_requests, 429, "Too Many Requests");
      (Camelio.Status.not_implemented, 501, "Not Implemented");
      (Camelio.Status.bad_gateway, 502, "Bad Gateway");
      (Camelio.Status.service_unavailable, 503, "Service Unavailable");
    ]
  in
  List.iter
    (fun (status, code, reason) ->
      check int "code" code (Camelio.Status.code status);
      check string "reason" reason (Camelio.Status.reason status))
    cases

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
          test_case "standard status constants" `Quick
            test_standard_status_constants;
          test_case "unknown valid status" `Quick test_unknown_status;
          test_case "invalid status" `Quick test_invalid_status;
        ] );
    ]
