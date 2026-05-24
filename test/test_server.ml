open Alcotest

let request =
  Choku.Request.make ~meth:Choku.Method.GET ~target:"/"
    ~headers:Choku.Headers.empty ~body:Choku.Body.empty

let test_create_applies_middleware () =
  let middleware next req =
    next req |> Choku.Response.with_header "x-middleware" "yes"
  in
  let server =
    Choku.Server.create ~middlewares:[ middleware ]
      ~handler:(fun _ -> Choku.Response.text "ok")
      ()
  in
  let response = Choku.Server.handle server request in
  check (option string) "middleware header" (Some "yes")
    (Choku.Headers.get "x-middleware" (Choku.Response.headers response))

let test_create_router_applies_middleware () =
  let middleware next req =
    next req |> Choku.Response.with_header "x-router-middleware" "yes"
  in
  let router =
    Choku.Router.empty
    |> Choku.Router.get "/" (fun _ _ -> Choku.Response.text "ok")
  in
  let server = Choku.Server.create_router ~middlewares:[ middleware ] router in
  let response = Choku.Server.handle server request in
  check (option string) "middleware header" (Some "yes")
    (Choku.Headers.get "x-router-middleware" (Choku.Response.headers response))

let test_create_router_handle_uses_existing_request_body () =
  let request =
    Choku.Request.make ~meth:Choku.Method.POST ~target:"/upload"
      ~headers:Choku.Headers.empty ~body:(Choku.Body.string "ping")
  in
  let router =
    Choku.Router.empty
    |> Choku.Router.post ~request_body_mode:Choku.Request_body_mode.Streaming
         "/upload" (fun _ req ->
           check bool "handle body remains buffered" true
             (Choku.Body.is_buffered (Choku.Request.body req));
           check string "body" "ping"
             (Choku.Body.to_string (Choku.Request.body req));
           Choku.Response.text "ok")
  in
  let server = Choku.Server.create_router router in
  let response = Choku.Server.handle server request in
  check int "status" 200 (Choku.Status.code (Choku.Response.status response))

let test_default_max_request_body_size () =
  let server =
    Choku.Server.create ~handler:(fun _ -> Choku.Response.text "ok") ()
  in
  check int "default" 1_048_576 (Choku.Server.max_request_body_size server)

let test_create_rejects_invalid_request_head_limits () =
  check_raises "invalid max request head size"
    (Invalid_argument "max_request_head_size <= 0") (fun () ->
      ignore
        (Choku.Server.create ~max_request_head_size:0
           ~handler:(fun _ -> Choku.Response.text "ok")
           ()
          : Choku.Server.t));
  check_raises "invalid request head timeout"
    (Invalid_argument "non-positive request_head_timeout") (fun () ->
      ignore
        (Choku.Server.create ~request_head_timeout:(Some 0.0)
           ~handler:(fun _ -> Choku.Response.text "ok")
           ()
          : Choku.Server.t))

