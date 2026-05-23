open Alcotest

let request =
  Camelio.Request.make ~meth:Camelio.Method.GET ~target:"/"
    ~headers:Camelio.Headers.empty ~body:Camelio.Body.empty

let test_create_applies_middleware () =
  let middleware next req =
    next req |> Camelio.Response.with_header "x-middleware" "yes"
  in
  let server =
    Camelio.Server.create ~middlewares:[ middleware ]
      ~handler:(fun _ -> Camelio.Response.text "ok")
      ()
  in
  let response = Camelio.Server.handle server request in
  check (option string) "middleware header" (Some "yes")
    (Camelio.Headers.get "x-middleware" (Camelio.Response.headers response))

let test_default_max_request_body_size () =
  let server =
    Camelio.Server.create ~handler:(fun _ -> Camelio.Response.text "ok") ()
  in
  check int "default" 1_048_576 (Camelio.Server.max_request_body_size server)

let with_server ?(max_request_body_size = 4)
    ?(request_body_mode = Camelio.Server.Buffered) handler f =
  Eio_main.run @@ fun env ->
  let net = Eio.Stdenv.net env in
  let clock = Eio.Stdenv.clock env in
  let port =
    let socket = Unix.socket Unix.PF_INET Unix.SOCK_STREAM 0 in
    Fun.protect
      ~finally:(fun () -> Unix.close socket)
      (fun () ->
        Unix.bind socket Unix.(ADDR_INET (inet_addr_loopback, 0));
        match Unix.getsockname socket with
        | Unix.ADDR_INET (_, port) -> port
        | Unix.ADDR_UNIX _ -> fail "expected TCP socket")
  in
  let addr = `Tcp (Eio.Net.Ipaddr.V4.loopback, port) in
  let server =
    Camelio.Server.create ~max_request_body_size ~request_body_mode ~handler ()
  in
  let response = ref None in
  (try
     Eio.Switch.run @@ fun sw ->
     Eio.Fiber.fork ~sw (fun () -> Camelio.Server.run ~sw ~net ~addr server);
     let rec connect attempts =
       Eio.Switch.run @@ fun client_sw ->
       match Eio.Net.connect ~sw:client_sw net addr with
       | flow -> f flow
       | exception _ when attempts > 0 ->
           Eio.Time.sleep clock 0.01;
           connect (attempts - 1)
     in
     response := Some (connect 100);
     Eio.Switch.fail sw Exit
   with Exit -> ());
  match !response with Some response -> response | None -> fail "no response"

let request raw flow =
  Eio.Flow.copy_string raw flow;
  Eio.Flow.shutdown flow `Send;
  let buffer = Buffer.create 128 in
  (try Eio.Flow.copy flow (Eio.Flow.buffer_sink buffer) with End_of_file -> ());
  Buffer.contents buffer

let require_network () =
  match Sys.getenv_opt "CAMELIO_RUN_NETWORK_TESTS" with
  | Some "1" -> ()
  | _ -> skip ()

let test_run_success () =
  require_network ();
  let response =
    with_server
      (fun _ -> Camelio.Response.text "ok\n")
      (request "GET / HTTP/1.1\r\n\r\n")
  in
  check bool "200" true (String.starts_with ~prefix:"HTTP/1.1 200 OK" response);
  check bool "body" true (String.ends_with ~suffix:"ok\n" response)

