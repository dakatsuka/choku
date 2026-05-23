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
let random_source byte = Eio.Flow.string_source (String.make 16 (Char.chr byte))
let random_sources bytes = Eio.Flow.string_source (String.concat "" bytes)

let with_temp_dir name fn =
  Eio_main.run @@ fun env ->
  let dir =
    Eio.Path.(
      Eio.Stdenv.fs env
      / ("/tmp/camelio-multipart-" ^ string_of_int (Unix.getpid ()) ^ "-" ^ name))
  in
  (try Eio.Path.rmtree ~missing_ok:true dir with _ -> ());
  Fun.protect
    ~finally:(fun () -> try Eio.Path.rmtree ~missing_ok:true dir with _ -> ())
    (fun () ->
      Eio.Path.mkdir ~perm:0o700 dir;
      fn dir)

module Failing_source = struct
  type t = { mutable read_count : int }

  let read_methods = []

  let single_read t buffer =
    match t.read_count with
    | 0 ->
        t.read_count <- 1;
        Cstruct.blit_from_string "partial" 0 buffer 0 7;
        7
    | _ -> failwith "copy failed"
end

let failing_source () =
  Eio.Resource.T
    ( { Failing_source.read_count = 0 },
      Eio.Flow.Pi.source (module Failing_source) )

let expect_multipart = function
  | Ok multipart -> multipart
  | Error error ->
      fail
        (Format.asprintf "expected multipart, got %a" Camelio.Multipart.pp_error
           error)

let part_body part = Camelio.Body.to_string (Camelio.Multipart.Part.body part)

let test_filename_sanitize () =
  let sanitize = Camelio.Multipart.Filename.sanitize in
  check string "slash" "foo-bar.jpg" (sanitize "foo/bar.jpg");
  check string "backslash" "foo-bar.jpg" (sanitize "foo\\bar.jpg");
  check string "colon" "foo-bar.jpg" (sanitize "foo:bar.jpg");
  check string "collapse unsafe" "foo-bar.jpg" (sanitize "foo///bar.jpg");
  check string "leading dot" "env" (sanitize ".env");
  check string "dot traversal" "secret.txt" (sanitize "../secret.txt");
  check string "blank fallback" "upload" (sanitize "   ");
  check string "unsafe fallback" "upload" (sanitize "../../../");
  check string "fallback length" "upl" (sanitize ~max_length:3 "../../../");
  check string "nul" "foo-bar.jpg" (sanitize "foo\x00bar.jpg");
  check string "crlf" "foo-bar.jpg" (sanitize "foo\r\nbar.jpg");
  check string "length" "avatar" (sanitize ~max_length:6 "avatar-image.jpg");
  check_raises "invalid max length" (Invalid_argument "non-positive max_length")
    (fun () -> ignore (sanitize ~max_length:0 "avatar.jpg" : string))

let test_tempfile_save_source () =
  with_temp_dir "save-source" @@ fun dir ->
  let saved =
    Camelio.Multipart.Tempfile.save_source ~dir ~random:(random_source 0)
      ~original_filename:"foo/bar.jpg"
      (Eio.Flow.string_source "hello")
  in
  let expected_name = "camelio-upload-00000000000000000000000000000000.tmp" in
  check (option string) "basename" (Some expected_name)
    (Eio.Path.split (Camelio.Multipart.Tempfile.path saved) |> Option.map snd);
  check (option string) "original" (Some "foo/bar.jpg")
    (Camelio.Multipart.Tempfile.original_filename saved);
  check (option string) "display" (Some "foo-bar.jpg")
    (Camelio.Multipart.Tempfile.display_filename saved);
  check int "size" 5 (Camelio.Multipart.Tempfile.size saved);
  check string "body" "hello"
    (Eio.Path.load (Camelio.Multipart.Tempfile.path saved));
  check (list string) "entries" [ expected_name ] (Eio.Path.read_dir dir)

