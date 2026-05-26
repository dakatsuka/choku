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
    |> Choku.Router.get "/" (fun _ctx -> Choku.Response.text "ok")
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
         "/upload" (fun ctx ->
           check bool "handle body remains buffered" true
             (Choku.Body.is_buffered (Choku.Request.body ctx.request));
           check string "body" "ping"
             (Choku.Body.to_string (Choku.Request.body ctx.request));
           Choku.Response.text "ok")
  in
  let server = Choku.Server.create_router router in
  let response = Choku.Server.handle server request in
  check int "status" 200 (Choku.Status.code (Choku.Response.status response))

let test_create_with_request_body_selector_handle_uses_existing_request_body ()
    =
  let selector_calls = ref 0 in
  let server =
    Choku.Server.create_with_request_body_selector
      ~request_body_mode:(fun _ ->
        incr selector_calls;
        Choku.Request_body_mode.Streaming)
      ~handler:(fun request ->
        check bool "request body is buffered" true
          (Choku.Body.is_buffered (Choku.Request.body request));
        Choku.Response.text
          (Choku.Body.to_string (Choku.Request.body request) ^ "\n"))
      ()
  in
  let request =
    Choku.Request.make ~meth:Choku.Method.POST ~target:"/upload"
      ~headers:Choku.Headers.empty
      ~body:(Choku.Body.string "already built")
  in
  let response = Choku.Server.handle server request in
  check int "selector calls" 0 !selector_calls;
  check string "body" "already built\n"
    (Choku.Response.body response |> Choku.Body.to_string)

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
    ?request_head_timeout ?mono_clock ?keep_alive
    ?(request_body_mode = Choku.Server.Buffered) handler f =
  let server =
    Choku.Server.create ?keep_alive ?max_request_head_size ?request_head_timeout
      ~max_request_body_size ~request_body_mode ~handler ()
  in
  with_running_server ?mono_clock server f

let with_router_server ?(max_request_body_size = 4) ?max_request_head_size
    ?request_head_timeout ?mono_clock ?keep_alive router f =
  let server =
    Choku.Server.create_router ?keep_alive ?max_request_head_size
      ?request_head_timeout ~max_request_body_size router
  in
  with_running_server ?mono_clock server f

let with_selector_server ?(max_request_body_size = 4) ?max_request_head_size
    ?request_head_timeout ?mono_clock ?keep_alive ~request_body_mode handler f =
  let server =
    Choku.Server.create_with_request_body_selector ?keep_alive
      ?max_request_head_size ?request_head_timeout ~max_request_body_size
      ~request_body_mode ~handler ()
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

type response_reader = {
  flow : Eio.Flow.source_ty Eio.Resource.t;
  mutable buffered : string;
}

let response_reader flow =
  { flow :> Eio.Flow.source_ty Eio.Resource.t; buffered = "" }

let take_from_reader reader length =
  if String.length reader.buffered >= length then (
    let taken = String.sub reader.buffered 0 length in
    reader.buffered <-
      String.sub reader.buffered length (String.length reader.buffered - length);
    taken)
  else
    let prefix = reader.buffered in
    reader.buffered <- "";
    let remaining = length - String.length prefix in
    let exact = Cstruct.create remaining in
    Eio.Flow.read_exact reader.flow exact;
    prefix ^ Cstruct.to_string exact

let find_header_end raw =
  let len = String.length raw in
  let rec loop index =
    if index + 3 >= len then None
    else if
      Char.equal raw.[index] '\r'
      && Char.equal raw.[index + 1] '\n'
      && Char.equal raw.[index + 2] '\r'
      && Char.equal raw.[index + 3] '\n'
    then Some index
    else loop (index + 1)
  in
  loop 0

let read_until_header_end reader =
  let scratch = Cstruct.create 128 in
  let rec loop () =
    match find_header_end reader.buffered with
    | Some header_end ->
        let head_end = header_end + 4 in
        let head = String.sub reader.buffered 0 head_end in
        reader.buffered <-
          String.sub reader.buffered head_end
            (String.length reader.buffered - head_end);
        head
    | None ->
        let read = Eio.Flow.single_read reader.flow scratch in
        reader.buffered <-
          reader.buffered ^ Cstruct.to_string (Cstruct.sub scratch 0 read);
        loop ()
  in
  loop ()

let response_content_length head =
  head |> String.split_on_char '\n'
  |> List.find_map (fun line ->
      let line =
        if
          String.length line > 0
          && Char.equal line.[String.length line - 1] '\r'
        then String.sub line 0 (String.length line - 1)
        else line
      in
      match String.index_opt line ':' with
      | None -> None
      | Some index ->
          let name = String.sub line 0 index |> String.lowercase_ascii in
          if String.equal name "content-length" then
            Some
              (String.sub line (index + 1) (String.length line - index - 1)
              |> String.trim |> int_of_string)
          else None)
  |> Option.value ~default:0

let response_is_chunked head =
  head |> String.split_on_char '\n'
  |> List.exists (fun line ->
      let line =
        if
          String.length line > 0
          && Char.equal line.[String.length line - 1] '\r'
        then String.sub line 0 (String.length line - 1)
        else line
      in
      match String.index_opt line ':' with
      | None -> false
      | Some index ->
          let name = String.sub line 0 index |> String.lowercase_ascii in
          let value =
            String.sub line (index + 1) (String.length line - index - 1)
            |> String.trim |> String.lowercase_ascii
          in
          String.equal name "transfer-encoding" && String.equal value "chunked")

let take_until_crlf reader =
  let rec loop () =
    match String.index_opt reader.buffered '\n' with
    | Some index ->
        let line_end = index + 1 in
        let line = String.sub reader.buffered 0 line_end in
        reader.buffered <-
          String.sub reader.buffered line_end
            (String.length reader.buffered - line_end);
        line
    | None ->
        let scratch = Cstruct.create 128 in
        let read = Eio.Flow.single_read reader.flow scratch in
        reader.buffered <-
          reader.buffered ^ Cstruct.to_string (Cstruct.sub scratch 0 read);
        loop ()
  in
  loop ()