let test_run_post_request () =
  require_network ();
  let raw =
    String.concat ""
      [
        "POST /upload?x=1 HTTP/1.1\r\n";
        "Content-Type: text/plain\r\n";
        "Content-Length: 4\r\n";
        "\r\n";
        "ping";
      ]
  in
  let response =
    with_server
      (fun req ->
        check
          (module Camelio.Method)
          "method" Camelio.Method.POST (Camelio.Request.meth req);
        check string "target" "/upload?x=1" (Camelio.Request.target req);
        check string "path" "/upload" (Camelio.Request.path req);
        check (option string) "content-type" (Some "text/plain")
          (Camelio.Headers.get "content-type" (Camelio.Request.headers req));
        check (option string) "content-length" (Some "4")
          (Camelio.Headers.get "content-length" (Camelio.Request.headers req));
        check bool "buffered" true
          (Camelio.Body.is_buffered (Camelio.Request.body req));
        check string "body" "ping"
          (Camelio.Body.to_string (Camelio.Request.body req));
        Camelio.Response.text "ok\n")
      (request raw)
  in
  check bool
    ("200 response: " ^ response)
    true
    (String.starts_with ~prefix:"HTTP/1.1 200 OK" response)

let test_run_streaming_post_request () =
  require_network ();
  let body = String.make 5_000 'x' in
  let raw =
    String.concat ""
      [
        "POST /upload HTTP/1.1\r\n";
        "Content-Type: application/octet-stream\r\n";
        "Content-Length: ";
        string_of_int (String.length body);
        "\r\n";
        "\r\n";
        body;
      ]
  in
  let response =
    with_server ~max_request_body_size:5_000
      ~request_body_mode:Camelio.Server.Streaming
      (fun req ->
        let request_body = Camelio.Request.body req in
        check bool "streaming" false (Camelio.Body.is_buffered request_body);
        check (option string) "content-length" (Some "5000")
          (Camelio.Headers.get "content-length" (Camelio.Request.headers req));
        check_raises "streaming to_string"
          (Invalid_argument "streaming body cannot be read with Body.to_string")
          (fun () -> ignore (Camelio.Body.to_string request_body : string));
        check
          (result string (of_pp Camelio.Body.pp_error))
          "body" (Ok body)
          (Camelio.Body.to_string_limited ~max_size:5_000 request_body);
        check_raises "single consumption"
          (Invalid_argument "streaming body has already been consumed")
          (fun () ->
            ignore
              (Camelio.Body.to_string_limited ~max_size:5_000 request_body
                : (string, Camelio.Body.error) result));
        Camelio.Response.text "ok\n")
      (request raw)
  in
  check bool
    ("200 response: " ^ response)
    true
    (String.starts_with ~prefix:"HTTP/1.1 200 OK" response)

let test_run_streaming_unconsumed_body () =
  require_network ();
  let response =
    with_server ~request_body_mode:Camelio.Server.Streaming
      (fun _req -> Camelio.Response.text "ok\n")
      (request "POST / HTTP/1.1\r\nContent-Length: 4\r\n\r\nping")
  in
  check bool "200" true (String.starts_with ~prefix:"HTTP/1.1 200 OK" response)

let test_run_streaming_short_body_source_error () =
  require_network ();
  let response =
    with_server ~max_request_body_size:5
      ~request_body_mode:Camelio.Server.Streaming
      (fun req ->
        match
          Camelio.Body.with_source (Camelio.Request.body req) Eio.Flow.read_all
        with
        | _ -> Camelio.Response.text "unexpected\n"
        | exception Camelio.Body.Unexpected_end_of_body_read ->
            Camelio.Response.text ~status:Camelio.Status.bad_request "short\n")
      (request "POST / HTTP/1.1\r\nContent-Length: 5\r\n\r\nhi")
  in
  check bool
    ("400 response: " ^ response)
    true
    (String.starts_with ~prefix:"HTTP/1.1 400 Bad Request" response)

let test_run_bad_request () =
  require_network ();
  let response =
    with_server
      (fun _ -> fail "handler should not run")
      (request "GET /bad path HTTP/1.1\r\n\r\n")
  in
  check bool "400" true
    (String.starts_with ~prefix:"HTTP/1.1 400 Bad Request" response)

