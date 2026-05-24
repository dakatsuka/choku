open Alcotest

let request target =
  Choku.Request.make ~meth:Choku.Method.GET ~target ~headers:Choku.Headers.empty
    ~body:Choku.Body.empty

let test_path_strips_query () =
  check string "path" "/items" (Choku.Request.path (request "/items?a=1"))

let test_root_path () =
  check string "path" "/" (Choku.Request.path (request "/"))

let test_path_can_be_split_for_direct_matching () =
  match
    Choku.Request.path (request "/users/42?tab=profile")
    |> String.split_on_char '/'
  with
  | [ ""; "users"; id ] -> check string "id" "42" id
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
          test_case "path can be split for direct matching" `Quick
            test_path_can_be_split_for_direct_matching;
          test_case "invalid target" `Quick test_invalid_target;
          test_case "space in target" `Quick test_reject_space_in_target;
          test_case "fragment in target" `Quick test_reject_fragment_in_target;
          test_case "control targets" `Quick test_reject_control_targets;
        ] );
    ]
