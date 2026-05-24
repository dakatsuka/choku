open Alcotest

[@@@alert "-internal"]

let test_body_values () =
  check string "empty" "" (Choku.Body.to_string Choku.Body.empty);
  check bool "empty buffered" true (Choku.Body.is_buffered Choku.Body.empty);
  check string "string" "hello"
    (Choku.Body.to_string (Choku.Body.string "hello"));
  check bool "string buffered" true
    (Choku.Body.is_buffered (Choku.Body.string "hello"))

let test_to_string_limited () =
  check
    (result string (of_pp Choku.Body.pp_error))
    "within limit" (Ok "hello")
    (Choku.Body.to_string_limited ~max_size:5 (Choku.Body.string "hello"));
  check
    (result string (of_pp Choku.Body.pp_error))
    "too large" (Error Choku.Body.Body_too_large)
    (Choku.Body.to_string_limited ~max_size:4 (Choku.Body.string "hello"))

let test_to_string_limited_rejects_negative_max_size () =
  check_raises "negative max_size" (Invalid_argument "negative max_size")
    (fun () ->
      ignore
        (Choku.Body.to_string_limited ~max_size:(-1) Choku.Body.empty
          : (string, Choku.Body.error) result))

let test_to_string_limited_streaming () =
  let body =
    Choku.Body.Internal.streaming ~content_length:5
      (Eio.Flow.string_source "hello")
  in
  check bool "streaming" false (Choku.Body.is_buffered body);
  check
    (result string (of_pp Choku.Body.pp_error))
    "read" (Ok "hello")
    (Choku.Body.to_string_limited ~max_size:5 body);
  check_raises "single consumption"
    (Invalid_argument "streaming body has already been consumed") (fun () ->
      ignore (Choku.Body.with_source body Eio.Flow.read_all : string))

let test_to_string_limited_streaming_too_large () =
  let body =
    Choku.Body.Internal.streaming ~content_length:5
      (Eio.Flow.string_source "hello")
  in
  check
    (result string (of_pp Choku.Body.pp_error))
    "too large" (Error Choku.Body.Body_too_large)
    (Choku.Body.to_string_limited ~max_size:4 body)

let test_to_string_limited_streaming_short_body () =
  let body =
    Choku.Body.Internal.streaming ~content_length:5
      (Eio.Flow.string_source "hi")
  in
  check
    (result string (of_pp Choku.Body.pp_error))
    "short body" (Error Choku.Body.Unexpected_end_of_body)
    (Choku.Body.to_string_limited ~max_size:5 body)

let test_streaming_to_string_raises () =
  let body =
    Choku.Body.Internal.streaming ~content_length:5
      (Eio.Flow.string_source "hello")
  in
  check_raises "streaming to_string"
    (Invalid_argument "streaming body cannot be read with Body.to_string")
    (fun () -> ignore (Choku.Body.to_string body : string))

let test_pp_error () =
  check string "body too large" "body too large"
    (Format.asprintf "%a" Choku.Body.pp_error Choku.Body.Body_too_large);
  check string "unexpected end of body" "unexpected end of body"
    (Format.asprintf "%a" Choku.Body.pp_error Choku.Body.Unexpected_end_of_body)

let test_body_source () =
  let body = Choku.Body.string "hello" in
  check bool "buffered" true (Choku.Body.is_buffered body);
  let read () = Choku.Body.with_source body Eio.Flow.read_all in
  check string "source" "hello" (read ());
  check string "source replayable" "hello" (read ());
  check string "to_string after source read" "hello" (Choku.Body.to_string body)

let test_copy_to_sink () =
  let buffer = Buffer.create 16 in
  Choku.Body.copy_to_sink
    (Choku.Body.string "hello")
    (Eio.Flow.buffer_sink buffer);
  check string "sink" "hello" (Buffer.contents buffer)

let test_save_to_path () =
  Eio_main.run @@ fun env ->
  let path =
    Eio.Path.(
      Eio.Stdenv.fs env
      / ("/tmp/choku-body-" ^ string_of_int (Unix.getpid ()) ^ ".txt"))
  in
  Fun.protect
    ~finally:(fun () -> try Eio.Path.unlink path with _ -> ())
    (fun () ->
      Choku.Body.save_to_path ~create:(`Or_truncate 0o600) path
        (Choku.Body.string "hello");
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
          test_case "to_string_limited streaming" `Quick
            test_to_string_limited_streaming;
          test_case "to_string_limited streaming too large" `Quick
            test_to_string_limited_streaming_too_large;
          test_case "to_string_limited streaming short body" `Quick
            test_to_string_limited_streaming_short_body;
          test_case "streaming to_string raises" `Quick
            test_streaming_to_string_raises;
          test_case "pp_error" `Quick test_pp_error;
          test_case "body source" `Quick test_body_source;
          test_case "copy to sink" `Quick test_copy_to_sink;
          test_case "save to path" `Quick test_save_to_path;
        ] );
    ]
