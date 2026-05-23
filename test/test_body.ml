open Alcotest

let test_body_values () =
  check string "empty" "" (Camelio.Body.to_string Camelio.Body.empty);
  check string "string" "hello"
    (Camelio.Body.to_string (Camelio.Body.string "hello"))

let test_body_source () =
  let body = Camelio.Body.string "hello" in
  check bool "buffered" true (Camelio.Body.is_buffered body);
  let read () = Camelio.Body.with_source body Eio.Flow.read_all in
  check string "source" "hello" (read ());
  check string "source replayable" "hello" (read ())

let () =
  run "body"
    [
      ( "body",
        [
          test_case "body values" `Quick test_body_values;
          test_case "body source" `Quick test_body_source;
        ] );
    ]