let read_chunked_body reader =
  let buffer = Buffer.create 128 in
  let rec loop () =
    let size_line = take_until_crlf reader in
    Buffer.add_string buffer size_line;
    let size_text =
      String.sub size_line 0 (String.length size_line - 2)
      |> String.split_on_char ';' |> List.hd |> String.trim
    in
    let size = int_of_string ("0x" ^ size_text) in
    if size = 0 then
      let trailer_end = take_from_reader reader 2 in
      Buffer.add_string buffer trailer_end
    else
      let chunk = take_from_reader reader (size + 2) in
      Buffer.add_string buffer chunk;
      loop ()
  in
  loop ();
  Buffer.contents buffer

let read_response ?(include_body = true) reader =
  let head = read_until_header_end reader in
  if include_body && response_is_chunked head then
    head ^ read_chunked_body reader
  else if include_body then
    let body = take_from_reader reader (response_content_length head) in
    head ^ body
  else head

let contains_sub ~needle haystack =
  let needle_len = String.length needle in
  let haystack_len = String.length haystack in
  let rec loop index =
    if index + needle_len > haystack_len then false
    else if String.equal (String.sub haystack index needle_len) needle then true
    else loop (index + 1)
  in
  loop 0

let test_run_success () =
  require_network ();
  let response =
    with_server
      (fun _ -> Choku.Response.text "ok\n")
      (request "GET / HTTP/1.1\r\nHost: example.test\r\n\r\n")
  in
  check bool "200" true (String.starts_with ~prefix:"HTTP/1.1 200 OK" response);
  check bool "body" true (String.ends_with ~suffix:"ok\n" response)

let test_run_keep_alive_two_gets () =
  require_network ();
  let response =
    with_server
      (fun req -> Choku.Response.text (Choku.Request.path req ^ "\n"))
      (fun flow ->
        let reader = response_reader flow in
        Eio.Flow.copy_string "GET /one HTTP/1.1\r\nHost: example.test\r\n\r\n"
          flow;
        let first = read_response reader in
        Eio.Flow.copy_string "GET /two HTTP/1.1\r\nHost: example.test\r\n\r\n"
          flow;
        let second = read_response reader in
        Eio.Flow.shutdown flow `Send;
        first ^ second)
  in
  check bool "first response" true
    (contains_sub ~needle:"connection: keep-alive\r\n\r\n/one\n" response);
  check bool "second response" true (String.ends_with ~suffix:"/two\n" response)

let test_run_keep_alive_pipelined_gets () =
  require_network ();
  let response =
    with_server
      (fun req -> Choku.Response.text (Choku.Request.path req ^ "\n"))
      (fun flow ->
        let reader = response_reader flow in
        Eio.Flow.copy_string
          "GET /one HTTP/1.1\r\n\
           Host: example.test\r\n\
           \r\n\
           GET /two HTTP/1.1\r\n\
           Host: example.test\r\n\
           \r\n"
          flow;
        let first = read_response reader in
        let second = read_response reader in
        Eio.Flow.shutdown flow `Send;
        first ^ second)
  in
  check bool "first response" true
    (contains_sub ~needle:"connection: keep-alive\r\n\r\n/one\n" response);
  check bool "second response" true (String.ends_with ~suffix:"/two\n" response)

let test_run_keep_alive_fixed_post_then_get () =
  require_network ();
  let response =
    with_server ~max_request_body_size:4
      (fun req ->
        if Choku.Method.equal (Choku.Request.meth req) Choku.Method.POST then
          Choku.Response.text
            (Choku.Body.to_string (Choku.Request.body req) ^ "\n")
        else Choku.Response.text "next\n")
      (fun flow ->
        let reader = response_reader flow in
        Eio.Flow.copy_string
          "POST / HTTP/1.1\r\n\
           Host: example.test\r\n\
           Content-Length: 4\r\n\
           \r\n\
           pingGET /next HTTP/1.1\r\n\
           Host: example.test\r\n\
           \r\n"
          flow;
        let first = read_response reader in
        let second = read_response reader in
        Eio.Flow.shutdown flow `Send;
        first ^ second)
  in
  check bool "post response" true
    (contains_sub ~needle:"connection: keep-alive\r\n\r\nping\n" response);
  check bool "next response" true (String.ends_with ~suffix:"next\n" response)

let test_run_keep_alive_chunked_post_then_get () =
  require_network ();
  let response =
    with_server ~max_request_body_size:4
      (fun req ->
        if Choku.Method.equal (Choku.Request.meth req) Choku.Method.POST then
          Choku.Response.text
            (Choku.Body.to_string (Choku.Request.body req) ^ "\n")
        else Choku.Response.text "next\n")
      (fun flow ->
        let reader = response_reader flow in
        Eio.Flow.copy_string
          "POST / HTTP/1.1\r\n\
           Host: example.test\r\n\
           Transfer-Encoding: chunked\r\n\
           \r\n\
           4\r\n\
           ping\r\n\
           0\r\n\
           \r\n\
           GET /next HTTP/1.1\r\n\
           Host: example.test\r\n\
           \r\n"
          flow;
        let first = read_response reader in
        let second = read_response reader in
        Eio.Flow.shutdown flow `Send;
        first ^ second)
  in
  check bool "chunked response" true
    (contains_sub ~needle:"connection: keep-alive\r\n\r\nping\n" response);
  check bool "next response" true (String.ends_with ~suffix:"next\n" response)

