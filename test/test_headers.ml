open Alcotest

let test_add_get_and_get_all () =
  let headers =
    Camelio.Headers.empty
    |> Camelio.Headers.add "Set-Cookie" "a=1"
    |> Camelio.Headers.add "set-cookie" "b=2"
  in
  check (option string) "first value" (Some "a=1")
    (Camelio.Headers.get "SET-COOKIE" headers);
  check (list string) "all values" [ "a=1"; "b=2" ]
    (Camelio.Headers.get_all "Set-Cookie" headers)

let test_set_replaces_and_appends () =
  let headers =
    Camelio.Headers.empty
    |> Camelio.Headers.add "X-Test" "old"
    |> Camelio.Headers.add "Other" "value"
    |> Camelio.Headers.set "x-test" "new"
  in
  check
    (list (pair string string))
    "insertion order"
    [ ("Other", "value"); ("x-test", "new") ]
    (Camelio.Headers.to_list headers)

let test_reject_invalid_names_and_values () =
  check_raises "space in name" (Invalid_argument "invalid HTTP header name")
    (fun () ->
      ignore (Camelio.Headers.add "Bad Name" "x" Camelio.Headers.empty));
  check_raises "newline in value" (Invalid_argument "invalid HTTP header value")
    (fun () ->
      ignore (Camelio.Headers.add "Good" "bad\r\nvalue" Camelio.Headers.empty))

let () =
  run "headers"
    [
      ( "headers",
        [
          test_case "add and lookup" `Quick test_add_get_and_get_all;
          test_case "set replaces case-insensitive matches" `Quick
            test_set_replaces_and_appends;
          test_case "reject invalid names and values" `Quick
            test_reject_invalid_names_and_values;
        ] );
    ]
