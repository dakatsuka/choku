open Alcotest

let test_known_status () =
  check int "code" 404 (Choku.Status.code Choku.Status.not_found);
  check string "reason" "Not Found" (Choku.Status.reason Choku.Status.not_found)

let test_standard_status_constants () =
  let cases =
    [
      (Choku.Status.continue_, 100, "Continue");
      (Choku.Status.created, 201, "Created");
      (Choku.Status.no_content, 204, "No Content");
      (Choku.Status.moved_permanently, 301, "Moved Permanently");
      (Choku.Status.temporary_redirect, 307, "Temporary Redirect");
      (Choku.Status.unauthorized, 401, "Unauthorized");
      (Choku.Status.forbidden, 403, "Forbidden");
      (Choku.Status.method_not_allowed, 405, "Method Not Allowed");
      (Choku.Status.conflict, 409, "Conflict");
      (Choku.Status.uri_too_long, 414, "URI Too Long");
      (Choku.Status.too_many_requests, 429, "Too Many Requests");
      (Choku.Status.not_implemented, 501, "Not Implemented");
      (Choku.Status.bad_gateway, 502, "Bad Gateway");
      (Choku.Status.service_unavailable, 503, "Service Unavailable");
    ]
  in
  List.iter
    (fun (status, code, reason) ->
      check int "code" code (Choku.Status.code status);
      check string "reason" reason (Choku.Status.reason status))
    cases

let test_unknown_status () =
  let status = Choku.Status.of_code 599 in
  check int "code" 599 (Choku.Status.code status);
  check string "reason" "" (Choku.Status.reason status)

let test_status_class () =
  let status_class =
    testable
      (fun formatter -> function
        | Choku.Status.Informational ->
            Format.pp_print_string formatter "Informational"
        | Choku.Status.Successful ->
            Format.pp_print_string formatter "Successful"
        | Choku.Status.Redirection ->
            Format.pp_print_string formatter "Redirection"
        | Choku.Status.Client_error ->
            Format.pp_print_string formatter "Client_error"
        | Choku.Status.Server_error ->
            Format.pp_print_string formatter "Server_error")
      ( = )
  in
  let cases =
    [
      (Choku.Status.of_code 100, Choku.Status.Informational);
      (Choku.Status.of_code 199, Choku.Status.Informational);
      (Choku.Status.ok, Choku.Status.Successful);
      (Choku.Status.of_code 299, Choku.Status.Successful);
      (Choku.Status.moved_permanently, Choku.Status.Redirection);
      (Choku.Status.of_code 399, Choku.Status.Redirection);
      (Choku.Status.bad_request, Choku.Status.Client_error);
      (Choku.Status.of_code 499, Choku.Status.Client_error);
      (Choku.Status.internal_server_error, Choku.Status.Server_error);
      (Choku.Status.of_code 599, Choku.Status.Server_error);
    ]
  in
  List.iter
    (fun (status, expected) ->
      check status_class "class" expected (Choku.Status.class_ status))
    cases

let test_invalid_status () =
  check_raises "invalid low" (Invalid_argument "invalid HTTP status code")
    (fun () -> ignore (Choku.Status.of_code 99 : Choku.Status.t))

let () =
  run "status"
    [
      ( "status",
        [
          test_case "known status" `Quick test_known_status;
          test_case "standard status constants" `Quick
            test_standard_status_constants;
          test_case "unknown valid status" `Quick test_unknown_status;
          test_case "status class" `Quick test_status_class;
          test_case "invalid status" `Quick test_invalid_status;
        ] );
    ]
