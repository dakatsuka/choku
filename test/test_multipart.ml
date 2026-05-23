open Alcotest

[@@@alert "-internal"]

let boundary = "AaB03x"

let multipart_body =
  "--AaB03x\r\n\
   Content-Disposition: form-data; name=\"field1\"\r\n\
   \r\n\
   value1\r\n\
   --AaB03x\r\n\
   Content-Disposition: form-data; name=\"file\"; filename=\"hello.txt\"\r\n\
   Content-Type: text/plain\r\n\
   X-Trace: one\r\n\
   \r\n\
   hello file\r\n\
   --AaB03x--\r\n"

let request ?content_type body =
  let body = Camelio.Body.string body in
  let headers =
    match content_type with
    | None -> Camelio.Headers.empty
    | Some value ->
        Camelio.Headers.add "content-type" value Camelio.Headers.empty
  in
  Camelio.Request.make ~meth:Camelio.Method.POST ~target:"/upload" ~headers
    ~body

let request_with_body ?content_type body =
  let headers =
    match content_type with
    | None -> Camelio.Headers.empty
    | Some value ->
        Camelio.Headers.add "content-type" value Camelio.Headers.empty
  in
  Camelio.Request.make ~meth:Camelio.Method.POST ~target:"/upload" ~headers
    ~body

let multipart_error = of_pp Camelio.Multipart.pp_error

let expect_multipart = function
  | Ok multipart -> multipart
  | Error error ->
      fail
        (Format.asprintf "expected multipart, got %a" Camelio.Multipart.pp_error
           error)

let part_body part = Camelio.Body.to_string (Camelio.Multipart.Part.body part)

let file_part () =
  let multipart =
    Camelio.Multipart.decode ~boundary multipart_body |> expect_multipart
  in
  match Camelio.Multipart.get "file" multipart with
  | Some part -> part
  | None -> fail "expected file part"

let test_decode_parts () =
  let multipart =
    Camelio.Multipart.decode ~boundary multipart_body |> expect_multipart
  in
  let parts = Camelio.Multipart.parts multipart in
  check int "part count" 2 (List.length parts);
  match parts with
  | [ field; file ] ->
      check (option string) "field name" (Some "field1")
        (Camelio.Multipart.Part.name field);
      check string "field body" "value1" (part_body field);
      check (option string) "file name" (Some "file")
        (Camelio.Multipart.Part.name file);
      check (option string) "filename" (Some "hello.txt")
        (Camelio.Multipart.Part.filename file);
      check (option string) "content type" (Some "text/plain")
        (Camelio.Multipart.Part.content_type file);
      check (option string) "custom header" (Some "one")
        (Camelio.Headers.get "x-trace" (Camelio.Multipart.Part.headers file));
      check string "file body" "hello file" (part_body file)
  | _ -> fail "unexpected part count"

let test_part_copy_to_sink () =
  let buffer = Buffer.create 16 in
  Camelio.Multipart.Part.copy_to_sink (file_part ())
    (Eio.Flow.buffer_sink buffer);
  check string "sink body" "hello file" (Buffer.contents buffer)