let test_run_bad_request_target_control () =
  require_network ();
  let response =
    with_server
      (fun _ -> fail "handler should not run")
      (request "GET /bad\tpath HTTP/1.1\r\n\r\n")
  in
  check bool "400" true
    (String.starts_with ~prefix:"HTTP/1.1 400 Bad Request" response)

let test_run_incomplete_headers_bad_request () =
  require_network ();
  let response =
    with_server
      (fun _ -> fail "handler should not run")
      (request "GET / HTTP/1.1\r\nHost: example.test\r\n")
  in
  check bool "400" true
    (String.starts_with ~prefix:"HTTP/1.1 400 Bad Request" response)

let test_run_short_body_bad_request () =
  require_network ();
  let response =
    with_server
      (fun _ -> fail "handler should not run")
      (request "POST / HTTP/1.1\r\nContent-Length: 4\r\n\r\nhi")
  in
  check bool "400" true
    (String.starts_with ~prefix:"HTTP/1.1 400 Bad Request" response)

let test_run_payload_too_large () =
  require_network ();
  let response =
    with_server
      (fun _ -> fail "handler should not run")
      (request "POST / HTTP/1.1\r\nContent-Length: 5\r\n\r\nhello")
  in
  check bool "413" true
    (String.starts_with ~prefix:"HTTP/1.1 413 Payload Too Large" response)

let test_run_streaming_payload_too_large () =
  require_network ();
  let response =
    with_server ~request_body_mode:Camelio.Server.Streaming
      (fun _ -> fail "handler should not run")
      (request "POST / HTTP/1.1\r\nContent-Length: 5\r\n\r\nhello")
  in
  check bool "413" true
    (String.starts_with ~prefix:"HTTP/1.1 413 Payload Too Large" response)

let test_run_streaming_unsupported_transfer_encoding () =
  require_network ();
  let raw =
    String.concat ""
      [
        "POST / HTTP/1.1\r\n";
        "Transfer-Encoding: chunked\r\n";
        "\r\n";
        "4\r\n";
        "ping\r\n";
        "0\r\n";
        "\r\n";
      ]
  in
  let response =
    with_server ~request_body_mode:Camelio.Server.Streaming
      (fun _ -> fail "handler should not run")
      (request raw)
  in
  check bool "400" true
    (String.starts_with ~prefix:"HTTP/1.1 400 Bad Request" response)

let multipart_request ~boundary body =
  String.concat ""
    [
      "POST /upload HTTP/1.1\r\n";
      "Content-Type: multipart/form-data; boundary=";
      boundary;
      "\r\n";
      "Content-Length: ";
      string_of_int (String.length body);
      "\r\n";
      "\r\n";
      body;
    ]

let test_run_streaming_multipart_upload () =
  require_network ();
  let boundary = "AaB03x" in
  let file_body = String.make 6_000 'u' in
  let body =
    String.concat ""
      [
        "--AaB03x\r\n";
        "Content-Disposition: form-data; name=\"title\"\r\n";
        "\r\n";
        "avatar\r\n";
        "--AaB03x\r\n";
        "Content-Disposition: form-data; name=\"file\"; \
         filename=\"avatar.bin\"\r\n";
        "Content-Type: application/octet-stream\r\n";
        "\r\n";
        file_body;
        "\r\n";
        "--AaB03x--\r\n";
      ]
  in
  let response =
    with_server ~max_request_body_size:(String.length body)
      ~request_body_mode:Camelio.Server.Streaming
      (fun req ->
        check bool "request body is streaming" false
          (Camelio.Body.is_buffered (Camelio.Request.body req));
        let title = ref None in
        let file_bytes = ref None in
        match
          Camelio.Multipart.Streaming.iter_request req
            ~on_part:(fun part source ->
              match Camelio.Multipart.Streaming.name part with
              | Some "title" -> title := Some (Eio.Flow.read_all source)
              | Some "file" ->
                  check (option string) "filename" (Some "avatar.bin")
                    (Camelio.Multipart.Streaming.filename part);
                  let scratch = Cstruct.create 257 in
                  let rec count total =
                    match Eio.Flow.single_read source scratch with
                    | exception End_of_file -> total
                    | read -> count (total + read)
                  in
                  file_bytes := Some (count 0)
              | _ ->
                  Eio.Flow.copy source (Eio.Flow.buffer_sink (Buffer.create 0)))
        with
        | Error error ->
            Camelio.Response.text ~status:Camelio.Status.bad_request
              (Format.asprintf "%a\n" Camelio.Multipart.pp_error error)
        | Ok () ->
            check (option string) "title" (Some "avatar") !title;
            check (option int) "file bytes"
              (Some (String.length file_body))
              !file_bytes;
            Camelio.Response.text "uploaded\n")
      (request (multipart_request ~boundary body))
  in
  check bool
    ("200 response: " ^ response)
    true
    (String.starts_with ~prefix:"HTTP/1.1 200 OK" response);
  check bool "body" true (String.ends_with ~suffix:"uploaded\n" response)

