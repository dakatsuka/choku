open Alcotest

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
  let headers =
    match content_type with
    | None -> Camelio.Headers.empty
    | Some value ->
        Camelio.Headers.add "content-type" value Camelio.Headers.empty
  in
  Camelio.Request.make ~meth:Camelio.Method.POST ~target:"/upload" ~headers
    ~body:(Camelio.Body.string body)

let multipart_error = of_pp Camelio.Multipart.pp_error

let expect_multipart = function
  | Ok multipart -> multipart
  | Error error ->
      fail
        (Format.asprintf "expected multipart, got %a" Camelio.Multipart.pp_error
           error)

let part_body part = Camelio.Body.to_string (Camelio.Multipart.Part.body part)

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

let test_of_request_extracts_quoted_boundary () =
  let request =
    request
      ~content_type:"Multipart/Form-Data; boundary=\"AaB03x\"; charset=utf-8"
      multipart_body
  in
  let multipart = Camelio.Multipart.of_request request |> expect_multipart in
  check int "part count" 2 (List.length (Camelio.Multipart.parts multipart))

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
       Camelio.Multipart.Malformed_body)

let () =
  run "multipart"
    [
      ( "multipart",
        [
          test_case "decode parts" `Quick test_decode_parts;
          test_case "get and get_all preserve order" `Quick
            test_get_and_get_all_preserve_order;
          test_case "of_request extracts quoted boundary" `Quick
            test_of_request_extracts_quoted_boundary;
          test_case "of_request rejects missing content-type" `Quick
            test_of_request_rejects_missing_content_type;
          test_case "of_request rejects unsupported content-type" `Quick
            test_of_request_rejects_unsupported_content_type;
          test_case "of_request rejects missing boundary" `Quick
            test_of_request_rejects_missing_boundary;
          test_case "decode rejects malformed body" `Quick
            test_decode_rejects_malformed_body;
          test_case "decode rejects empty boundary" `Quick
            test_decode_rejects_empty_boundary;
          test_case "pp_error" `Quick test_pp_error;
        ] );
    ]