let with_running_server ?mono_clock server f =
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
  let response = ref None in
  (try
     Eio.Switch.run @@ fun sw ->
     Eio.Fiber.fork ~sw (fun () ->
         Choku.Server.run ~sw ~net ?mono_clock ~addr server);
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

let with_server ?(max_request_body_size = 4) ?max_request_head_size
    ?request_head_timeout ?mono_clock
    ?(request_body_mode = Choku.Server.Buffered) handler f =
  let server =
    Choku.Server.create ?max_request_head_size ?request_head_timeout
      ~max_request_body_size ~request_body_mode ~handler ()
  in
  with_running_server ?mono_clock server f

let with_router_server ?(max_request_body_size = 4) ?max_request_head_size
    ?request_head_timeout ?mono_clock router f =
  let server =
    Choku.Server.create_router ?max_request_head_size ?request_head_timeout
      ~max_request_body_size router
  in
  with_running_server ?mono_clock server f

let request raw flow =
  Eio.Flow.copy_string raw flow;
  Eio.Flow.shutdown flow `Send;
  let buffer = Buffer.create 128 in
  (try Eio.Flow.copy flow (Eio.Flow.buffer_sink buffer) with End_of_file -> ());
  Buffer.contents buffer

let require_network () =
  match Sys.getenv_opt "CHOKU_RUN_NETWORK_TESTS" with
  | Some "1" -> ()
  | _ -> skip ()

let test_run_success () =
  require_network ();
  let response =
    with_server
      (fun _ -> Choku.Response.text "ok\n")
      (request "GET / HTTP/1.1\r\nHost: example.test\r\n\r\n")
  in
  check bool "200" true (String.starts_with ~prefix:"HTTP/1.1 200 OK" response);
  check bool "body" true (String.ends_with ~suffix:"ok\n" response)

let test_run_head_suppresses_response_body () =
  require_network ();
  let response =
    with_server
      (fun _ -> Choku.Response.text "hello")
      (request "HEAD / HTTP/1.1\r\nHost: example.test\r\n\r\n")
  in
  check string "wire"
    "HTTP/1.1 200 OK\r\n\
     content-type: text/plain; charset=utf-8\r\n\
     content-length: 5\r\n\
     connection: close\r\n\
     \r\n"
    response

let test_run_post_request () =
  require_network ();
  let raw =
    String.concat ""
      [
        "POST /upload?x=1 HTTP/1.1\r\n";
        "Host: example.test\r\n";
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
          (module Choku.Method)
          "method" Choku.Method.POST (Choku.Request.meth req);
        check string "target" "/upload?x=1" (Choku.Request.target req);
        check string "path" "/upload" (Choku.Request.path req);
        check (option string) "content-type" (Some "text/plain")
          (Choku.Headers.get "content-type" (Choku.Request.headers req));
        check (option string) "content-length" (Some "4")
          (Choku.Headers.get "content-length" (Choku.Request.headers req));
        check bool "buffered" true
          (Choku.Body.is_buffered (Choku.Request.body req));
        check string "body" "ping"
          (Choku.Body.to_string (Choku.Request.body req));
        Choku.Response.text "ok\n")
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
        "Host: example.test\r\n";
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
      ~request_body_mode:Choku.Server.Streaming
      (fun req ->
        let request_body = Choku.Request.body req in
        check bool "streaming" false (Choku.Body.is_buffered request_body);
        check (option string) "content-length" (Some "5000")
          (Choku.Headers.get "content-length" (Choku.Request.headers req));
        check_raises "streaming to_string"
          (Invalid_argument "streaming body cannot be read with Body.to_string")
          (fun () -> ignore (Choku.Body.to_string request_body : string));
        check
          (result string (of_pp Choku.Body.pp_error))
          "body" (Ok body)
          (Choku.Body.to_string_limited ~max_size:5_000 request_body);
        check_raises "single consumption"
          (Invalid_argument "streaming body has already been consumed")
          (fun () ->
            ignore
              (Choku.Body.to_string_limited ~max_size:5_000 request_body
                : (string, Choku.Body.error) result));
        Choku.Response.text "ok\n")
      (request raw)
  in
  check bool
    ("200 response: " ^ response)
    true
    (String.starts_with ~prefix:"HTTP/1.1 200 OK" response)

let test_run_streaming_unconsumed_body () =
  require_network ();
  let response =
    with_server ~request_body_mode:Choku.Server.Streaming
      (fun _req -> Choku.Response.text "ok\n")
      (request
         "POST / HTTP/1.1\r\n\
          Host: example.test\r\n\
          Content-Length: 4\r\n\
          \r\n\
          ping")
  in
  check bool "200" true (String.starts_with ~prefix:"HTTP/1.1 200 OK" response)

let test_run_streaming_short_body_source_error () =
  require_network ();
  let response =
    with_server ~max_request_body_size:5
      ~request_body_mode:Choku.Server.Streaming
      (fun req ->
        match
          Choku.Body.with_source (Choku.Request.body req) Eio.Flow.read_all
        with
        | _ -> Choku.Response.text "unexpected\n"
        | exception Choku.Body.Unexpected_end_of_body_read ->
            Choku.Response.text ~status:Choku.Status.bad_request "short\n")
      (request
         "POST / HTTP/1.1\r\nHost: example.test\r\nContent-Length: 5\r\n\r\nhi")
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
      (request "GET /bad path HTTP/1.1\r\nHost: example.test\r\n\r\n")
  in
  check bool "400" true
    (String.starts_with ~prefix:"HTTP/1.1 400 Bad Request" response)

let test_run_bad_request_target_control () =
  require_network ();
  let response =
    with_server
      (fun _ -> fail "handler should not run")
      (request "GET /bad\tpath HTTP/1.1\r\nHost: example.test\r\n\r\n")
  in
  check bool "400" true
    (String.starts_with ~prefix:"HTTP/1.1 400 Bad Request" response)

let test_run_missing_host_bad_request () =
  require_network ();
  let handler_ran = ref false in
  let response =
    with_server
      (fun _ ->
        handler_ran := true;
        Choku.Response.text "unexpected\n")
      (request "GET / HTTP/1.1\r\n\r\n")
  in
  check bool "400" true
    (String.starts_with ~prefix:"HTTP/1.1 400 Bad Request" response);
  check bool "handler not run" false !handler_ran

let test_run_duplicate_host_bad_request () =
  require_network ();
  let handler_ran = ref false in
  let response =
    with_server
      (fun _ ->
        handler_ran := true;
        Choku.Response.text "unexpected\n")
      (request
         "GET / HTTP/1.1\r\nHost: example.test\r\nHost: other.test\r\n\r\n")
  in
  check bool "400" true
    (String.starts_with ~prefix:"HTTP/1.1 400 Bad Request" response);
  check bool "handler not run" false !handler_ran

let test_run_rejects_fragment_target_before_body_limit () =
  require_network ();
  let handler_ran = ref false in
  let response =
    with_server
      (fun _ ->
        handler_ran := true;
        Choku.Response.text "unexpected\n")
      (request
         "POST /bad#fragment HTTP/1.1\r\n\
          Host: example.test\r\n\
          Content-Length: 5\r\n\
          \r\n\
          hello")
  in
  check bool "400" true
    (String.starts_with ~prefix:"HTTP/1.1 400 Bad Request" response);
  check bool "handler not run" false !handler_ran

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
      (request
         "POST / HTTP/1.1\r\nHost: example.test\r\nContent-Length: 4\r\n\r\nhi")
  in
  check bool "400" true
    (String.starts_with ~prefix:"HTTP/1.1 400 Bad Request" response)

let test_run_payload_too_large () =
  require_network ();
  let response =
    with_server
      (fun _ -> fail "handler should not run")
      (request
         "POST / HTTP/1.1\r\n\
          Host: example.test\r\n\
          Content-Length: 5\r\n\
          \r\n\
          hello")
  in
  check bool "413" true
    (String.starts_with ~prefix:"HTTP/1.1 413 Payload Too Large" response)

let test_run_streaming_payload_too_large () =
  require_network ();
  let response =
    with_server ~request_body_mode:Choku.Server.Streaming
      (fun _ -> fail "handler should not run")
      (request
         "POST / HTTP/1.1\r\n\
          Host: example.test\r\n\
          Content-Length: 5\r\n\
          \r\n\
          hello")
  in
  check bool "413" true
    (String.starts_with ~prefix:"HTTP/1.1 413 Payload Too Large" response)

let test_run_streaming_unsupported_transfer_encoding () =
  require_network ();
  let raw =
    String.concat ""
      [
        "POST / HTTP/1.1\r\n";
        "Host: example.test\r\n";
        "Transfer-Encoding: chunked\r\n";
        "\r\n";
        "4\r\n";
        "ping\r\n";
        "0\r\n";
        "\r\n";
      ]
  in
  let response =
    with_server ~request_body_mode:Choku.Server.Streaming
      (fun _ -> fail "handler should not run")
      (request raw)
  in
  check bool "400" true
    (String.starts_with ~prefix:"HTTP/1.1 400 Bad Request" response)

let test_run_rejects_transfer_encoding_content_length_smuggling () =
  require_network ();
  let handler_ran = ref false in
  let raw =
    String.concat ""
      [
        "POST / HTTP/1.1\r\n";
        "Host: example.test\r\n";
        "Transfer-Encoding: chunked\r\n";
        "Content-Length: 4\r\n";
        "\r\n";
        "4\r\n";
        "ping\r\n";
        "0\r\n";
        "\r\n";
      ]
  in
  let response =
    with_server
      (fun _ ->
        handler_ran := true;
        Choku.Response.text "unexpected\n")
      (request raw)
  in
  check bool "400" true
    (String.starts_with ~prefix:"HTTP/1.1 400 Bad Request" response);
  check bool "handler not run" false !handler_ran

let test_run_rejects_malformed_folded_header () =
  require_network ();
  let handler_ran = ref false in
  let response =
    with_server
      (fun _ ->
        handler_ran := true;
        Choku.Response.text "unexpected\n")
      (request "GET / HTTP/1.1\r\nHost: example.test\r\n folded: yes\r\n\r\n")
  in
  check bool "400" true
    (String.starts_with ~prefix:"HTTP/1.1 400 Bad Request" response);
  check bool "handler not run" false !handler_ran

let test_run_rejects_large_request_head () =
  require_network ();
  let handler_ran = ref false in
  let response =
    with_server ~max_request_head_size:32
      (fun _ ->
        handler_ran := true;
        Choku.Response.text "unexpected\n")
      (request
         "GET / HTTP/1.1\r\n\
          Host: example.test\r\n\
          X-Long: 012345678901234567890123456789\r\n\
          \r\n")
  in
  check bool "431" true
    (String.starts_with ~prefix:"HTTP/1.1 431 Request Header Fields Too Large"
       response);
  check bool "handler not run" false !handler_ran

let test_run_large_request_head_at_limit () =
  require_network ();
  let raw = "GET / HTTP/1.1\r\nHost: example.test\r\nX-Test: ok\r\n\r\n" in
  let response =
    with_server ~max_request_head_size:(String.length raw)
      (fun _ -> Choku.Response.text "ok\n")
      (request raw)
  in
  check bool "200" true (String.starts_with ~prefix:"HTTP/1.1 200 OK" response)

let test_run_request_head_limit_ignores_buffered_body_prefix () =
  require_network ();
  let head =
    "POST / HTTP/1.1\r\nHost: example.test\r\nContent-Length: 4\r\n\r\n"
  in
  let response =
    with_server ~max_request_head_size:(String.length head)
      (fun req ->
        check string "body" "ping"
          (Choku.Body.to_string (Choku.Request.body req));
        Choku.Response.text "ok\n")
      (request (head ^ "ping"))
  in
  check bool "200" true (String.starts_with ~prefix:"HTTP/1.1 200 OK" response)

let test_run_rejects_request_head_timeout () =
  require_network ();
  Eio_main.run @@ fun env ->
  let net = Eio.Stdenv.net env in
  let mono_clock = Eio.Stdenv.mono_clock env in
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
  let handler_ran = ref false in
  let server =
    Choku.Server.create ~request_head_timeout:(Some 0.02)
      ~handler:(fun _ ->
        handler_ran := true;
        Choku.Response.text "unexpected\n")
      ()
  in
  let response = ref None in
  (try
     Eio.Switch.run @@ fun sw ->
     Eio.Fiber.fork ~sw (fun () ->
         Choku.Server.run ~sw ~net ~mono_clock ~addr server);
     let rec connect attempts =
       Eio.Switch.run @@ fun client_sw ->
       match Eio.Net.connect ~sw:client_sw net addr with
       | flow ->
           Eio.Flow.copy_string "GET / HTTP/1.1\r\nHost: example.test" flow;
           Eio.Time.sleep clock 0.05;
           let buffer = Buffer.create 128 in
           (try Eio.Flow.copy flow (Eio.Flow.buffer_sink buffer)
            with End_of_file -> ());
           Buffer.contents buffer
       | exception _ when attempts > 0 ->
           Eio.Time.sleep clock 0.01;
           connect (attempts - 1)
     in
     response := Some (connect 100);
     Eio.Switch.fail sw Exit
   with Exit -> ());
  let response =
    match !response with
    | Some response -> response
    | None -> fail "no response"
  in
  check bool "408" true
    (String.starts_with ~prefix:"HTTP/1.1 408 Request Timeout" response);
  check bool "handler not run" false !handler_ran

let test_run_request_head_timeout_does_not_cover_body () =
  require_network ();
  Eio_main.run @@ fun env ->
  let net = Eio.Stdenv.net env in
  let mono_clock = Eio.Stdenv.mono_clock env in
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
    Choku.Server.create ~max_request_body_size:4
      ~request_head_timeout:(Some 0.02)
      ~handler:(fun req ->
        check string "body" "ping"
          (Choku.Body.to_string (Choku.Request.body req));
        Choku.Response.text "ok\n")
      ()
  in
  let response = ref None in
  (try
     Eio.Switch.run @@ fun sw ->
     Eio.Fiber.fork ~sw (fun () ->
         Choku.Server.run ~sw ~net ~mono_clock ~addr server);
     let rec connect attempts =
       Eio.Switch.run @@ fun client_sw ->
       match Eio.Net.connect ~sw:client_sw net addr with
       | flow ->
           Eio.Flow.copy_string
             "POST / HTTP/1.1\r\n\
              Host: example.test\r\n\
              Content-Length: 4\r\n\
              \r\n"
             flow;
           Eio.Time.sleep clock 0.05;
           Eio.Flow.copy_string "ping" flow;
           Eio.Flow.shutdown flow `Send;
           let buffer = Buffer.create 128 in
           (try Eio.Flow.copy flow (Eio.Flow.buffer_sink buffer)
            with End_of_file -> ());
           Buffer.contents buffer
       | exception _ when attempts > 0 ->
           Eio.Time.sleep clock 0.01;
           connect (attempts - 1)
     in
     response := Some (connect 100);
     Eio.Switch.fail sw Exit
   with Exit -> ());
  let response =
    match !response with
    | Some response -> response
    | None -> fail "no response"
  in
  check bool "200" true (String.starts_with ~prefix:"HTTP/1.1 200 OK" response)