let test_run_keep_alive_head_then_get () =
  require_network ();
  let response =
    with_server
      (fun _ -> Choku.Response.text "hello")
      (fun flow ->
        let reader = response_reader flow in
        Eio.Flow.copy_string "HEAD / HTTP/1.1\r\nHost: example.test\r\n\r\n"
          flow;
        let first = read_response ~include_body:false reader in
        Eio.Flow.copy_string "GET / HTTP/1.1\r\nHost: example.test\r\n\r\n" flow;
        let second = read_response reader in
        Eio.Flow.shutdown flow `Send;
        first ^ second)
  in
  check bool "head response" true
    (contains_sub
       ~needle:"content-length: 5\r\nconnection: keep-alive\r\n\r\nHTTP/1.1"
       response);
  check bool "get body" true (String.ends_with ~suffix:"hello" response)

let test_run_connection_close_request_closes () =
  require_network ();
  let response =
    with_server
      (fun _ -> Choku.Response.text "bye\n")
      (fun flow ->
        Eio.Flow.copy_string
          "GET / HTTP/1.1\r\n\
           Host: example.test\r\n\
           Connection: keep-alive, Close\r\n\
           \r\n"
          flow;
        Eio.Flow.shutdown flow `Send;
        let buffer = Buffer.create 128 in
        (try Eio.Flow.copy flow (Eio.Flow.buffer_sink buffer)
         with End_of_file -> ());
        Buffer.contents buffer)
  in
  check bool "connection close" true
    (contains_sub ~needle:"connection: close\r\n\r\nbye\n" response)

let test_run_keep_alive_false_closes () =
  require_network ();
  let response =
    with_server ~keep_alive:false
      (fun _ -> Choku.Response.text "ok\n")
      (request "GET / HTTP/1.1\r\nHost: example.test\r\n\r\n")
  in
  check bool "connection close" true
    (contains_sub ~needle:"connection: close\r\n\r\nok\n" response)

let test_run_response_connection_close_closes () =
  require_network ();
  let response =
    with_server
      (fun _ ->
        Choku.Response.text "bye\n"
        |> Choku.Response.with_header "Connection" "Close")
      (request "GET / HTTP/1.1\r\nHost: example.test\r\n\r\n")
  in
  check bool "connection close" true
    (contains_sub ~needle:"connection: close\r\n\r\nbye\n" response)

let test_run_response_connection_close_token_closes () =
  require_network ();
  let response =
    with_server
      (fun _ ->
        let headers =
          Choku.Headers.empty
          |> Choku.Headers.add "Connection" "keep-alive"
          |> Choku.Headers.add "Connection" "upgrade, Close"
        in
        Choku.Response.make Choku.Status.ok ~headers
          ~body:(Choku.Body.string "bye\n"))
      (request "GET / HTTP/1.1\r\nHost: example.test\r\n\r\n")
  in
  check bool "connection close" true
    (contains_sub ~needle:"connection: close\r\n\r\nbye\n" response)

let test_run_keep_alive_client_eof_after_response () =
  require_network ();
  let remaining =
    with_server
      (fun _ -> Choku.Response.text "ok\n")
      (fun flow ->
        let reader = response_reader flow in
        Eio.Flow.copy_string "GET / HTTP/1.1\r\nHost: example.test\r\n\r\n" flow;
        let response = read_response reader in
        check bool "keep-alive response" true
          (contains_sub ~needle:"connection: keep-alive\r\n\r\nok\n" response);
        Eio.Flow.shutdown flow `Send;
        let buffer = Buffer.create 128 in
        (try Eio.Flow.copy flow (Eio.Flow.buffer_sink buffer)
         with End_of_file -> ());
        Buffer.contents buffer)
  in
  check string "no synthetic response" "" remaining

let test_run_keep_alive_partial_next_request_eof_bad_request () =
  require_network ();
  let response =
    with_server
      (fun _ -> Choku.Response.text "ok\n")
      (fun flow ->
        let reader = response_reader flow in
        Eio.Flow.copy_string "GET / HTTP/1.1\r\nHost: example.test\r\n\r\n" flow;
        let first = read_response reader in
        Eio.Flow.copy_string "GET /broken HTTP/1.1\r\nHost" flow;
        Eio.Flow.shutdown flow `Send;
        let second = read_response reader in
        first ^ second)
  in
  check bool "first response" true
    (contains_sub ~needle:"connection: keep-alive\r\n\r\nok\n" response);
  check bool "second response" true
    (contains_sub
       ~needle:
         "HTTP/1.1 400 Bad Request\r\n\
          content-type: text/plain; charset=utf-8\r\n\
          content-length: 12\r\n\
          connection: close\r\n\
          \r\n\
          Bad Request\n"
       response)

let test_run_streaming_request_closes () =
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
          ping")
  in
  check bool "connection close" true
    (contains_sub ~needle:"connection: close\r\n\r\nok\n" response)

let test_run_keep_alive_idle_timeout_before_second_request () =
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
    Choku.Server.create ~request_head_timeout:(Some 0.02)
      ~handler:(fun _ -> Choku.Response.text "ok\n")
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
           let reader = response_reader flow in
           Eio.Flow.copy_string "GET / HTTP/1.1\r\nHost: example.test\r\n\r\n"
             flow;
           let first = read_response reader in
           Eio.Time.sleep clock 0.05;
           let second = read_response reader in
           first ^ second
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
  check bool "first 200" true
    (String.starts_with ~prefix:"HTTP/1.1 200 OK" response);
  check bool "second 408" true
    (contains_sub ~needle:"HTTP/1.1 408 Request Timeout" response)

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
     connection: keep-alive\r\n\
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
    with_server ~max_request_body_size:4
      ~request_body_mode:Choku.Server.Streaming
      (fun req ->
        check bool "streaming" false
          (Choku.Body.is_buffered (Choku.Request.body req));
        check
          (result string (of_pp Choku.Body.pp_error))
          "body" (Ok "ping")
          (Choku.Body.to_string_limited ~max_size:4 (Choku.Request.body req));
        Choku.Response.text "ok\n")
      (request raw)
  in
  check bool "200" true (String.starts_with ~prefix:"HTTP/1.1 200 OK" response)