let test_tempfile_save_source_retries_on_collision () =
  with_temp_dir "collision" @@ fun dir ->
  let first_name = "camelio-upload-00000000000000000000000000000000.tmp" in
  let second_name = "camelio-upload-02020202020202020202020202020202.tmp" in
  Eio.Path.save ~create:(`Exclusive 0o600)
    Eio.Path.(dir / first_name)
    "existing";
  let saved =
    Camelio.Multipart.Tempfile.save_source ~dir
      ~random:
        (random_sources
           [ String.make 16 (Char.chr 0); String.make 16 (Char.chr 2) ])
      (Eio.Flow.string_source "hello")
  in
  check (option string) "basename" (Some second_name)
    (Eio.Path.split (Camelio.Multipart.Tempfile.path saved) |> Option.map snd);
  check string "body" "hello"
    (Eio.Path.load (Camelio.Multipart.Tempfile.path saved));
  check (list string) "entries"
    [ first_name; second_name ]
    (Eio.Path.read_dir dir)

let test_tempfile_save_source_cleans_up_on_failure () =
  with_temp_dir "cleanup" @@ fun dir ->
  check_raises "copy failure" (Failure "copy failed") (fun () ->
      ignore
        (Camelio.Multipart.Tempfile.save_source ~dir ~random:(random_source 1)
           (failing_source ())
          : _ Camelio.Multipart.Tempfile.t));
  check (list string) "entries" [] (Eio.Path.read_dir dir)

let file_part () =
  let multipart =
    Camelio.Multipart.decode ~boundary multipart_body |> expect_multipart
  in
  match Camelio.Multipart.get "file" multipart with
  | Some part -> part
  | None -> fail "expected file part"

let test_tempfile_save_part () =
  with_temp_dir "save-part" @@ fun dir ->
  let saved =
    Camelio.Multipart.Tempfile.save_part ~dir ~random:(random_source 255)
      (file_part ())
  in
  check (option string) "original" (Some "hello.txt")
    (Camelio.Multipart.Tempfile.original_filename saved);
  check (option string) "display" (Some "hello.txt")
    (Camelio.Multipart.Tempfile.display_filename saved);
  check int "size" 10 (Camelio.Multipart.Tempfile.size saved);
  check string "body" "hello file"
    (Eio.Path.load (Camelio.Multipart.Tempfile.path saved))

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

let test_filename_sanitize_path_traversal_from_part () =
  let body =
    "--AaB03x\r\n\
     Content-Disposition: form-data; name=\"file\"; \
     filename=\"../../.ssh/id_rsa\"\r\n\
     \r\n\
     content\r\n\
     --AaB03x--\r\n"
  in
  let multipart = Camelio.Multipart.decode ~boundary body |> expect_multipart in
  match Camelio.Multipart.get "file" multipart with
  | None -> fail "expected file part"
  | Some part ->
      check (option string) "raw filename" (Some "../../.ssh/id_rsa")
        (Camelio.Multipart.Part.filename part);
      check string "sanitized" "ssh-id_rsa"
        (Camelio.Multipart.Part.filename part
        |> Option.value ~default:"" |> Camelio.Multipart.Filename.sanitize)

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

let streaming_request ?content_type body =
  let body =
    Camelio.Body.Internal.streaming ~content_length:(String.length body)
      (Eio.Flow.string_source body)
  in
  request_with_body ?content_type body

module Chunk_source = struct
  type t = { mutable chunks : string list }

  let read_methods = []

  let single_read t buffer =
    match t.chunks with
    | [] -> raise End_of_file
    | chunk :: rest ->
        let read = min (String.length chunk) (Cstruct.length buffer) in
        Cstruct.blit_from_string chunk 0 buffer 0 read;
        if read = String.length chunk then t.chunks <- rest
        else
          t.chunks <- String.sub chunk read (String.length chunk - read) :: rest;
        read
end

let chunked_streaming_request ?content_type ~content_length chunks =
  let source =
    Eio.Resource.T
      ({ Chunk_source.chunks }, Eio.Flow.Pi.source (module Chunk_source))
  in
  let body = Camelio.Body.Internal.streaming ~content_length source in
  request_with_body ?content_type body

let test_streaming_iter_request () =
  let seen = ref [] in
  let request =
    streaming_request ~content_type:"multipart/form-data; boundary=AaB03x"
      multipart_body
  in
  let parse_result =
    Camelio.Multipart.Streaming.iter_request request
      ~on_part:(fun part source ->
        let body = Eio.Flow.read_all source in
        seen :=
          Printf.sprintf "%s|%s|%s|%s"
            (Option.value ~default:"" (Camelio.Multipart.Streaming.name part))
            (Option.value ~default:""
               (Camelio.Multipart.Streaming.filename part))
            (Option.value ~default:""
               (Camelio.Multipart.Streaming.content_type part))
            body
          :: !seen)
  in
  check (result unit multipart_error) "result" (Ok ()) parse_result;
  check (list string) "parts"
    [ "field1|||value1"; "file|hello.txt|text/plain|hello file" ]
    (List.rev !seen)

let test_streaming_iter_request_partial_consumption () =
  let seen = ref [] in
  let request =
    streaming_request ~content_type:"multipart/form-data; boundary=AaB03x"
      multipart_body
  in
  let parse_result =
    Camelio.Multipart.Streaming.iter_request request
      ~on_part:(fun part source ->
        let body =
          match Camelio.Multipart.Streaming.name part with
          | Some "field1" ->
              let buffer = Cstruct.create 3 in
              ignore (Eio.Flow.single_read source buffer : int);
              Cstruct.to_string buffer
          | _ -> Eio.Flow.read_all source
        in
        seen := body :: !seen)
  in
  check (result unit multipart_error) "result" (Ok ()) parse_result;
  check (list string) "parts" [ "val"; "hello file" ] (List.rev !seen)

let test_streaming_iter_request_rejects_malformed_body () =
  let request =
    streaming_request ~content_type:"multipart/form-data; boundary=AaB03x"
      "not multipart"
  in
  check
    (result reject multipart_error)
    "malformed" (Error Camelio.Multipart.Malformed_body)
    (Camelio.Multipart.Streaming.iter_request request ~on_part:(fun _ _ ->
         fail "handler should not run"))

let test_streaming_iter_request_rejects_content_type_errors () =
  check
    (result reject multipart_error)
    "missing content-type" (Error Camelio.Multipart.Missing_content_type)
    (Camelio.Multipart.Streaming.iter_request (streaming_request multipart_body)
       ~on_part:(fun _ _ -> fail "handler should not run"));
  check
    (result reject multipart_error)
    "unsupported content-type"
    (Error (Camelio.Multipart.Unsupported_content_type "application/json"))
    (Camelio.Multipart.Streaming.iter_request
       (streaming_request ~content_type:"application/json" multipart_body)
       ~on_part:(fun _ _ -> fail "handler should not run"));
  check
    (result reject multipart_error)
    "missing boundary" (Error Camelio.Multipart.Missing_boundary)
    (Camelio.Multipart.Streaming.iter_request
       (streaming_request ~content_type:"multipart/form-data" multipart_body)
       ~on_part:(fun _ _ -> fail "handler should not run"))

let test_streaming_iter_request_rejects_negative_max_header_size () =
  let request =
    streaming_request ~content_type:"multipart/form-data; boundary=AaB03x"
      multipart_body
  in
  check_raises "negative max_header_size"
    (Invalid_argument "negative max_header_size") (fun () ->
      ignore
        (Camelio.Multipart.Streaming.iter_request ~max_header_size:(-1) request
           ~on_part:(fun _ _ -> ())
          : (unit, Camelio.Multipart.error) result))

let test_streaming_iter_request_propagates_callback_exception () =
  let request =
    streaming_request ~content_type:"multipart/form-data; boundary=AaB03x"
      multipart_body
  in
  check_raises "callback exception" (Failure "boom") (fun () ->
      ignore
        (Camelio.Multipart.Streaming.iter_request request ~on_part:(fun _ _ ->
             failwith "boom")
          : (unit, Camelio.Multipart.error) result))

let test_streaming_iter_request_rejects_large_headers () =
  let request =
    streaming_request ~content_type:"multipart/form-data; boundary=AaB03x"
      multipart_body
  in
  check
    (result reject multipart_error)
    "large headers" (Error Camelio.Multipart.Malformed_body)
    (Camelio.Multipart.Streaming.iter_request ~max_header_size:10 request
       ~on_part:(fun _ _ -> fail "handler should not run"))

let test_streaming_iter_request_allows_split_header_terminator_at_limit () =
  let header = "Content-Disposition: form-data; name=\"field1\"" in
  let chunks =
    [ "--AaB03x\r\n"; header; "\r"; "\n\r\nvalue1\r\n--AaB03x--\r\n" ]
  in
  let content_length =
    chunks |> List.map String.length |> List.fold_left ( + ) 0
  in
  let request =
    chunked_streaming_request ~content_length
      ~content_type:"multipart/form-data; boundary=AaB03x" chunks
  in
  let seen = ref [] in
  let parse_result =
    Camelio.Multipart.Streaming.iter_request
      ~max_header_size:(String.length header) request ~on_part:(fun _ source ->
        seen := Eio.Flow.read_all source :: !seen)
  in
  check (result unit multipart_error) "result" (Ok ()) parse_result;
  check (list string) "body" [ "value1" ] (List.rev !seen)

let test_streaming_iter_request_rejects_missing_final_boundary () =
  let body =
    "--AaB03x\r\nContent-Disposition: form-data; name=\"field1\"\r\n\r\nvalue1"
  in
  let request =
    streaming_request ~content_type:"multipart/form-data; boundary=AaB03x" body
  in
  check
    (result reject multipart_error)
    "unexpected end" (Error Camelio.Multipart.Unexpected_end_of_body)
    (Camelio.Multipart.Streaming.iter_request request ~on_part:(fun _ source ->
         ignore (Eio.Flow.read_all source : string)))

let test_streaming_iter_request_preserves_boundary_like_body () =
  let body =
    "--AaB03x\r\n\
     Content-Disposition: form-data; name=\"field1\"\r\n\
     \r\n\
     before\r\n\
     --AaB03x-not-a-boundary\r\n\
     after\r\n\
     --AaB03x--\r\n"
  in
  let request =
    streaming_request ~content_type:"multipart/form-data; boundary=AaB03x" body
  in
  let seen = ref [] in
  let parse_result =
    Camelio.Multipart.Streaming.iter_request request ~on_part:(fun _ source ->
        seen := Eio.Flow.read_all source :: !seen)
  in
  check (result unit multipart_error) "result" (Ok ()) parse_result;
  check (list string) "body"
    [ "before\r\n--AaB03x-not-a-boundary\r\nafter" ]
    (List.rev !seen)

let test_streaming_iter_request_handles_split_boundary () =
  let body =
    "--AaB03x\r\nContent-Disposition: form-data; name=\"field1\"\r\n\r\n"
    ^ String.make 4_040 'x' ^ "\r\n--AaB03x--\r\n"
  in
  let request =
    streaming_request ~content_type:"multipart/form-data; boundary=AaB03x" body
  in
  let seen = ref [] in
  let parse_result =
    Camelio.Multipart.Streaming.iter_request request ~on_part:(fun _ source ->
        seen := Eio.Flow.read_all source :: !seen)
  in
  check (result unit multipart_error) "result" (Ok ()) parse_result;
  check (list int) "body length" [ 4_040 ]
    (List.map String.length (List.rev !seen))

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
      "--AaB03x\r\nX-Test: ok\rbad\r\n\r\nbody\r\n--AaB03x--\r\n";
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
          test_case "filename sanitize" `Quick test_filename_sanitize;
          test_case "tempfile save source" `Quick test_tempfile_save_source;
          test_case "tempfile retries on collision" `Quick
            test_tempfile_save_source_retries_on_collision;
          test_case "tempfile save part" `Quick test_tempfile_save_part;
          test_case "tempfile cleanup on failure" `Quick
            test_tempfile_save_source_cleans_up_on_failure;
          test_case "decode parts" `Quick test_decode_parts;
          test_case "part copy_to_sink" `Quick test_part_copy_to_sink;
          test_case "part save_to_path" `Quick test_part_save_to_path;
          test_case "get and get_all preserve order" `Quick
            test_get_and_get_all_preserve_order;
          test_case "quoted parameter semicolon" `Quick
            test_quoted_parameter_semicolon;
          test_case "filename sanitize path traversal from part" `Quick
            test_filename_sanitize_path_traversal_from_part;
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
          test_case "streaming iter_request" `Quick test_streaming_iter_request;
          test_case "streaming iter_request partial consumption" `Quick
            test_streaming_iter_request_partial_consumption;
          test_case "streaming iter_request rejects malformed body" `Quick
            test_streaming_iter_request_rejects_malformed_body;
          test_case "streaming iter_request rejects content-type errors" `Quick
            test_streaming_iter_request_rejects_content_type_errors;
          test_case "streaming iter_request rejects negative max header size"
            `Quick test_streaming_iter_request_rejects_negative_max_header_size;
          test_case "streaming iter_request propagates callback exception"
            `Quick test_streaming_iter_request_propagates_callback_exception;
          test_case "streaming iter_request rejects large headers" `Quick
            test_streaming_iter_request_rejects_large_headers;
          test_case
            "streaming iter_request allows split header terminator at limit"
            `Quick
            test_streaming_iter_request_allows_split_header_terminator_at_limit;
          test_case "streaming iter_request rejects missing final boundary"
            `Quick test_streaming_iter_request_rejects_missing_final_boundary;
          test_case "streaming iter_request preserves boundary-like body" `Quick
            test_streaming_iter_request_preserves_boundary_like_body;
          test_case "streaming iter_request handles split boundary" `Quick
            test_streaming_iter_request_handles_split_boundary;
          test_case "decode rejects malformed body" `Quick
            test_decode_rejects_malformed_body;
          test_case "decode rejects empty boundary" `Quick
            test_decode_rejects_empty_boundary;
          test_case "pp_error" `Quick test_pp_error;
        ] );
    ]