let test_run_requires_mono_clock_for_request_head_timeout () =
  require_network ();
  let server =
    Choku.Server.create ~request_head_timeout:(Some 1.0)
      ~handler:(fun _ -> Choku.Response.text "ok\n")
      ()
  in
  Eio_main.run @@ fun env ->
  let net = Eio.Stdenv.net env in
  Eio.Switch.run @@ fun sw ->
  check_raises "missing mono_clock"
    (Invalid_argument "request_head_timeout requires Server.run ~mono_clock")
    (fun () ->
      Choku.Server.run ~sw ~net
        ~addr:(`Tcp (Eio.Net.Ipaddr.V4.loopback, 0))
        server)

let test_run_streaming_body_is_capped_to_content_length () =
  require_network ();
  let response =
    with_server ~request_body_mode:Choku.Server.Streaming
      (fun req ->
        check
          (result string (of_pp Choku.Body.pp_error))
          "body" (Ok "ping")
          (Choku.Body.to_string_limited ~max_size:4 (Choku.Request.body req));
        Choku.Response.text "ok\n")
      (request
         "POST / HTTP/1.1\r\n\
          Host: example.test\r\n\
          Content-Length: 4\r\n\
          \r\n\
          pingGET /evil")
  in
  check bool "200" true (String.starts_with ~prefix:"HTTP/1.1 200 OK" response)

let test_run_router_buffered_route () =
  require_network ();
  let router =
    Choku.Router.empty
    |> Choku.Router.post "/buffered" (fun _ req ->
        let body = Choku.Request.body req in
        check bool "buffered" true (Choku.Body.is_buffered body);
        check string "body" "ping" (Choku.Body.to_string body);
        Choku.Response.text "buffered\n")
  in
  let response =
    with_router_server router
      (request
         "POST /buffered HTTP/1.1\r\n\
          Host: example.test\r\n\
          Content-Length: 4\r\n\
          \r\n\
          ping")
  in
  check bool
    ("200 response: " ^ response)
    true
    (String.starts_with ~prefix:"HTTP/1.1 200 OK" response);
  check bool "body" true (String.ends_with ~suffix:"buffered\n" response)

let test_run_router_streaming_route () =
  require_network ();
  let body = String.make 5_000 'x' in
  let router =
    Choku.Router.empty
    |> Choku.Router.post ~request_body_mode:Choku.Request_body_mode.Streaming
         "/streaming" (fun _ req ->
           let request_body = Choku.Request.body req in
           check bool "streaming" false (Choku.Body.is_buffered request_body);
           check
             (result string (of_pp Choku.Body.pp_error))
             "body" (Ok body)
             (Choku.Body.to_string_limited ~max_size:5_000 request_body);
           Choku.Response.text "streaming\n")
  in
  let raw =
    String.concat ""
      [
        "POST /streaming HTTP/1.1\r\n";
        "Host: example.test\r\n";
        "Content-Length: ";
        string_of_int (String.length body);
        "\r\n";
        "\r\n";
        body;
      ]
  in
  let response =
    with_router_server ~max_request_body_size:5_000 router (request raw)
  in
  check bool
    ("200 response: " ^ response)
    true
    (String.starts_with ~prefix:"HTTP/1.1 200 OK" response);
  check bool "body" true (String.ends_with ~suffix:"streaming\n" response)

let test_run_router_unmatched_body_too_large () =
  require_network ();
  let not_found_ran = ref false in
  let router =
    Choku.Router.empty
    |> Choku.Router.not_found (fun _ ->
        not_found_ran := true;
        Choku.Response.text ~status:Choku.Status.not_found "missing\n")
  in
  let response =
    with_router_server router
      (request
         "POST /missing HTTP/1.1\r\n\
          Host: example.test\r\n\
          Content-Length: 5\r\n\
          \r\n\
          hello")
  in
  check bool "413" true
    (String.starts_with ~prefix:"HTTP/1.1 413 Payload Too Large" response);
  check bool "not found not run" false !not_found_ran

let test_run_router_does_not_preinvoke_route_handler () =
  require_network ();
  let handler_started = ref 0 in
  let router =
    Choku.Router.empty
    |> Choku.Router.post ~request_body_mode:Choku.Request_body_mode.Streaming
         "/upload" (fun _params ->
           incr handler_started;
           fun req ->
             check
               (result string (of_pp Choku.Body.pp_error))
               "body" (Ok "ping")
               (Choku.Body.to_string_limited ~max_size:4
                  (Choku.Request.body req));
             Choku.Response.text "ok\n")
  in
  let response =
    with_router_server router
      (request
         "POST /upload HTTP/1.1\r\n\
          Host: example.test\r\n\
          Content-Length: 4\r\n\
          \r\n\
          ping")
  in
  check bool "200" true (String.starts_with ~prefix:"HTTP/1.1 200 OK" response);
  check int "handler invoked once" 1 !handler_started

let multipart_request ~boundary body =
  String.concat ""
    [
      "POST /upload HTTP/1.1\r\n";
      "Host: example.test\r\n";
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
      ~request_body_mode:Choku.Server.Streaming
      (fun req ->
        check bool "request body is streaming" false
          (Choku.Body.is_buffered (Choku.Request.body req));
        let title = ref None in
        let file_bytes = ref None in
        match
          Choku.Multipart.Streaming.iter_request req
            ~on_part:(fun part source ->
              match Choku.Multipart.Streaming.name part with
              | Some "title" -> title := Some (Eio.Flow.read_all source)
              | Some "file" ->
                  check (option string) "filename" (Some "avatar.bin")
                    (Choku.Multipart.Streaming.filename part);
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
            Choku.Response.text ~status:Choku.Status.bad_request
              (Format.asprintf "%a\n" Choku.Multipart.pp_error error)
        | Ok () ->
            check (option string) "title" (Some "avatar") !title;
            check (option int) "file bytes"
              (Some (String.length file_body))
              !file_bytes;
            Choku.Response.text "uploaded\n")
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
      ~request_body_mode:Choku.Server.Streaming
      (fun req ->
        handler_ran := true;
        match
          Choku.Multipart.Streaming.iter_request req ~on_part:(fun _ source ->
              ignore (Eio.Flow.read_all source : string))
        with
        | Ok () -> Choku.Response.text "unexpected\n"
        | Error error ->
            Choku.Response.text ~status:Choku.Status.bad_request
              (Format.asprintf "%a\n" Choku.Multipart.pp_error error))
      (request (multipart_request ~boundary body))
  in
  check bool
    ("400 response: " ^ response)
    true
    (String.starts_with ~prefix:"HTTP/1.1 400 Bad Request" response);
  check bool "handler ran" true !handler_ran

let test_run_router_streaming_multipart_upload () =
  require_network ();
  let boundary = "AaB03x" in
  let file_body = String.make 6_000 'r' in
  let body =
    String.concat ""
      [
        "--AaB03x\r\n";
        "Content-Disposition: form-data; name=\"file\"; \
         filename=\"router.bin\"\r\n";
        "Content-Type: application/octet-stream\r\n";
        "\r\n";
        file_body;
        "\r\n";
        "--AaB03x--\r\n";
      ]
  in
  let router =
    Choku.Router.empty
    |> Choku.Router.get "/health" (fun _ req ->
        check bool "health body is buffered" true
          (Choku.Body.is_buffered (Choku.Request.body req));
        Choku.Response.text "ok\n")
    |> Choku.Router.post ~request_body_mode:Choku.Request_body_mode.Streaming
         "/upload" (fun _ req ->
           check bool "request body is streaming" false
             (Choku.Body.is_buffered (Choku.Request.body req));
           let file_bytes = ref None in
           match
             Choku.Multipart.Streaming.iter_request req
               ~on_part:(fun part source ->
                 match Choku.Multipart.Streaming.filename part with
                 | Some "router.bin" ->
                     file_bytes :=
                       Some (String.length (Eio.Flow.read_all source))
                 | _ ->
                     Eio.Flow.copy source
                       (Eio.Flow.buffer_sink (Buffer.create 0)))
           with
           | Error error ->
               Choku.Response.text ~status:Choku.Status.bad_request
                 (Format.asprintf "%a\n" Choku.Multipart.pp_error error)
           | Ok () ->
               check (option int) "file bytes"
                 (Some (String.length file_body))
                 !file_bytes;
               Choku.Response.text "uploaded\n")
  in
  let health =
    with_router_server ~max_request_body_size:(String.length body) router
      (request "GET /health HTTP/1.1\r\nHost: example.test\r\n\r\n")
  in
  check bool "health 200" true
    (String.starts_with ~prefix:"HTTP/1.1 200 OK" health);
  let upload =
    with_router_server ~max_request_body_size:(String.length body) router
      (request (multipart_request ~boundary body))
  in
  check bool
    ("upload 200 response: " ^ upload)
    true
    (String.starts_with ~prefix:"HTTP/1.1 200 OK" upload);
  check bool "upload body" true (String.ends_with ~suffix:"uploaded\n" upload)

let test_run_handler_exception () =
  require_network ();
  let response =
    with_server
      (fun _ -> failwith "boom")
      (request "GET / HTTP/1.1\r\nHost: example.test\r\n\r\n")
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
          test_case "create router applies middleware" `Quick
            test_create_router_applies_middleware;
          test_case "create router handle uses existing request body" `Quick
            test_create_router_handle_uses_existing_request_body;
          test_case "default max body size" `Quick
            test_default_max_request_body_size;
          test_case "create rejects invalid request head limits" `Quick
            test_create_rejects_invalid_request_head_limits;
          test_case "run success" `Quick test_run_success;
          test_case "run HEAD suppresses response body" `Quick
            test_run_head_suppresses_response_body;
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
          test_case "run missing Host bad request" `Quick
            test_run_missing_host_bad_request;
          test_case "run duplicate Host bad request" `Quick
            test_run_duplicate_host_bad_request;
          test_case "run rejects fragment target before body limit" `Quick
            test_run_rejects_fragment_target_before_body_limit;
          test_case "run incomplete headers bad request" `Quick
            test_run_incomplete_headers_bad_request;
          test_case "run short body bad request" `Quick
            test_run_short_body_bad_request;
          test_case "run payload too large" `Quick test_run_payload_too_large;
          test_case "run streaming payload too large" `Quick
            test_run_streaming_payload_too_large;
          test_case "run streaming unsupported transfer encoding" `Quick
            test_run_streaming_unsupported_transfer_encoding;
          test_case "run rejects transfer-encoding content-length smuggling"
            `Quick test_run_rejects_transfer_encoding_content_length_smuggling;
          test_case "run rejects malformed folded header" `Quick
            test_run_rejects_malformed_folded_header;
          test_case "run rejects large request head" `Quick
            test_run_rejects_large_request_head;
          test_case "run large request head at limit" `Quick
            test_run_large_request_head_at_limit;
          test_case "run request head limit ignores buffered body prefix" `Quick
            test_run_request_head_limit_ignores_buffered_body_prefix;
          test_case "run rejects request head timeout" `Quick
            test_run_rejects_request_head_timeout;
          test_case "run request head timeout does not cover body" `Quick
            test_run_request_head_timeout_does_not_cover_body;
          test_case "run requires mono clock for request head timeout" `Quick
            test_run_requires_mono_clock_for_request_head_timeout;
          test_case "run streaming body is capped to content-length" `Quick
            test_run_streaming_body_is_capped_to_content_length;
          test_case "run router buffered route" `Quick
            test_run_router_buffered_route;
          test_case "run router streaming route" `Quick
            test_run_router_streaming_route;
          test_case "run router unmatched body too large" `Quick
            test_run_router_unmatched_body_too_large;
          test_case "run router does not preinvoke route handler" `Quick
            test_run_router_does_not_preinvoke_route_handler;
          test_case "run streaming multipart upload" `Quick
            test_run_streaming_multipart_upload;
          test_case "run streaming multipart malformed body" `Quick
            test_run_streaming_multipart_malformed_body;
          test_case "run router streaming multipart upload" `Quick
            test_run_router_streaming_multipart_upload;
          test_case "run handler exception" `Quick test_run_handler_exception;
        ] );
    ]