let test_run_buffered_chunked_request () =
  require_network ();
  let raw =
    String.concat ""
      [
        "POST / HTTP/1.1\r\n";
        "Host: example.test\r\n";
        "Transfer-Encoding: chunked\r\n";
        "\r\n";
        "4\r\n";
        "Wiki\r\n";
        "5;ignored=yes\r\n";
        "pedia\r\n";
        "0\r\n";
        "X-Trailer: ignored\r\n";
        "\r\n";
      ]
  in
  let response =
    with_server ~max_request_body_size:9
      (fun req ->
        check bool "buffered" true
          (Choku.Body.is_buffered (Choku.Request.body req));
        check string "body" "Wikipedia"
          (Choku.Body.to_string (Choku.Request.body req));
        Choku.Response.text "ok\n")
      (request raw)
  in
  check bool "200" true (String.starts_with ~prefix:"HTTP/1.1 200 OK" response)

let test_run_buffered_chunked_payload_too_large () =
  require_network ();
  let response =
    with_server ~max_request_body_size:4
      (fun _ -> fail "handler should not run")
      (request
         "POST / HTTP/1.1\r\n\
          Host: example.test\r\n\
          Transfer-Encoding: chunked\r\n\
          \r\n\
          5\r\n\
          hello\r\n\
          0\r\n\
          \r\n")
  in
  check bool "413" true
    (String.starts_with ~prefix:"HTTP/1.1 413 Payload Too Large" response)

let test_run_streaming_chunked_payload_too_large () =
  require_network ();
  let response =
    with_server ~max_request_body_size:4
      ~request_body_mode:Choku.Server.Streaming
      (fun req ->
        match
          Choku.Body.with_source (Choku.Request.body req) Eio.Flow.read_all
        with
        | _ -> Choku.Response.text "unexpected\n"
        | exception Choku.Body.Body_too_large_read ->
            Choku.Response.text ~status:Choku.Status.payload_too_large
              "too large\n")
      (request
         "POST / HTTP/1.1\r\n\
          Host: example.test\r\n\
          Transfer-Encoding: chunked\r\n\
          \r\n\
          5\r\n\
          hello\r\n\
          0\r\n\
          \r\n")
  in
  check bool "413" true
    (String.starts_with ~prefix:"HTTP/1.1 413 Payload Too Large" response)

let test_run_streaming_chunked_malformed_uncaught_maps_400 () =
  require_network ();
  let response =
    with_server ~request_body_mode:Choku.Server.Streaming
      (fun req ->
        Choku.Body.with_source (Choku.Request.body req) Eio.Flow.read_all
        |> Choku.Response.text)
      (request
         "POST / HTTP/1.1\r\n\
          Host: example.test\r\n\
          Transfer-Encoding: chunked\r\n\
          \r\n\
          nope\r\n")
  in
  check bool "400" true
    (String.starts_with ~prefix:"HTTP/1.1 400 Bad Request" response)

let test_run_streaming_chunked_malformed_to_string_limited () =
  require_network ();
  let response =
    with_server ~request_body_mode:Choku.Server.Streaming
      (fun req ->
        check
          (result string (of_pp Choku.Body.pp_error))
          "body" (Error Choku.Body.Malformed_body)
          (Choku.Body.to_string_limited ~max_size:4 (Choku.Request.body req));
        Choku.Response.text ~status:Choku.Status.bad_request "bad body\n")
      (request
         "POST / HTTP/1.1\r\n\
          Host: example.test\r\n\
          Transfer-Encoding: chunked\r\n\
          \r\n\
          nope\r\n")
  in
  check bool "400" true
    (String.starts_with ~prefix:"HTTP/1.1 400 Bad Request" response)