let test_run_streaming_multipart_malformed_body () =
  require_network ();
  let boundary = "AaB03x" in
  let handler_ran = ref false in
  let body =
    "--AaB03x\r\n\
     Content-Disposition: form-data; name=\"file\"\r\n\
     \r\n\
     missing close"
  in
  let response =
    with_server ~max_request_body_size:(String.length body)
      ~request_body_mode:Camelio.Server.Streaming
      (fun req ->
        handler_ran := true;
        match
          Camelio.Multipart.Streaming.iter_request req ~on_part:(fun _ source ->
              ignore (Eio.Flow.read_all source : string))
        with
        | Ok () -> Camelio.Response.text "unexpected\n"
        | Error error ->
            Camelio.Response.text ~status:Camelio.Status.bad_request
              (Format.asprintf "%a\n" Camelio.Multipart.pp_error error))
      (request (multipart_request ~boundary body))
  in
  check bool
    ("400 response: " ^ response)
    true
    (String.starts_with ~prefix:"HTTP/1.1 400 Bad Request" response);
  check bool "handler ran" true !handler_ran

let test_run_handler_exception () =
  require_network ();
  let response =
    with_server (fun _ -> failwith "boom") (request "GET / HTTP/1.1\r\n\r\n")
  in
  check bool "500" true
    (String.starts_with ~prefix:"HTTP/1.1 500 Internal Server Error" response)

let () =
  run "server"
    [
      ( "server",
        [
          test_case "create applies middleware" `Quick
            test_create_applies_middleware;
          test_case "default max body size" `Quick
            test_default_max_request_body_size;
          test_case "run success" `Quick test_run_success;
          test_case "run post request" `Quick test_run_post_request;
          test_case "run streaming post request" `Quick
            test_run_streaming_post_request;
          test_case "run streaming unconsumed body" `Quick
            test_run_streaming_unconsumed_body;
          test_case "run streaming short body source error" `Quick
            test_run_streaming_short_body_source_error;
          test_case "run bad request" `Quick test_run_bad_request;
          test_case "run bad request target control" `Quick
            test_run_bad_request_target_control;
          test_case "run incomplete headers bad request" `Quick
            test_run_incomplete_headers_bad_request;
          test_case "run short body bad request" `Quick
            test_run_short_body_bad_request;
          test_case "run payload too large" `Quick test_run_payload_too_large;
          test_case "run streaming payload too large" `Quick
            test_run_streaming_payload_too_large;
          test_case "run streaming unsupported transfer encoding" `Quick
            test_run_streaming_unsupported_transfer_encoding;
          test_case "run streaming multipart upload" `Quick
            test_run_streaming_multipart_upload;
          test_case "run streaming multipart malformed body" `Quick
            test_run_streaming_multipart_malformed_body;
          test_case "run handler exception" `Quick test_run_handler_exception;
        ] );
    ]
