open Alcotest

let test_add_get_and_get_all () =
  let headers =
    Choku.Headers.empty
    |> Choku.Headers.add "Set-Cookie" "a=1"
    |> Choku.Headers.add "set-cookie" "b=2"
  in
  check (option string) "first value" (Some "a=1")
    (Choku.Headers.get "SET-COOKIE" headers);
  check (list string) "all values" [ "a=1"; "b=2" ]
    (Choku.Headers.get_all "Set-Cookie" headers)

let test_set_replaces_and_appends () =
  let headers =
    Choku.Headers.empty
    |> Choku.Headers.add "X-Test" "old"
    |> Choku.Headers.add "Other" "value"
    |> Choku.Headers.set "x-test" "new"
  in
  check
    (list (pair string string))
    "insertion order"
    [ ("Other", "value"); ("x-test", "new") ]
    (Choku.Headers.to_list headers)

let test_remove_deletes_case_insensitive_matches () =
  let headers =
    Choku.Headers.empty
    |> Choku.Headers.add "Content-Length" "10"
    |> Choku.Headers.add "x-test" "ok"
    |> Choku.Headers.add "content-length" "11"
    |> Choku.Headers.remove "CONTENT-LENGTH"
  in
  check
    (list (pair string string))
    "remaining headers"
    [ ("x-test", "ok") ]
    (Choku.Headers.to_list headers);
  check_raises "bad name" (Invalid_argument "invalid HTTP header name")
    (fun () -> ignore (Choku.Headers.remove "Bad Name" headers))

let test_reject_invalid_names_and_values () =
  check_raises "space in name" (Invalid_argument "invalid HTTP header name")
    (fun () -> ignore (Choku.Headers.add "Bad Name" "x" Choku.Headers.empty));
  check_raises "newline in value" (Invalid_argument "invalid HTTP header value")
    (fun () ->
      ignore (Choku.Headers.add "Good" "bad\r\nvalue" Choku.Headers.empty))

let () =
  run "headers"
    [
      ( "headers",
        [
          test_case "add and lookup" `Quick test_add_get_and_get_all;
          test_case "set replaces case-insensitive matches" `Quick
            test_set_replaces_and_appends;
          test_case "remove deletes case-insensitive matches" `Quick
            test_remove_deletes_case_insensitive_matches;
          test_case "reject invalid names and values" `Quick
            test_reject_invalid_names_and_values;
        ] );
    ]
