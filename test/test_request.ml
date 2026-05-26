open Alcotest

let request target =
  Choku.Request.make ~meth:Choku.Method.GET ~target ~headers:Choku.Headers.empty
    ~body:Choku.Body.empty

let test_path_strips_query () =
  check string "path" "/items" (Choku.Request.path (request "/items?a=1"))

let test_root_path () =
  check string "path" "/" (Choku.Request.path (request "/"))

let check_path_segments target expected =
  check (list string)
    ("path segments for " ^ target)
    expected
    (Choku.Request.path_segments (request target))

let test_path_segments () =
  check_path_segments "/" [];
  check_path_segments "/?q=1" [];
  check_path_segments "/users/42?tab=profile" [ "users"; "42" ];
  check_path_segments "/users/" [ "users"; "" ];
  check_path_segments "/users//42" [ "users"; ""; "42" ];
  check_path_segments "//users" [ ""; "users" ];
  check_path_segments "/%2F" [ "%2F" ];
  check_path_segments "/./../x" [ "."; ".."; "x" ]

let test_path_segments_support_direct_matching () =
  match Choku.Request.path_segments (request "/users/42?tab=profile") with
  | [ "users"; id ] -> check string "id" "42" id
  | segments ->
      fail
        (Printf.sprintf "unexpected path segments: [%s]"
           (String.concat "; " segments))

let test_invalid_target () =
  check_raises "invalid target" (Invalid_argument "invalid origin-form target")
    (fun () -> ignore (request "https://example.test/" : Choku.Request.t))

let test_reject_space_in_target () =
  check_raises "space in target" (Invalid_argument "invalid origin-form target")
    (fun () -> ignore (request "/bad path" : Choku.Request.t))

let test_reject_fragment_in_target () =
  check_raises "fragment in target"
    (Invalid_argument "invalid origin-form target") (fun () ->
      ignore (request "/bad#fragment" : Choku.Request.t))

let test_reject_control_targets () =
  List.iter
    (fun target ->
      check_raises ("invalid " ^ target)
        (Invalid_argument "invalid origin-form target") (fun () ->
          ignore (request target : Choku.Request.t)))
    [ "/bad\tpath"; "/bad\rpath"; "/bad\npath"; "" ]

let () =
  run "request"
    [
      ( "request",
        [
          test_case "path strips query" `Quick test_path_strips_query;
          test_case "root path" `Quick test_root_path;
          test_case "path segments" `Quick test_path_segments;
          test_case "path segments support direct matching" `Quick
            test_path_segments_support_direct_matching;
          test_case "invalid target" `Quick test_invalid_target;
          test_case "space in target" `Quick test_reject_space_in_target;
          test_case "fragment in target" `Quick test_reject_fragment_in_target;
          test_case "control targets" `Quick test_reject_control_targets;
        ] );
    ]
