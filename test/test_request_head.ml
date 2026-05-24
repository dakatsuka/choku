open Alcotest

let head ?(headers = Choku.Headers.empty) target =
  Choku.Request_head.make ~meth:Choku.Method.GET ~target ~headers

let test_fields () =
  let headers = Choku.Headers.empty |> Choku.Headers.add "x-mode" "stream" in
  let head = head ~headers "/upload?part=1" in
  check bool "method" true
    (Choku.Method.equal Choku.Method.GET (Choku.Request_head.meth head));
  check string "target" "/upload?part=1" (Choku.Request_head.target head);
  check string "path" "/upload" (Choku.Request_head.path head);
  check (option string) "header" (Some "stream")
    (Choku.Headers.get "x-mode" (Choku.Request_head.headers head))

let test_does_not_require_host () =
  let head = head "/" in
  check string "path" "/" (Choku.Request_head.path head)

let test_invalid_target () =
  check_raises "invalid target" (Invalid_argument "invalid origin-form target")
    (fun () -> ignore (head "https://example.test/" : Choku.Request_head.t))

let test_reject_control_targets () =
  List.iter
    (fun target ->
      check_raises ("invalid " ^ target)
        (Invalid_argument "invalid origin-form target") (fun () ->
          ignore (head target : Choku.Request_head.t)))
    [
      "/bad path"; "/bad\tpath"; "/bad\rpath"; "/bad\npath"; "/bad#fragment"; "";
    ]

let () =
  run "request_head"
    [
      ( "request_head",
        [
          test_case "fields" `Quick test_fields;
          test_case "does not require Host" `Quick test_does_not_require_host;
          test_case "invalid target" `Quick test_invalid_target;
          test_case "control targets" `Quick test_reject_control_targets;
        ] );
    ]
