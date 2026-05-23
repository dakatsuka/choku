open Alcotest

let request target =
  Camelio.Request.make ~meth:Camelio.Method.GET ~target
    ~headers:Camelio.Headers.empty ~body:Camelio.Body.empty

let test_path_strips_query () =
  check string "path" "/items" (Camelio.Request.path (request "/items?a=1"))

let test_root_path () =
  check string "path" "/" (Camelio.Request.path (request "/"))

let test_invalid_target () =
  check_raises "invalid target" (Invalid_argument "invalid origin-form target")
    (fun () -> ignore (request "https://example.test/" : Camelio.Request.t))

let test_reject_space_in_target () =
  check_raises "space in target" (Invalid_argument "invalid origin-form target")
    (fun () -> ignore (request "/bad path" : Camelio.Request.t))

let () =
  run "request"
    [
      ( "request",
        [
          test_case "path strips query" `Quick test_path_strips_query;
          test_case "root path" `Quick test_root_path;
          test_case "invalid target" `Quick test_invalid_target;
          test_case "space in target" `Quick test_reject_space_in_target;
        ] );
    ]
