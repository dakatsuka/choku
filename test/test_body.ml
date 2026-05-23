open Alcotest

let test_body_values () =
  check string "empty" "" (Camelio.Body.to_string Camelio.Body.empty);
  check string "string" "hello"
    (Camelio.Body.to_string (Camelio.Body.string "hello"))

let test_to_string_limited () =
  check
    (result string (of_pp Camelio.Body.pp_error))
    "within limit" (Ok "hello")
    (Camelio.Body.to_string_limited ~max_size:5 (Camelio.Body.string "hello"));
  check
    (result string (of_pp Camelio.Body.pp_error))
    "too large" (Error Camelio.Body.Body_too_large)
    (Camelio.Body.to_string_limited ~max_size:4 (Camelio.Body.string "hello"))

let test_to_string_limited_rejects_negative_max_size () =
  check_raises "negative max_size" (Invalid_argument "negative max_size")
    (fun () ->
      ignore
        (Camelio.Body.to_string_limited ~max_size:(-1) Camelio.Body.empty
          : (string, Camelio.Body.error) result))

let test_pp_error () =
  check string "body too large" "body too large"
    (Format.asprintf "%a" Camelio.Body.pp_error Camelio.Body.Body_too_large)

let test_body_source () =
  let body = Camelio.Body.string "hello" in
  check bool "buffered" true (Camelio.Body.is_buffered body);
  let read () = Camelio.Body.with_source body Eio.Flow.read_all in
  check string "source" "hello" (read ());
  check string "source replayable" "hello" (read ())

let test_copy_to_sink () =
  let buffer = Buffer.create 16 in
  Camelio.Body.copy_to_sink
    (Camelio.Body.string "hello")
    (Eio.Flow.buffer_sink buffer);
  check string "sink" "hello" (Buffer.contents buffer)

let test_save_to_path () =
  Eio_main.run @@ fun env ->
  let path =
    Eio.Path.(
      Eio.Stdenv.fs env
      / ("/tmp/camelio-body-" ^ string_of_int (Unix.getpid ()) ^ ".txt"))
  in
  Fun.protect
    ~finally:(fun () -> try Eio.Path.unlink path with _ -> ())
    (fun () ->
      Camelio.Body.save_to_path ~create:(`Or_truncate 0o600) path
        (Camelio.Body.string "hello");
      check string "file" "hello" (Eio.Path.load path))

let () =
  run "body"
    [
      ( "body",
        [
          test_case "body values" `Quick test_body_values;
          test_case "to_string_limited" `Quick test_to_string_limited;
          test_case "to_string_limited rejects negative max_size" `Quick
            test_to_string_limited_rejects_negative_max_size;
          test_case "pp_error" `Quick test_pp_error;
          test_case "body source" `Quick test_body_source;
          test_case "copy to sink" `Quick test_copy_to_sink;
          test_case "save to path" `Quick test_save_to_path;
        ] );
    ]