let test_run_unsupported_transfer_coding () =
  require_network ();
  let response =
    with_server
      (fun _ -> fail "handler should not run")
      (request
         "POST / HTTP/1.1\r\n\
          Host: example.test\r\n\
          Transfer-Encoding: gzip\r\n\
          \r\n")
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
    |> Choku.Router.post "/buffered" (fun ctx ->
        let body = Choku.Request.body ctx.request in
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

let test_run_router_head_falls_back_to_get () =
  require_network ();
  let router =
    Choku.Router.empty
    |> Choku.Router.get "/health" (fun _ctx -> Choku.Response.text "ok\n")
  in
  let response =
    with_router_server router
      (request "HEAD /health HTTP/1.1\r\nHost: example.test\r\n\r\n")
  in
  check string "wire"
    "HTTP/1.1 200 OK\r\n\
     content-type: text/plain; charset=utf-8\r\n\
     content-length: 3\r\n\
     connection: keep-alive\r\n\
     \r\n"
    response

let test_run_router_method_not_allowed () =
  require_network ();
  let router =
    Choku.Router.empty
    |> Choku.Router.get "/health" (fun _ctx -> Choku.Response.text "ok\n")
  in
  let response =
    with_router_server router
      (request "POST /health HTTP/1.1\r\nHost: example.test\r\n\r\n")
  in
  check bool "405" true
    (String.starts_with ~prefix:"HTTP/1.1 405 Method Not Allowed" response);
  check bool "allow" true (contains_sub ~needle:"allow: GET, HEAD\r\n" response);
  check bool "body" true
    (String.ends_with ~suffix:"Method Not Allowed\n" response)

let test_run_router_method_not_allowed_drains_body_and_reuses () =
  require_network ();
  let router =
    Choku.Router.empty
    |> Choku.Router.get "/health" (fun _ctx -> Choku.Response.text "ok\n")
  in
  let response =
    with_router_server router (fun flow ->
        let reader = response_reader flow in
        Eio.Flow.copy_string
          "POST /health HTTP/1.1\r\n\
           Host: example.test\r\n\
           Content-Length: 4\r\n\
           \r\n\
           pingGET /health HTTP/1.1\r\n\
           Host: example.test\r\n\
           \r\n"
          flow;
        let first = read_response reader in
        let second = read_response reader in
        Eio.Flow.shutdown flow `Send;
        first ^ second)
  in
  check bool "405" true
    (contains_sub
       ~needle:
         "HTTP/1.1 405 Method Not Allowed\r\n\
          content-type: text/plain; charset=utf-8\r\n\
          allow: GET, HEAD\r\n\
          content-length: 19\r\n\
          connection: keep-alive\r\n\
          \r\n\
          Method Not Allowed\n"
       response);
  check bool "second response" true (String.ends_with ~suffix:"ok\n" response)

let test_run_router_method_not_allowed_oversized_body_precedence () =
  require_network ();
  let router =
    Choku.Router.empty
    |> Choku.Router.get "/health" (fun _ctx -> Choku.Response.text "ok\n")
  in
  let response =
    with_router_server router
      (request
         "POST /health HTTP/1.1\r\n\
          Host: example.test\r\n\
          Content-Length: 5\r\n\
          \r\n\
          hello")
  in
  check bool "413" true
    (String.starts_with ~prefix:"HTTP/1.1 413 Payload Too Large" response)

let test_run_router_method_not_allowed_malformed_body_precedence () =
  require_network ();
  let router =
    Choku.Router.empty
    |> Choku.Router.get "/health" (fun _ctx -> Choku.Response.text "ok\n")
  in
  let response =
    with_router_server router
      (request
         "POST /health HTTP/1.1\r\n\
          Host: example.test\r\n\
          Content-Length: nope\r\n\
          \r\n")
  in
  check bool "400" true
    (String.starts_with ~prefix:"HTTP/1.1 400 Bad Request" response)

let test_run_router_streaming_route () =
  require_network ();
  let body = String.make 5_000 'x' in
  let router =
    Choku.Router.empty
    |> Choku.Router.post ~request_body_mode:Choku.Request_body_mode.Streaming
         "/streaming" (fun ctx ->
           let request_body = Choku.Request.body ctx.request in
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
         "/upload" (fun ctx ->
           incr handler_started;
           check
             (result string (of_pp Choku.Body.pp_error))
             "body" (Ok "ping")
             (Choku.Body.to_string_limited ~max_size:4
                (Choku.Request.body ctx.request));
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
    |> Choku.Router.get "/health" (fun ctx ->
        check bool "health body is buffered" true
          (Choku.Body.is_buffered (Choku.Request.body ctx.request));
        Choku.Response.text "ok\n")
    |> Choku.Router.post ~request_body_mode:Choku.Request_body_mode.Streaming
         "/upload" (fun ctx ->
           check bool "request body is streaming" false
             (Choku.Body.is_buffered (Choku.Request.body ctx.request));
           let file_bytes = ref None in
           match
             Choku.Multipart.Streaming.iter_request ctx.request
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

let test_run_selector_chooses_buffered_or_streaming_by_path () =
  require_network ();
  let request_body_mode head =
    match Choku.Request_head.path head with
    | "/upload" -> Choku.Request_body_mode.Streaming
    | _ -> Choku.Request_body_mode.Buffered
  in
  let handler request =
    match Choku.Request.path request with
    | "/upload" ->
        check bool "upload body is streaming" false
          (Choku.Body.is_buffered (Choku.Request.body request));
        let body =
          match
            Choku.Body.to_string_limited ~max_size:8
              (Choku.Request.body request)
          with
          | Ok body -> body
          | Error error -> Format.asprintf "%a" Choku.Body.pp_error error
        in
        Choku.Response.text (body ^ "\n")
    | _ ->
        check bool "default body is buffered" true
          (Choku.Body.is_buffered (Choku.Request.body request));
        Choku.Response.text
          (Choku.Body.to_string (Choku.Request.body request) ^ "\n")
  in
  let buffered =
    with_selector_server ~max_request_body_size:8 ~request_body_mode handler
      (request
         "POST /echo HTTP/1.1\r\n\
          Host: example.test\r\n\
          Content-Length: 4\r\n\
          \r\n\
          ping")
  in
  check bool "buffered 200" true
    (String.starts_with ~prefix:"HTTP/1.1 200 OK" buffered);
  check bool "buffered body" true (String.ends_with ~suffix:"ping\n" buffered);
  let streaming =
    with_selector_server ~max_request_body_size:8 ~request_body_mode handler
      (request
         "POST /upload HTTP/1.1\r\n\
          Host: example.test\r\n\
          Content-Length: 4\r\n\
          \r\n\
          pong")
  in
  check bool "streaming 200" true
    (String.starts_with ~prefix:"HTTP/1.1 200 OK" streaming);
  check bool "streaming body" true (String.ends_with ~suffix:"pong\n" streaming)

let test_run_selector_can_inspect_method_and_headers () =
  require_network ();
  let request_body_mode head =
    match
      ( Choku.Request_head.meth head,
        Choku.Headers.get "x-body-mode" (Choku.Request_head.headers head) )
    with
    | Choku.Method.POST, Some "streaming" -> Choku.Request_body_mode.Streaming
    | _ -> Choku.Request_body_mode.Buffered
  in
  let response =
    with_selector_server ~request_body_mode
      (fun request ->
        check bool "body is streaming" false
          (Choku.Body.is_buffered (Choku.Request.body request));
        Choku.Response.text "ok\n")
      (request
         "POST /upload HTTP/1.1\r\n\
          Host: example.test\r\n\
          X-Body-Mode: streaming\r\n\
          Content-Length: 0\r\n\
          \r\n")
  in
  check bool "200" true (String.starts_with ~prefix:"HTTP/1.1 200 OK" response)

let test_run_selector_runs_once_per_keep_alive_request () =
  require_network ();
  let selector_calls = ref 0 in
  let request_body_mode head =
    incr selector_calls;
    check bool "selector sees method" true
      (Choku.Method.equal Choku.Method.GET (Choku.Request_head.meth head));
    Choku.Request_body_mode.Buffered
  in
  let response =
    with_selector_server ~request_body_mode
      (fun req -> Choku.Response.text (Choku.Request.path req ^ "\n"))
      (fun flow ->
        let reader = response_reader flow in
        Eio.Flow.copy_string "GET /one HTTP/1.1\r\nHost: example.test\r\n\r\n"
          flow;
        let first = read_response reader in
        Eio.Flow.copy_string "GET /two HTTP/1.1\r\nHost: example.test\r\n\r\n"
          flow;
        let second = read_response reader in
        Eio.Flow.shutdown flow `Send;
        first ^ second)
  in
  check int "selector calls" 2 !selector_calls;
  check bool "first response" true
    (contains_sub ~needle:"connection: keep-alive\r\n\r\n/one\n" response);
  check bool "second response" true (String.ends_with ~suffix:"/two\n" response)

let test_run_selector_exception_500_closes () =
  require_network ();
  let response =
    with_selector_server
      ~request_body_mode:(fun _ -> failwith "selector failed")
      (fun _ -> Choku.Response.text "unexpected\n")
      (fun flow ->
        Eio.Flow.copy_string
          "GET /boom HTTP/1.1\r\n\
           Host: example.test\r\n\
           \r\n\
           GET /next HTTP/1.1\r\n\
           Host: example.test\r\n\
           \r\n"
          flow;
        Eio.Flow.shutdown flow `Send;
        let buffer = Buffer.create 128 in
        (try Eio.Flow.copy flow (Eio.Flow.buffer_sink buffer)
         with End_of_file -> ());
        Buffer.contents buffer)
  in
  check bool "500" true
    (String.starts_with ~prefix:"HTTP/1.1 500 Internal Server Error" response);
  check bool "connection close" true
    (contains_sub ~needle:"connection: close\r\n" response);
  check bool "does not process next request" false
    (contains_sub ~needle:"unexpected" response)

let test_run_selector_head_exception_suppresses_body () =
  require_network ();
  let response =
    with_selector_server
      ~request_body_mode:(fun _ -> failwith "selector failed")
      (fun _ -> Choku.Response.text "unexpected\n")
      (request "HEAD /boom HTTP/1.1\r\nHost: example.test\r\n\r\n")
  in
  check bool "500" true
    (String.starts_with ~prefix:"HTTP/1.1 500 Internal Server Error" response);
  check bool "no 500 body" false
    (contains_sub ~needle:"\r\n\r\nInternal Server Error\n" response)

let test_run_selector_not_invoked_for_invalid_framing () =
  require_network ();
  let selector_calls = ref 0 in
  let response =
    with_selector_server
      ~request_body_mode:(fun _ ->
        incr selector_calls;
        Choku.Request_body_mode.Buffered)
      (fun _ -> Choku.Response.text "unexpected\n")
      (request
         "POST /upload HTTP/1.1\r\n\
          Host: example.test\r\n\
          Transfer-Encoding: gzip\r\n\
          \r\n")
  in
  check int "selector calls" 0 !selector_calls;
  check bool "400" true
    (String.starts_with ~prefix:"HTTP/1.1 400 Bad Request" response)

let test_run_streaming_response_known_length () =
  require_network ();
  let response =
    with_server
      (fun _ ->
        Choku.Response.stream ~content_length:8 (fun sink ->
            Eio.Flow.copy_string "pingpong" sink))
      (request "GET /download HTTP/1.1\r\nHost: example.test\r\n\r\n")
  in
  check bool "200" true (String.starts_with ~prefix:"HTTP/1.1 200 OK" response);
  check bool "content-length" true
    (contains_sub ~needle:"content-length: 8\r\n" response);
  check bool "no transfer-encoding" false
    (contains_sub ~needle:"transfer-encoding:" response);
  check bool "body" true (String.ends_with ~suffix:"pingpong" response)

let test_run_streaming_response_unknown_length_chunked () =
  require_network ();
  let response =
    with_server
      (fun _ ->
        Choku.Response.stream (fun sink ->
            Eio.Flow.copy_string "ping" sink;
            Eio.Flow.copy_string "pong" sink))
      (request "GET /download HTTP/1.1\r\nHost: example.test\r\n\r\n")
  in
  check bool "200" true (String.starts_with ~prefix:"HTTP/1.1 200 OK" response);
  check bool "transfer-encoding" true
    (contains_sub ~needle:"transfer-encoding: chunked\r\n" response);
  check bool "no content-length" false
    (contains_sub ~needle:"content-length:" response);
  check bool "chunks" true
    (String.ends_with ~suffix:"4\r\nping\r\n4\r\npong\r\n0\r\n\r\n" response)

let test_run_streaming_response_replaces_framing_headers () =
  require_network ();
  let headers =
    Choku.Headers.empty
    |> Choku.Headers.set "content-length" "999"
    |> Choku.Headers.set "transfer-encoding" "gzip"
  in
  let response =
    with_server
      (fun _ ->
        Choku.Response.stream ~headers (fun sink ->
            Eio.Flow.copy_string "data" sink))
      (request "GET /download HTTP/1.1\r\nHost: example.test\r\n\r\n")
  in
  check bool "chunked" true
    (contains_sub ~needle:"transfer-encoding: chunked\r\n" response);
  check bool "content-length removed" false
    (contains_sub ~needle:"content-length:" response);
  check bool "gzip removed" false (contains_sub ~needle:"gzip" response)

let test_run_head_streaming_response_does_not_invoke_writer () =
  require_network ();
  let writer_ran = ref false in
  let response =
    with_server
      (fun _ ->
        Choku.Response.stream (fun sink ->
            writer_ran := true;
            Eio.Flow.copy_string "unexpected" sink))
      (request "HEAD /download HTTP/1.1\r\nHost: example.test\r\n\r\n")
  in
  check bool "writer not run" false !writer_ran;
  check bool "chunked header" true
    (contains_sub ~needle:"transfer-encoding: chunked\r\n" response);
  check bool "no chunks" false
    (contains_sub ~needle:"\r\n\r\n0\r\n\r\n" response);
  check bool "no body" false (contains_sub ~needle:"unexpected" response)

let test_run_head_known_length_streaming_response_does_not_invoke_writer () =
  require_network ();
  let writer_ran = ref false in
  let response =
    with_server
      (fun _ ->
        Choku.Response.stream ~content_length:10 (fun sink ->
            writer_ran := true;
            Eio.Flow.copy_string "unexpected" sink))
      (request "HEAD /download HTTP/1.1\r\nHost: example.test\r\n\r\n")
  in
  check bool "writer not run" false !writer_ran;
  check bool "content-length" true
    (contains_sub ~needle:"content-length: 10\r\n" response);
  check bool "no transfer-encoding" false
    (contains_sub ~needle:"transfer-encoding:" response);
  check bool "no body" false (contains_sub ~needle:"unexpected" response)

let test_run_no_content_streaming_response_does_not_invoke_writer () =
  require_network ();
  let writer_ran = ref false in
  let response =
    with_server
      (fun _ ->
        Choku.Response.stream ~status:Choku.Status.no_content (fun sink ->
            writer_ran := true;
            Eio.Flow.copy_string "unexpected" sink))
      (request "GET /empty HTTP/1.1\r\nHost: example.test\r\n\r\n")
  in
  check bool "204" true
    (String.starts_with ~prefix:"HTTP/1.1 204 No Content" response);
  check bool "writer not run" false !writer_ran;
  check bool "no content-length" false
    (contains_sub ~needle:"content-length:" response);
  check bool "no transfer-encoding" false
    (contains_sub ~needle:"transfer-encoding:" response);
  check bool "no body" true (String.ends_with ~suffix:"\r\n\r\n" response)

let test_run_keep_alive_after_successful_streaming_response () =
  require_network ();
  let response =
    with_server
      (fun req ->
        Choku.Response.stream (fun sink ->
            Eio.Flow.copy_string (Choku.Request.path req ^ "\n") sink))
      (fun flow ->
        let reader = response_reader flow in
        Eio.Flow.copy_string "GET /one HTTP/1.1\r\nHost: example.test\r\n\r\n"
          flow;
        let first = read_response reader in
        Eio.Flow.copy_string "GET /two HTTP/1.1\r\nHost: example.test\r\n\r\n"
          flow;
        let second = read_response reader in
        Eio.Flow.shutdown flow `Send;
        first ^ second)
  in
  check bool "first keep-alive" true
    (contains_sub ~needle:"connection: keep-alive\r\n" response);
  check bool "first chunk" true
    (contains_sub ~needle:"5\r\n/one\n\r\n0\r\n\r\n" response);
  check bool "second chunk" true
    (String.ends_with ~suffix:"5\r\n/two\n\r\n0\r\n\r\n" response)

let test_run_streaming_response_failure_closes () =
  require_network ();
  let response =
    with_server
      (fun req ->
        if String.equal (Choku.Request.path req) "/boom" then
          Choku.Response.stream (fun sink ->
              Eio.Flow.copy_string "part" sink;
              failwith "boom")
        else Choku.Response.text "next\n")
      (fun flow ->
        Eio.Flow.copy_string
          "GET /boom HTTP/1.1\r\n\
           Host: example.test\r\n\
           \r\n\
           GET /next HTTP/1.1\r\n\
           Host: example.test\r\n\
           \r\n"
          flow;
        Eio.Flow.shutdown flow `Send;
        let buffer = Buffer.create 128 in
        (try Eio.Flow.copy flow (Eio.Flow.buffer_sink buffer)
         with End_of_file -> ());
        Buffer.contents buffer)
  in
  check bool "partial chunk" true
    (contains_sub ~needle:"4\r\npart\r\n" response);
  check bool "no terminator" false (contains_sub ~needle:"0\r\n\r\n" response);
  check bool "second request not processed" false
    (contains_sub ~needle:"next\n" response)

let test_run_streaming_response_known_length_underflow_closes () =
  require_network ();
  let response =
    with_server
      (fun req ->
        if String.equal (Choku.Request.path req) "/short" then
          Choku.Response.stream ~content_length:8 (fun sink ->
              Eio.Flow.copy_string "tiny" sink)
        else Choku.Response.text "next\n")
      (fun flow ->
        Eio.Flow.copy_string
          "GET /short HTTP/1.1\r\n\
           Host: example.test\r\n\
           \r\n\
           GET /next HTTP/1.1\r\n\
           Host: example.test\r\n\
           \r\n"
          flow;
        Eio.Flow.shutdown flow `Send;
        let buffer = Buffer.create 128 in
        (try Eio.Flow.copy flow (Eio.Flow.buffer_sink buffer)
         with End_of_file -> ());
        Buffer.contents buffer)
  in
  check bool "declared length" true
    (contains_sub ~needle:"content-length: 8\r\n" response);
  check bool "partial body" true (String.ends_with ~suffix:"tiny" response);
  check bool "second request not processed" false
    (contains_sub ~needle:"next\n" response)

let test_run_streaming_response_known_length_overflow_closes () =
  require_network ();
  let response =
    with_server
      (fun req ->
        if String.equal (Choku.Request.path req) "/long" then
          Choku.Response.stream ~content_length:4 (fun sink ->
              Eio.Flow.copy_string "toolong" sink)
        else Choku.Response.text "next\n")
      (fun flow ->
        Eio.Flow.copy_string
          "GET /long HTTP/1.1\r\n\
           Host: example.test\r\n\
           \r\n\
           GET /next HTTP/1.1\r\n\
           Host: example.test\r\n\
           \r\n"
          flow;
        Eio.Flow.shutdown flow `Send;
        let buffer = Buffer.create 128 in
        (try Eio.Flow.copy flow (Eio.Flow.buffer_sink buffer)
         with End_of_file -> ());
        Buffer.contents buffer)
  in
  check bool "declared length" true
    (contains_sub ~needle:"content-length: 4\r\n" response);
  check bool "overflow body not written" false
    (contains_sub ~needle:"toolong" response);
  check bool "second request not processed" false
    (contains_sub ~needle:"next\n" response)

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
          test_case
            "create with request body selector handle uses existing request \
             body"
            `Quick
            test_create_with_request_body_selector_handle_uses_existing_request_body;
          test_case "default max body size" `Quick
            test_default_max_request_body_size;
          test_case "create rejects invalid request head limits" `Quick
            test_create_rejects_invalid_request_head_limits;
          test_case "run success" `Quick test_run_success;
          test_case "run keep-alive two GETs" `Quick
            test_run_keep_alive_two_gets;
          test_case "run keep-alive pipelined GETs" `Quick
            test_run_keep_alive_pipelined_gets;
          test_case "run keep-alive fixed POST then GET" `Quick
            test_run_keep_alive_fixed_post_then_get;
          test_case "run keep-alive chunked POST then GET" `Quick
            test_run_keep_alive_chunked_post_then_get;
          test_case "run keep-alive HEAD then GET" `Quick
            test_run_keep_alive_head_then_get;
          test_case "run Connection close request closes" `Quick
            test_run_connection_close_request_closes;
          test_case "run keep_alive false closes" `Quick
            test_run_keep_alive_false_closes;
          test_case "run response Connection close closes" `Quick
            test_run_response_connection_close_closes;
          test_case "run response Connection close token closes" `Quick
            test_run_response_connection_close_token_closes;
          test_case "run keep-alive client EOF after response" `Quick
            test_run_keep_alive_client_eof_after_response;
          test_case "run keep-alive partial next request EOF bad request" `Quick
            test_run_keep_alive_partial_next_request_eof_bad_request;
          test_case "run streaming request closes" `Quick
            test_run_streaming_request_closes;
          test_case "run keep-alive idle timeout before second request" `Quick
            test_run_keep_alive_idle_timeout_before_second_request;
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
          test_case "run buffered chunked request" `Quick
            test_run_buffered_chunked_request;
          test_case "run buffered chunked payload too large" `Quick
            test_run_buffered_chunked_payload_too_large;
          test_case "run streaming chunked payload too large" `Quick
            test_run_streaming_chunked_payload_too_large;
          test_case "run streaming chunked malformed uncaught maps 400" `Quick
            test_run_streaming_chunked_malformed_uncaught_maps_400;
          test_case "run streaming chunked malformed to_string_limited" `Quick
            test_run_streaming_chunked_malformed_to_string_limited;
          test_case "run unsupported transfer coding" `Quick
            test_run_unsupported_transfer_coding;
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
          test_case "run router HEAD falls back to GET" `Quick
            test_run_router_head_falls_back_to_get;
          test_case "run router method not allowed" `Quick
            test_run_router_method_not_allowed;
          test_case "run router method not allowed drains body and reuses"
            `Quick test_run_router_method_not_allowed_drains_body_and_reuses;
          test_case "run router method not allowed oversized body precedence"
            `Quick test_run_router_method_not_allowed_oversized_body_precedence;
          test_case "run router method not allowed malformed body precedence"
            `Quick test_run_router_method_not_allowed_malformed_body_precedence;
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
          test_case "run selector chooses buffered or streaming by path" `Quick
            test_run_selector_chooses_buffered_or_streaming_by_path;
          test_case "run selector can inspect method and headers" `Quick
            test_run_selector_can_inspect_method_and_headers;
          test_case "run selector runs once per keep-alive request" `Quick
            test_run_selector_runs_once_per_keep_alive_request;
          test_case "run selector exception 500 closes" `Quick
            test_run_selector_exception_500_closes;
          test_case "run selector HEAD exception suppresses body" `Quick
            test_run_selector_head_exception_suppresses_body;
          test_case "run selector not invoked for invalid framing" `Quick
            test_run_selector_not_invoked_for_invalid_framing;
          test_case "run streaming response known length" `Quick
            test_run_streaming_response_known_length;
          test_case "run streaming response unknown length chunked" `Quick
            test_run_streaming_response_unknown_length_chunked;
          test_case "run streaming response replaces framing headers" `Quick
            test_run_streaming_response_replaces_framing_headers;
          test_case "run HEAD streaming response does not invoke writer" `Quick
            test_run_head_streaming_response_does_not_invoke_writer;
          test_case
            "run HEAD known-length streaming response does not invoke writer"
            `Quick
            test_run_head_known_length_streaming_response_does_not_invoke_writer;
          test_case "run no-content streaming response does not invoke writer"
            `Quick test_run_no_content_streaming_response_does_not_invoke_writer;
          test_case "run keep-alive after successful streaming response" `Quick
            test_run_keep_alive_after_successful_streaming_response;
          test_case "run streaming response failure closes" `Quick
            test_run_streaming_response_failure_closes;
          test_case "run streaming response known length underflow closes"
            `Quick test_run_streaming_response_known_length_underflow_closes;
          test_case "run streaming response known length overflow closes" `Quick
            test_run_streaming_response_known_length_overflow_closes;
          test_case "run handler exception" `Quick test_run_handler_exception;
        ] );
    ]