let test_part_save_to_path () =
  Eio_main.run @@ fun env ->
  let path =
    Eio.Path.(
      Eio.Stdenv.fs env
      / ("/tmp/camelio-multipart-part-"
        ^ string_of_int (Unix.getpid ())
        ^ ".txt"))
  in
  Fun.protect
    ~finally:(fun () -> try Eio.Path.unlink path with _ -> ())
    (fun () ->
      Camelio.Multipart.Part.save_to_path ~create:(`Or_truncate 0o600) path
        (file_part ());
      check string "saved body" "hello file" (Eio.Path.load path))

let test_get_and_get_all_preserve_order () =
  let body =
    "--AaB03x\r\n\
     Content-Disposition: form-data; name=\"tag\"\r\n\
     \r\n\
     ocaml\r\n\
     --AaB03x\r\n\
     Content-Disposition: form-data; name=\"tag\"\r\n\
     \r\n\
     eio\r\n\
     --AaB03x--\r\n"
  in
  let multipart = Camelio.Multipart.decode ~boundary body |> expect_multipart in
  check (option string) "first tag" (Some "ocaml")
    (Camelio.Multipart.get "tag" multipart |> Option.map part_body);
  check (list string) "all tags" [ "ocaml"; "eio" ]
    (Camelio.Multipart.get_all "tag" multipart |> List.map part_body)

let test_quoted_parameter_semicolon () =
  let body =
    "--AaB03x\r\n\
     Content-Disposition: form-data; name=\"file\"; filename=\"a;b.txt\"\r\n\
     \r\n\
     content\r\n\
     --AaB03x--\r\n"
  in
  let multipart = Camelio.Multipart.decode ~boundary body |> expect_multipart in
  match Camelio.Multipart.get "file" multipart with
  | None -> fail "expected file part"
  | Some part ->
      check (option string) "filename" (Some "a;b.txt")
        (Camelio.Multipart.Part.filename part)

let test_of_request_extracts_quoted_boundary () =
  let request =
    request
      ~content_type:"Multipart/Form-Data; boundary=\"AaB03x\"; charset=utf-8"
      multipart_body
  in
  let multipart = Camelio.Multipart.of_request request |> expect_multipart in
  check int "part count" 2 (List.length (Camelio.Multipart.parts multipart))

let test_of_request_limited_extracts_quoted_boundary () =
  let request =
    request
      ~content_type:"Multipart/Form-Data; boundary=\"AaB03x\"; charset=utf-8"
      multipart_body
  in
  let multipart =
    Camelio.Multipart.of_request_limited
      ~max_size:(String.length multipart_body)
      request
    |> expect_multipart
  in
  check int "part count" 2 (List.length (Camelio.Multipart.parts multipart))

let test_of_request_limited_rejects_body_too_large () =
  let request =
    request ~content_type:"multipart/form-data; boundary=AaB03x" multipart_body
  in
  check
    (result reject multipart_error)
    "body too large" (Error Camelio.Multipart.Body_too_large)
    (Camelio.Multipart.of_request_limited
       ~max_size:(String.length multipart_body - 1)
       request)

let test_of_request_limited_rejects_malformed_body () =
  let request =
    request ~content_type:"multipart/form-data; boundary=AaB03x" "not multipart"
  in
  check
    (result reject multipart_error)
    "malformed" (Error Camelio.Multipart.Malformed_body)
    (Camelio.Multipart.of_request_limited ~max_size:20 request)

let test_of_request_limited_rejects_unexpected_end_of_body () =
  let body =
    Camelio.Body.Internal.streaming
      ~content_length:(String.length multipart_body)
      (Eio.Flow.string_source (String.sub multipart_body 0 10))
  in
  let request =
    request_with_body ~content_type:"multipart/form-data; boundary=AaB03x" body
  in
  check
    (result reject multipart_error)
    "unexpected end" (Error Camelio.Multipart.Unexpected_end_of_body)
    (Camelio.Multipart.of_request_limited
       ~max_size:(String.length multipart_body)
       request)

let test_of_request_limited_rejects_negative_max_size () =
  let request =
    request ~content_type:"multipart/form-data; boundary=AaB03x" multipart_body
  in
  check_raises "negative max_size" (Invalid_argument "negative max_size")
    (fun () ->
      ignore
        (Camelio.Multipart.of_request_limited ~max_size:(-1) request
          : (Camelio.Multipart.t, Camelio.Multipart.error) result))

let test_of_request_limited_rejects_negative_max_size_before_headers () =
  check_raises "negative max_size" (Invalid_argument "negative max_size")
    (fun () ->
      ignore
        (Camelio.Multipart.of_request_limited ~max_size:(-1)
           (request multipart_body)
          : (Camelio.Multipart.t, Camelio.Multipart.error) result))

let test_of_request_rejects_missing_content_type () =
  check
    (result reject multipart_error)
    "missing content-type" (Error Camelio.Multipart.Missing_content_type)
    (Camelio.Multipart.of_request (request multipart_body))

let test_of_request_rejects_unsupported_content_type () =
  check
    (result reject multipart_error)
    "unsupported content-type"
    (Error (Camelio.Multipart.Unsupported_content_type "application/json"))
    (Camelio.Multipart.of_request
       (request ~content_type:"application/json" multipart_body))

let test_of_request_rejects_missing_boundary () =
  check
    (result reject multipart_error)
    "missing boundary" (Error Camelio.Multipart.Missing_boundary)
    (Camelio.Multipart.of_request
       (request ~content_type:"multipart/form-data" multipart_body));
  check
    (result reject multipart_error)
    "empty boundary" (Error Camelio.Multipart.Missing_boundary)
    (Camelio.Multipart.of_request
       (request ~content_type:"multipart/form-data; boundary=\"\""
          multipart_body))

let test_of_request_limited_rejects_content_type_errors () =
  check
    (result reject multipart_error)
    "missing content-type" (Error Camelio.Multipart.Missing_content_type)
    (Camelio.Multipart.of_request_limited ~max_size:100 (request multipart_body));
  check
    (result reject multipart_error)
    "unsupported content-type"
    (Error (Camelio.Multipart.Unsupported_content_type "application/json"))
    (Camelio.Multipart.of_request_limited ~max_size:100
       (request ~content_type:"application/json" multipart_body));
  check
    (result reject multipart_error)
    "missing boundary" (Error Camelio.Multipart.Missing_boundary)
    (Camelio.Multipart.of_request_limited ~max_size:100
       (request ~content_type:"multipart/form-data" multipart_body))

let test_decode_rejects_malformed_body () =
  List.iter
    (fun body ->
      check
        (result reject multipart_error)
        ("malformed " ^ body) (Error Camelio.Multipart.Malformed_body)
        (Camelio.Multipart.decode ~boundary body))
    [
      "";
      "--AaB03x\r\nContent-Disposition: form-data; name=\"a\"\r\n";
      "--wrong\r\n\r\nbody\r\n--wrong--\r\n";
      "--AaB03x\r\nBad Header\r\n\r\nbody\r\n--AaB03x--\r\n";
      "--AaB03x\r\n\
      \ Content-Disposition: form-data; name=\"a\"\r\n\
       \r\n\
       body\r\n\
       --AaB03x--\r\n";
    ]

let test_decode_rejects_empty_boundary () =
  check
    (result reject multipart_error)
    "missing boundary" (Error Camelio.Multipart.Missing_boundary)
    (Camelio.Multipart.decode ~boundary:"" multipart_body)

let test_pp_error () =
  check string "missing content-type" "missing content-type"
    (Format.asprintf "%a" Camelio.Multipart.pp_error
       Camelio.Multipart.Missing_content_type);
  check string "unsupported" "unsupported content-type: text/plain"
    (Format.asprintf "%a" Camelio.Multipart.pp_error
       (Camelio.Multipart.Unsupported_content_type "text/plain"));
  check string "missing boundary" "missing multipart boundary"
    (Format.asprintf "%a" Camelio.Multipart.pp_error
       Camelio.Multipart.Missing_boundary);
  check string "malformed" "malformed multipart body"
    (Format.asprintf "%a" Camelio.Multipart.pp_error
       Camelio.Multipart.Malformed_body);
  check string "body too large" "multipart body too large"
    (Format.asprintf "%a" Camelio.Multipart.pp_error
       Camelio.Multipart.Body_too_large);
  check string "unexpected end" "unexpected end of multipart body"
    (Format.asprintf "%a" Camelio.Multipart.pp_error
       Camelio.Multipart.Unexpected_end_of_body)

let () =
  run "multipart"
    [
      ( "multipart",
        [
          test_case "decode parts" `Quick test_decode_parts;
          test_case "part copy_to_sink" `Quick test_part_copy_to_sink;
          test_case "part save_to_path" `Quick test_part_save_to_path;
          test_case "get and get_all preserve order" `Quick
            test_get_and_get_all_preserve_order;
          test_case "quoted parameter semicolon" `Quick
            test_quoted_parameter_semicolon;
          test_case "of_request extracts quoted boundary" `Quick
            test_of_request_extracts_quoted_boundary;
          test_case "of_request_limited extracts quoted boundary" `Quick
            test_of_request_limited_extracts_quoted_boundary;
          test_case "of_request_limited rejects body too large" `Quick
            test_of_request_limited_rejects_body_too_large;
          test_case "of_request_limited rejects malformed body" `Quick
            test_of_request_limited_rejects_malformed_body;
          test_case "of_request_limited rejects unexpected end of body" `Quick
            test_of_request_limited_rejects_unexpected_end_of_body;
          test_case "of_request_limited rejects negative max_size" `Quick
            test_of_request_limited_rejects_negative_max_size;
          test_case
            "of_request_limited rejects negative max_size before headers" `Quick
            test_of_request_limited_rejects_negative_max_size_before_headers;
          test_case "of_request rejects missing content-type" `Quick
            test_of_request_rejects_missing_content_type;
          test_case "of_request rejects unsupported content-type" `Quick
            test_of_request_rejects_unsupported_content_type;
          test_case "of_request rejects missing boundary" `Quick
            test_of_request_rejects_missing_boundary;
          test_case "of_request_limited rejects content-type errors" `Quick
            test_of_request_limited_rejects_content_type_errors;
          test_case "decode rejects malformed body" `Quick
            test_decode_rejects_malformed_body;
          test_case "decode rejects empty boundary" `Quick
            test_decode_rejects_empty_boundary;
          test_case "pp_error" `Quick test_pp_error;
        ] );
    ]
