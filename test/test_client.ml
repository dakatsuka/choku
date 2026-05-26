open Alcotest

[@@@alert "-internal"]

let require_network () =
  match Sys.getenv_opt "CHOKU_RUN_NETWORK_TESTS" with
  | Some "1" -> ()
  | _ -> skip ()

let client_error = testable Choku.Client.Error.pp Choku.Client.Error.equal

let request_ok ?headers ?body ~meth ~url () =
  match Choku.Client.Request.make ?headers ?body ~meth ~url () with
  | Ok request -> request
  | Error error ->
      failf "unexpected request error: %a" Choku.Client.Error.pp error

let request_error ?headers ?body ~meth ~url () =
  match Choku.Client.Request.make ?headers ?body ~meth ~url () with
  | Ok _ -> fail "expected request error"
  | Error error -> error

let test_request_normalizes_url () =
  let request =
    request_ok ~meth:Choku.Method.GET ~url:"http://example.test:8080/items?a=1"
      ()
  in
  check
    (module Choku.Method)
    "method" Choku.Method.GET
    (Choku.Client.Request.meth request);
  check string "url" "http://example.test:8080/items?a=1"
    (Choku.Client.Request.url request);
  check string "authority" "example.test:8080"
    (Choku.Client.Request.authority request);
  check string "host" "example.test" (Choku.Client.Request.host request);
  check int "port" 8080 (Choku.Client.Request.port request);
  check string "target" "/items?a=1" (Choku.Client.Request.target request)

let test_request_normalizes_https_url () =
  let request =
    request_ok ~meth:Choku.Method.GET ~url:"https://example.test:8443/items?a=1"
      ()
  in
  check bool "scheme" true
    (match Choku.Client.Request.scheme request with
    | Choku.Client.Request.Https -> true
    | Choku.Client.Request.Http -> false);
  check string "authority" "example.test:8443"
    (Choku.Client.Request.authority request);
  check string "host" "example.test" (Choku.Client.Request.host request);
  check int "port" 8443 (Choku.Client.Request.port request);
  check string "target" "/items?a=1" (Choku.Client.Request.target request)

let test_request_defaults_path_and_port () =
  let request =
    request_ok ~meth:Choku.Method.GET ~url:"http://example.test" ()
  in
  check string "authority" "example.test"
    (Choku.Client.Request.authority request);
  check int "port" 80 (Choku.Client.Request.port request);
  check string "target" "/" (Choku.Client.Request.target request)

let test_request_defaults_https_path_and_port () =
  let request =
    request_ok ~meth:Choku.Method.GET ~url:"https://example.test" ()
  in
  check string "authority" "example.test"
    (Choku.Client.Request.authority request);
  check int "port" 443 (Choku.Client.Request.port request);
  check string "target" "/" (Choku.Client.Request.target request)

let test_request_omits_explicit_default_port_from_authority () =
  let request =
    request_ok ~meth:Choku.Method.GET ~url:"http://example.test:80/" ()
  in
  check string "authority" "example.test"
    (Choku.Client.Request.authority request);
  check int "port" 80 (Choku.Client.Request.port request)

let test_request_omits_explicit_https_default_port_from_authority () =
  let request =
    request_ok ~meth:Choku.Method.GET ~url:"https://example.test:443/" ()
  in
  check string "authority" "example.test"
    (Choku.Client.Request.authority request);
  check int "port" 443 (Choku.Client.Request.port request)

let test_request_accepts_single_label_https_host () =
  let request = request_ok ~meth:Choku.Method.GET ~url:"https://cafe/" () in
  check string "host" "cafe" (Choku.Client.Request.host request);
  check string "authority" "cafe" (Choku.Client.Request.authority request);
  check int "port" 443 (Choku.Client.Request.port request)

let test_request_rejects_unsupported_url_and_method () =
  check client_error "scheme" (Choku.Client.Error.Unsupported_scheme "ftp")
    (request_error ~meth:Choku.Method.GET ~url:"ftp://example.test/" ());
  check client_error "https ip"
    (Choku.Client.Error.Invalid_url "https IP literal not supported")
    (request_error ~meth:Choku.Method.GET ~url:"https://127.0.0.1/" ());
  check client_error "https numeric ip"
    (Choku.Client.Error.Invalid_url "https IP literal not supported")
    (request_error ~meth:Choku.Method.GET ~url:"https://0x7f000001/" ());
  check client_error "fragment"
    (Choku.Client.Error.Invalid_url "fragment not allowed")
    (request_error ~meth:Choku.Method.GET ~url:"http://example.test/#x" ());
  check client_error "connect"
    (Choku.Client.Error.Unsupported_method (Choku.Method.Other "CONNECT"))
    (request_error ~meth:(Choku.Method.Other "CONNECT")
       ~url:"http://example.test/" ())

let test_request_replaces_headers_and_body () =
  let request =
    request_ok ~meth:Choku.Method.POST ~url:"http://example.test/" ()
    |> Choku.Client.Request.with_header "authorization" "Bearer token"
    |> Choku.Client.Request.with_body (Choku.Body.string "ping")
  in
  check (option string) "authorization" (Some "Bearer token")
    (Choku.Headers.get "authorization" (Choku.Client.Request.headers request));
  check string "body" "ping"
    (Choku.Body.to_string (Choku.Client.Request.body request))

let test_middleware_order_and_response_replacement () =
  let trace = ref [] in
  let middleware name next request =
    trace := !trace @ [ name ^ "-request" ];
    let response = next request in
    trace := !trace @ [ name ^ "-response" ];
    response
  in
  let handler _ =
    trace := !trace @ [ "transport" ];
    Ok
      (Choku.Client.Response.make
         ~headers:(Choku.Headers.set "x-transport" "yes" Choku.Headers.empty)
         Choku.Status.ok)
  in
  let handler =
    Choku.Client.Middleware.apply [ middleware "a"; middleware "b" ] handler
  in
  let request =
    request_ok ~meth:Choku.Method.GET ~url:"http://example.test/" ()
  in
  match handler request with
  | Error error ->
      failf "unexpected response error: %a" Choku.Client.Error.pp error
  | Ok response ->
      check (list string) "trace"
        [ "a-request"; "b-request"; "transport"; "b-response"; "a-response" ]
        !trace;
      check (option string) "response header" (Some "yes")
        (Choku.Headers.get "x-transport"
           (Choku.Client.Response.headers response))

let with_intercept_client observe call =
  Eio_main.run @@ fun env ->
  Eio.Switch.run @@ fun sw ->
  let net = Eio.Stdenv.net env in
  let middleware _next request =
    observe request;
    Ok (Choku.Client.Response.make Choku.Status.ok)
  in
  let client = Choku.Client.create ~net ~middlewares:[ middleware ] () in
  call sw client

let expect_ok_response = function
  | Ok response -> response
  | Error error ->
      failf "unexpected response error: %a" Choku.Client.Error.pp error

let test_convenience_preserves_headers_and_body () =
  let seen = ref None in
  let headers =
    Choku.Headers.empty |> Choku.Headers.set "authorization" "Bearer token"
  in
  let body = Choku.Body.string "payload" in
  let response =
    with_intercept_client
      (fun request -> seen := Some request)
      (fun sw client ->
        Choku.Client.post ~sw client ~headers ~body
          ~url:"http://example.test/items" ())
    |> expect_ok_response
  in
  check int "status" 200
    (Choku.Status.code (Choku.Client.Response.status response));
  match !seen with
  | None -> fail "expected middleware to observe request"
  | Some request ->
      check
        (module Choku.Method)
        "method" Choku.Method.POST
        (Choku.Client.Request.meth request);
      check (option string) "authorization" (Some "Bearer token")
        (Choku.Headers.get "authorization"
           (Choku.Client.Request.headers request));
      check string "body" "payload"
        (Choku.Body.to_string (Choku.Client.Request.body request))

let test_convenience_methods_use_expected_methods () =
  let observed = ref [] in
  let observe expected request =
    observed := !observed @ [ Choku.Client.Request.meth request ];
    check
      (module Choku.Method)
      "method" expected
      (Choku.Client.Request.meth request)
  in
  let call expected helper =
    with_intercept_client (observe expected) (fun sw client ->
        helper ~sw client ~url:"http://example.test/" ())
    |> expect_ok_response |> ignore
  in
  call Choku.Method.GET (fun ~sw client ~url () ->
      Choku.Client.get ~sw client ~url ());
  call Choku.Method.HEAD (fun ~sw client ~url () ->
      Choku.Client.head ~sw client ~url ());
  call Choku.Method.POST (fun ~sw client ~url () ->
      Choku.Client.post ~sw client ~url ());
  call Choku.Method.PUT (fun ~sw client ~url () ->
      Choku.Client.put ~sw client ~url ());
  call Choku.Method.PATCH (fun ~sw client ~url () ->
      Choku.Client.patch ~sw client ~url ());
  call Choku.Method.DELETE (fun ~sw client ~url () ->
      Choku.Client.delete ~sw client ~url ());
  call Choku.Method.OPTIONS (fun ~sw client ~url () ->
      Choku.Client.options ~sw client ~url ());
  check
    (list (module Choku.Method))
    "observed methods"
    [
      Choku.Method.GET;
      Choku.Method.HEAD;
      Choku.Method.POST;
      Choku.Method.PUT;
      Choku.Method.PATCH;
      Choku.Method.DELETE;
      Choku.Method.OPTIONS;
    ]
    !observed

let test_fetch_preserves_arbitrary_method () =
  let meth = Choku.Method.Other "PROPFIND" in
  let seen = ref None in
  with_intercept_client
    (fun request -> seen := Some request)
    (fun sw client ->
      Choku.Client.fetch ~sw client ~meth ~url:"http://example.test/" ())
  |> expect_ok_response |> ignore;
  match !seen with
  | None -> fail "expected middleware to observe request"
  | Some request ->
      check
        (module Choku.Method)
        "method" meth
        (Choku.Client.Request.meth request)

let test_fetch_request_construction_error_bypasses_middleware () =
  let called = ref false in
  let result =
    with_intercept_client
      (fun _request -> called := true)
      (fun sw client ->
        Choku.Client.fetch ~sw client ~meth:Choku.Method.GET
          ~url:"ftp://example.test/" ())
  in
  let error =
    match result with
    | Ok _response -> fail "expected request construction error"
    | Error error -> error
  in
  check client_error "error" (Choku.Client.Error.Unsupported_scheme "ftp") error;
  check bool "middleware not called" false !called

let redirect_response status location =
  Choku.Client.Response.make
    ~headers:(Choku.Headers.set "location" location Choku.Headers.empty)
    status

let test_follow_redirects_get_chain () =
  let seen_urls = ref [] in
  let handler request =
    seen_urls := !seen_urls @ [ Choku.Client.Request.url request ];
    match !seen_urls with
    | [ _ ] -> Ok (redirect_response Choku.Status.found "/next")
    | [ _; _ ] -> Ok (redirect_response Choku.Status.found "?page=2")
    | [ _; _; _ ] -> Ok (Choku.Client.Response.make Choku.Status.ok)
    | _ -> fail "unexpected redirect request"
  in
  let handler =
    Choku.Client.Middleware.follow_redirects ~max_redirects:3 () handler
  in
  let request =
    request_ok ~meth:Choku.Method.GET ~url:"http://example.test/start?old=1" ()
  in
  match handler request with
  | Error error ->
      failf "unexpected response error: %a" Choku.Client.Error.pp error
  | Ok response ->
      check int "status" 200
        (Choku.Status.code (Choku.Client.Response.status response));
      check (list string) "urls"
        [
          "http://example.test/start?old=1";
          "http://example.test/next";
          "http://example.test/next?page=2";
        ]
        !seen_urls

let test_follow_redirects_strips_sensitive_headers_cross_origin () =
  let seen_authorization = ref [] in
  let seen_cookie = ref [] in
  let seen_proxy_authorization = ref [] in
  let handler request =
    let headers = Choku.Client.Request.headers request in
    seen_authorization :=
      !seen_authorization @ [ Choku.Headers.get "authorization" headers ];
    seen_cookie := !seen_cookie @ [ Choku.Headers.get "cookie" headers ];
    seen_proxy_authorization :=
      !seen_proxy_authorization
      @ [ Choku.Headers.get "proxy-authorization" headers ];
    match !seen_authorization with
    | [ _ ] ->
        Ok
          (redirect_response Choku.Status.found "http://other.example.test/done")
    | [ _; _ ] -> Ok (Choku.Client.Response.make Choku.Status.ok)
    | _ -> fail "unexpected redirect request"
  in
  let handler = Choku.Client.Middleware.follow_redirects () handler in
  let headers =
    Choku.Headers.empty
    |> Choku.Headers.set "authorization" "Bearer token"
    |> Choku.Headers.set "cookie" "session=secret"
    |> Choku.Headers.set "proxy-authorization" "Basic secret"
  in
  let request =
    request_ok ~headers ~meth:Choku.Method.GET ~url:"http://example.test/start"
      ()
  in
  match handler request with
  | Error error ->
      failf "unexpected response error: %a" Choku.Client.Error.pp error
  | Ok _ ->
      check
        (list (option string))
        "authorization"
        [ Some "Bearer token"; None ]
        !seen_authorization;
      check
        (list (option string))
        "cookie"
        [ Some "session=secret"; None ]
        !seen_cookie;
      check
        (list (option string))
        "proxy authorization"
        [ Some "Basic secret"; None ]
        !seen_proxy_authorization

let test_follow_redirects_preserves_sensitive_headers_same_origin () =
  let seen_authorization = ref [] in
  let handler request =
    let headers = Choku.Client.Request.headers request in
    seen_authorization :=
      !seen_authorization @ [ Choku.Headers.get "authorization" headers ];
    match !seen_authorization with
    | [ _ ] ->
        Ok
          (redirect_response Choku.Status.found "http://example.test:8080/done")
    | [ _; _ ] -> Ok (Choku.Client.Response.make Choku.Status.ok)
    | _ -> fail "unexpected redirect request"
  in
  let handler = Choku.Client.Middleware.follow_redirects () handler in
  let headers =
    Choku.Headers.set "authorization" "Bearer token" Choku.Headers.empty
  in
  let request =
    request_ok ~headers ~meth:Choku.Method.GET
      ~url:"http://Example.test:8080/start" ()
  in
  match handler request with
  | Error error ->
      failf "unexpected response error: %a" Choku.Client.Error.pp error
  | Ok _ ->
      check
        (list (option string))
        "authorization"
        [ Some "Bearer token"; Some "Bearer token" ]
        !seen_authorization

let test_follow_redirects_strips_location_fragment () =
  let seen_urls = ref [] in
  let handler request =
    seen_urls := !seen_urls @ [ Choku.Client.Request.url request ];
    match !seen_urls with
    | [ _ ] -> Ok (redirect_response Choku.Status.found "/login#section")
    | [ _; _ ] -> Ok (Choku.Client.Response.make Choku.Status.ok)
    | _ -> fail "unexpected redirect request"
  in
  let handler = Choku.Client.Middleware.follow_redirects () handler in
  let request =
    request_ok ~meth:Choku.Method.GET ~url:"http://example.test/start" ()
  in
  match handler request with
  | Error error ->
      failf "unexpected response error: %a" Choku.Client.Error.pp error
  | Ok _ ->
      check (list string) "urls"
        [ "http://example.test/start"; "http://example.test/login" ]
        !seen_urls

let test_follow_redirects_303_rewrites_to_get () =
  let seen_methods = ref [] in
  let seen_bodies = ref [] in
  let handler request =
    seen_methods := !seen_methods @ [ Choku.Client.Request.meth request ];
    seen_bodies :=
      !seen_bodies
      @ [ Choku.Body.to_string (Choku.Client.Request.body request) ];
    match !seen_methods with
    | [ _ ] -> Ok (redirect_response Choku.Status.see_other "/done")
    | [ _; _ ] -> Ok (Choku.Client.Response.make Choku.Status.ok)
    | _ -> fail "unexpected redirect request"
  in
  let handler = Choku.Client.Middleware.follow_redirects () handler in
  let request =
    request_ok ~meth:Choku.Method.POST ~url:"http://example.test/form"
      ~body:(Choku.Body.string "payload")
      ()
  in
  match handler request with
  | Error error ->
      failf "unexpected response error: %a" Choku.Client.Error.pp error
  | Ok _ ->
      check
        (list (module Choku.Method))
        "methods"
        [ Choku.Method.POST; Choku.Method.GET ]
        !seen_methods;
      check (list string) "bodies" [ "payload"; "" ] !seen_bodies

let test_follow_redirects_does_not_rewrite_post_302 () =
  let calls = ref 0 in
  let handler _ =
    incr calls;
    Ok (redirect_response Choku.Status.found "/done")
  in
  let handler = Choku.Client.Middleware.follow_redirects () handler in
  let request =
    request_ok ~meth:Choku.Method.POST ~url:"http://example.test/form" ()
  in
  match handler request with
  | Error error ->
      failf "unexpected response error: %a" Choku.Client.Error.pp error
  | Ok response ->
      check int "calls" 1 !calls;
      check int "status" 302
        (Choku.Status.code (Choku.Client.Response.status response))

let test_follow_redirects_reports_missing_location () =
  let handler _ = Ok (Choku.Client.Response.make Choku.Status.found) in
  let handler = Choku.Client.Middleware.follow_redirects () handler in
  let request =
    request_ok ~meth:Choku.Method.GET ~url:"http://example.test/start" ()
  in
  check
    (result reject client_error)
    "error" (Error Choku.Client.Error.Redirect_missing_location)
    (handler request)

let test_follow_redirects_reports_too_many_redirects () =
  let handler _ = Ok (redirect_response Choku.Status.found "/again") in
  let handler =
    Choku.Client.Middleware.follow_redirects ~max_redirects:1 () handler
  in
  let request =
    request_ok ~meth:Choku.Method.GET ~url:"http://example.test/start" ()
  in
  check
    (result reject client_error)
    "error" (Error Choku.Client.Error.Too_many_redirects) (handler request)

let test_create_rejects_invalid_limits () =
  Eio_main.run @@ fun env ->
  let net = Eio.Stdenv.net env in
  let mono_clock = Eio.Stdenv.mono_clock env in
  check_raises "invalid head limit"
    (Invalid_argument "max_response_head_size <= 0") (fun () ->
      ignore
        (Choku.Client.create ~net ~max_response_head_size:0 () : Choku.Client.t));
  check_raises "invalid body limit"
    (Invalid_argument "max_response_body_size < 0") (fun () ->
      ignore
        (Choku.Client.create ~net ~max_response_body_size:(-1) ()
          : Choku.Client.t));
  check_raises "invalid timeout"
    (Invalid_argument "non-positive connect_timeout") (fun () ->
      ignore
        (Choku.Client.create ~net ~mono_clock ~connect_timeout:(Some 0.0) ()
          : Choku.Client.t));
  check_raises "nan timeout"
    (Invalid_argument "non-positive response_head_timeout") (fun () ->
      ignore
        (Choku.Client.create ~net ~mono_clock
           ~response_head_timeout:(Some Float.nan) ()
          : Choku.Client.t));
  check_raises "infinite timeout"
    (Invalid_argument "non-positive response_body_timeout") (fun () ->
      ignore
        (Choku.Client.create ~net ~mono_clock
           ~response_body_timeout:(Some Float.infinity) ()
          : Choku.Client.t));
  check_raises "timeout without mono clock"
    (Invalid_argument "client timeouts require mono_clock") (fun () ->
      ignore
        (Choku.Client.create ~net ~response_head_timeout:(Some 1.0) ()
          : Choku.Client.t));
  check_raises "negative max redirects" (Invalid_argument "max_redirects < 0")
    (fun () ->
      ignore
        (Choku.Client.Middleware.follow_redirects ~max_redirects:(-1) ()
          : Choku.Client.Middleware.t))

let test_tls_ca_file_rejects_empty_file () =
  Eio_main.run @@ fun env ->
  let ( / ) = Eio.Path.( / ) in
  let path =
    Eio.Stdenv.fs env
    / Printf.sprintf "/tmp/choku-empty-ca-%d.pem" (Unix.getpid ())
  in
  Fun.protect
    ~finally:(fun () ->
      match Eio.Path.native path with
      | None -> ()
      | Some path -> ( try Unix.unlink path with Unix.Unix_error _ -> ()))
    (fun () ->
      Eio.Path.save ~create:(`Or_truncate 0o600) path "";
      check
        (result reject client_error)
        "error"
        (Error
           (Choku.Client.Error.Tls_configuration_failed
              "no CA certificates found"))
        (Choku.Client.Tls.ca_file path))

let available_port () =
  let socket = Unix.socket Unix.PF_INET Unix.SOCK_STREAM 0 in
  Fun.protect
    ~finally:(fun () -> Unix.close socket)
    (fun () ->
      Unix.bind socket Unix.(ADDR_INET (inet_addr_loopback, 0));
      match Unix.getsockname socket with
      | Unix.ADDR_INET (_, port) -> port
      | Unix.ADDR_UNIX _ -> fail "expected TCP socket")

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

let string_contains_sub string ~sub =
  let string_length = String.length string in
  let sub_length = String.length sub in
  let rec loop index =
    if index + sub_length > string_length then false
    else if String.equal (String.sub string index sub_length) sub then true
    else loop (index + 1)
  in
  loop 0

let read_request_head flow =
  let buffer = Buffer.create 256 in
  let scratch = Cstruct.create 128 in
  let rec loop () =
    match find_header_end (Buffer.contents buffer) with
    | Some header_end -> String.sub (Buffer.contents buffer) 0 (header_end + 4)
    | None ->
        let read = Eio.Flow.single_read flow scratch in
        Buffer.add_string buffer
          (Cstruct.to_string (Cstruct.sub scratch 0 read));
        loop ()
  in
  loop ()

let with_raw_server ?max_response_body_size response f =
  require_network ();
  Eio_main.run @@ fun env ->
  let net = Eio.Stdenv.net env in
  let clock = Eio.Stdenv.clock env in
  let port = available_port () in
  let addr = `Tcp (Eio.Net.Ipaddr.V4.loopback, port) in
  let request_head = ref None in
  let result = ref None in
  (try
     Eio.Switch.run @@ fun sw ->
     let socket = Eio.Net.listen ~reuse_addr:true ~backlog:1 ~sw net addr in
     Eio.Fiber.fork ~sw (fun () ->
         Eio.Net.run_server socket
           ~on_error:(function
             | Eio.Cancel.Cancelled _ as exn -> raise exn | _ -> ())
           (fun flow _addr ->
             request_head := Some (read_request_head flow);
             Eio.Flow.copy_string response flow;
             Eio.Flow.shutdown flow `All));
     let rec connect attempts =
       Eio.Switch.run @@ fun client_sw ->
       let client = Choku.Client.create ?max_response_body_size ~net () in
       let request =
         request_ok ~meth:Choku.Method.GET
           ~url:(Printf.sprintf "http://127.0.0.1:%d/items?a=1" port)
           ()
       in
       match Choku.Client.request ~sw:client_sw client request with
       | Error (Choku.Client.Error.Connection_failed _) when attempts > 0 ->
           Eio.Time.sleep clock 0.01;
           connect (attempts - 1)
       | response -> response
       | exception _ when attempts > 0 ->
           Eio.Time.sleep clock 0.01;
           connect (attempts - 1)
     in
     let response = connect 100 in
     let request_head = !request_head in
     result := Some (f response request_head);
     Eio.Switch.fail sw Exit
   with Exit -> ());
  match !result with Some result -> result | None -> fail "no client result"

let test_request_wire_and_fixed_response () =
  with_raw_server
    "HTTP/1.1 200 OK\r\nContent-Length: 5\r\nX-Test: yes\r\n\r\nhello"
    (fun response request_head ->
      match response with
      | Error error ->
          failf "unexpected response error: %a" Choku.Client.Error.pp error
      | Ok response ->
          let request_head = Option.get request_head in
          check bool "request line" true
            (String.starts_with ~prefix:"GET /items?a=1 HTTP/1.1\r\n"
               request_head);
          check bool "host" true
            (string_contains_sub request_head ~sub:"host: 127.0.0.1");
          check int "status" 200
            (Choku.Status.code (Choku.Client.Response.status response));
          check string "body" "hello"
            (Choku.Body.to_string (Choku.Client.Response.body response));
          check (option string) "header" (Some "yes")
            (Choku.Headers.get "x-test"
               (Choku.Client.Response.headers response)))

let test_follow_redirects_over_transport () =
  require_network ();
  Eio_main.run @@ fun env ->
  let net = Eio.Stdenv.net env in
  let clock = Eio.Stdenv.clock env in
  let port = available_port () in
  let addr = `Tcp (Eio.Net.Ipaddr.V4.loopback, port) in
  let targets = ref [] in
  let result = ref None in
  (try
     Eio.Switch.run @@ fun sw ->
     let socket = Eio.Net.listen ~reuse_addr:true ~backlog:4 ~sw net addr in
     Eio.Fiber.fork ~sw (fun () ->
         Eio.Net.run_server socket
           ~on_error:(function
             | Eio.Cancel.Cancelled _ as exn -> raise exn | _ -> ())
           (fun flow _addr ->
             let request_head = read_request_head flow in
             if string_contains_sub request_head ~sub:"GET /start HTTP/1.1" then (
               targets := !targets @ [ "/start" ];
               Eio.Flow.copy_string
                 "HTTP/1.1 302 Found\r\n\
                  Location: /done\r\n\
                  Content-Length: 0\r\n\
                  \r\n"
                 flow)
             else if string_contains_sub request_head ~sub:"GET /done HTTP/1.1"
             then (
               targets := !targets @ [ "/done" ];
               Eio.Flow.copy_string
                 "HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nok" flow)
             else failf "unexpected request head: %S" request_head;
             Eio.Flow.shutdown flow `All));
     let rec connect attempts =
       Eio.Switch.run @@ fun client_sw ->
       let client =
         Choku.Client.create ~net
           ~middlewares:[ Choku.Client.Middleware.follow_redirects () ]
           ()
       in
       let request =
         request_ok ~meth:Choku.Method.GET
           ~url:(Printf.sprintf "http://127.0.0.1:%d/start" port)
           ()
       in
       match Choku.Client.request ~sw:client_sw client request with
       | Error (Choku.Client.Error.Connection_failed _) when attempts > 0 ->
           Eio.Time.sleep clock 0.01;
           connect (attempts - 1)
       | response -> response
       | exception _ when attempts > 0 ->
           Eio.Time.sleep clock 0.01;
           connect (attempts - 1)
     in
     result := Some (connect 100);
     Eio.Switch.fail sw Exit
   with Exit -> ());
  match !result with
  | None -> fail "no client result"
  | Some (Error error) ->
      failf "unexpected response error: %a" Choku.Client.Error.pp error
  | Some (Ok response) ->
      check string "body" "ok"
        (Choku.Body.to_string (Choku.Client.Response.body response));
      check (list string) "targets" [ "/start"; "/done" ] !targets

let test_chunked_response_skips_informational () =
  with_raw_server
    "HTTP/1.1 100 Continue\r\n\
     \r\n\
     HTTP/1.1 200 OK\r\n\
     Transfer-Encoding: chunked\r\n\
     \r\n\
     5\r\n\
     hello\r\n\
     0\r\n\
     \r\n" (fun response _ ->
      match response with
      | Error error ->
          failf "unexpected response error: %a" Choku.Client.Error.pp error
      | Ok response ->
          check string "body" "hello"
            (Choku.Body.to_string (Choku.Client.Response.body response)))

let test_head_response_is_bodyless () =
  require_network ();
  Eio_main.run @@ fun env ->
  let net = Eio.Stdenv.net env in
  let clock = Eio.Stdenv.clock env in
  let port = available_port () in
  let addr = `Tcp (Eio.Net.Ipaddr.V4.loopback, port) in
  let result = ref None in
  (try
     Eio.Switch.run @@ fun sw ->
     let socket = Eio.Net.listen ~reuse_addr:true ~backlog:1 ~sw net addr in
     Eio.Fiber.fork ~sw (fun () ->
         Eio.Net.run_server socket
           ~on_error:(function
             | Eio.Cancel.Cancelled _ as exn -> raise exn | _ -> ())
           (fun flow _addr ->
             ignore (read_request_head flow : string);
             Eio.Flow.copy_string
               "HTTP/1.1 204 No Content\r\nContent-Length: 10\r\n\r\nignored"
               flow;
             Eio.Flow.shutdown flow `All));
     let rec connect attempts =
       Eio.Switch.run @@ fun client_sw ->
       let client = Choku.Client.create ~net () in
       let request =
         request_ok ~meth:Choku.Method.HEAD
           ~url:(Printf.sprintf "http://127.0.0.1:%d/" port)
           ()
       in
       match Choku.Client.request ~sw:client_sw client request with
       | Error (Choku.Client.Error.Connection_failed _) when attempts > 0 ->
           Eio.Time.sleep clock 0.01;
           connect (attempts - 1)
       | response -> response
       | exception _ when attempts > 0 ->
           Eio.Time.sleep clock 0.01;
           connect (attempts - 1)
     in
     result := Some (connect 100);
     Eio.Switch.fail sw Exit
   with Exit -> ());
  match !result with
  | None -> fail "no client result"
  | Some (Error error) ->
      failf "unexpected response error: %a" Choku.Client.Error.pp error
  | Some (Ok response) ->
      check string "body" ""
        (Choku.Body.to_string (Choku.Client.Response.body response))

let test_rejects_ambiguous_response_framing () =
  with_raw_server
    "HTTP/1.1 200 OK\r\n\
     Content-Length: 5\r\n\
     Transfer-Encoding: chunked\r\n\
     \r\n\
     0\r\n\
     \r\n" (fun response _ ->
      check
        (result reject client_error)
        "error" (Error Choku.Client.Error.Unsupported_transfer_encoding)
        response)

let test_rejects_unsupported_transfer_encoding () =
  with_raw_server "HTTP/1.1 200 OK\r\nTransfer-Encoding: gzip\r\n\r\n"
    (fun response _ ->
      check
        (result reject client_error)
        "error" (Error Choku.Client.Error.Unsupported_transfer_encoding)
        response)

let test_rejects_invalid_content_length () =
  with_raw_server
    "HTTP/1.1 200 OK\r\nContent-Length: 5\r\nContent-Length: 5\r\n\r\nhello"
    (fun response _ ->
      check
        (result reject client_error)
        "error" (Error Choku.Client.Error.Invalid_content_length) response)

let test_rejects_unsupported_upgrade () =
  with_raw_server "HTTP/1.1 101 Switching Protocols\r\n\r\n" (fun response _ ->
      check
        (result reject client_error)
        "error" (Error Choku.Client.Error.Unsupported_upgrade) response)

let test_rejects_response_body_too_large () =
  with_raw_server ~max_response_body_size:4
    "HTTP/1.1 200 OK\r\nContent-Length: 5\r\n\r\nhello" (fun response _ ->
      check
        (result reject client_error)
        "error" (Error Choku.Client.Error.Response_body_too_large) response)

let test_zero_response_body_limit_allows_empty_only () =
  with_raw_server ~max_response_body_size:0
    "HTTP/1.1 200 OK\r\nContent-Length: 0\r\n\r\n" (fun response _ ->
      match response with
      | Error error ->
          failf "unexpected response error: %a" Choku.Client.Error.pp error
      | Ok response ->
          check string "body" ""
            (Choku.Body.to_string (Choku.Client.Response.body response)))

let test_rejects_non_buffered_request_body () =
  Eio_main.run @@ fun env ->
  let net = Eio.Stdenv.net env in
  let client = Choku.Client.create ~net () in
  let body =
    Choku.Body.Internal.streaming (Eio.Flow.string_source "streaming")
  in
  let request =
    request_ok ~meth:Choku.Method.POST ~url:"http://example.test/" ~body ()
  in
  Eio.Switch.run @@ fun sw ->
  check
    (result reject client_error)
    "error" (Error Choku.Client.Error.Request_body_not_buffered)
    (Choku.Client.request ~sw client request)

let test_response_head_timeout () =
  require_network ();
  Eio_main.run @@ fun env ->
  let net = Eio.Stdenv.net env in
  let clock = Eio.Stdenv.clock env in
  let mono_clock = Eio.Stdenv.mono_clock env in
  let port = available_port () in
  let addr = `Tcp (Eio.Net.Ipaddr.V4.loopback, port) in
  let result = ref None in
  (try
     Eio.Switch.run @@ fun sw ->
     let socket = Eio.Net.listen ~reuse_addr:true ~backlog:1 ~sw net addr in
     Eio.Fiber.fork ~sw (fun () ->
         Eio.Net.run_server socket
           ~on_error:(function
             | Eio.Cancel.Cancelled _ as exn -> raise exn | _ -> ())
           (fun flow _addr ->
             ignore (read_request_head flow : string);
             Eio.Time.sleep clock 0.05;
             Eio.Flow.copy_string
               "HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nok" flow;
             Eio.Flow.shutdown flow `All));
     let rec connect attempts =
       Eio.Switch.run @@ fun client_sw ->
       let client =
         Choku.Client.create ~net ~mono_clock ~response_head_timeout:(Some 0.02)
           ()
       in
       let request =
         request_ok ~meth:Choku.Method.GET
           ~url:(Printf.sprintf "http://127.0.0.1:%d/" port)
           ()
       in
       match Choku.Client.request ~sw:client_sw client request with
       | Error (Choku.Client.Error.Connection_failed _) when attempts > 0 ->
           Eio.Time.sleep clock 0.01;
           connect (attempts - 1)
       | response -> response
     in
     result := Some (connect 100);
     Eio.Switch.fail sw Exit
   with Exit -> ());
  check
    (option (Alcotest.result reject client_error))
    "error"
    (Some (Error (Choku.Client.Error.Timeout Choku.Client.Error.Response_head)))
    !result

let test_response_body_timeout () =
  require_network ();
  Eio_main.run @@ fun env ->
  let net = Eio.Stdenv.net env in
  let clock = Eio.Stdenv.clock env in
  let mono_clock = Eio.Stdenv.mono_clock env in
  let port = available_port () in
  let addr = `Tcp (Eio.Net.Ipaddr.V4.loopback, port) in
  let result = ref None in
  (try
     Eio.Switch.run @@ fun sw ->
     let socket = Eio.Net.listen ~reuse_addr:true ~backlog:1 ~sw net addr in
     Eio.Fiber.fork ~sw (fun () ->
         Eio.Net.run_server socket
           ~on_error:(function
             | Eio.Cancel.Cancelled _ as exn -> raise exn | _ -> ())
           (fun flow _addr ->
             ignore (read_request_head flow : string);
             Eio.Flow.copy_string "HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\n"
               flow;
             Eio.Time.sleep clock 0.05;
             Eio.Flow.copy_string "ok" flow;
             Eio.Flow.shutdown flow `All));
     let rec connect attempts =
       Eio.Switch.run @@ fun client_sw ->
       let client =
         Choku.Client.create ~net ~mono_clock ~response_body_timeout:(Some 0.02)
           ()
       in
       let request =
         request_ok ~meth:Choku.Method.GET
           ~url:(Printf.sprintf "http://127.0.0.1:%d/" port)
           ()
       in
       match Choku.Client.request ~sw:client_sw client request with
       | Error (Choku.Client.Error.Connection_failed _) when attempts > 0 ->
           Eio.Time.sleep clock 0.01;
           connect (attempts - 1)
       | response -> response
     in
     result := Some (connect 100);
     Eio.Switch.fail sw Exit
   with Exit -> ());
  check
    (option (Alcotest.result reject client_error))
    "error"
    (Some (Error (Choku.Client.Error.Timeout Choku.Client.Error.Response_body)))
    !result

let test_tls_handshake_timeout () =
  require_network ();
  Mirage_crypto_rng_unix.use_default ();
  Eio_main.run @@ fun env ->
  let net = Eio.Stdenv.net env in
  let clock = Eio.Stdenv.clock env in
  let mono_clock = Eio.Stdenv.mono_clock env in
  let port = available_port () in
  let addr = `Tcp (Eio.Net.Ipaddr.V4.loopback, port) in
  let result = ref None in
  (try
     Eio.Switch.run @@ fun sw ->
     let socket = Eio.Net.listen ~reuse_addr:true ~backlog:1 ~sw net addr in
     Eio.Fiber.fork ~sw (fun () ->
         Eio.Net.run_server socket
           ~on_error:(function
             | Eio.Cancel.Cancelled _ as exn -> raise exn | _ -> ())
           (fun flow _addr ->
             Eio.Time.sleep clock 0.05;
             Eio.Flow.shutdown flow `All));
     let rec connect attempts =
       Eio.Switch.run @@ fun client_sw ->
       let client =
         Choku.Client.create ~net ~mono_clock ~tls_handshake_timeout:(Some 0.02)
           ()
       in
       let request =
         request_ok ~meth:Choku.Method.GET
           ~url:(Printf.sprintf "https://localhost:%d/" port)
           ()
       in
       match Choku.Client.request ~sw:client_sw client request with
       | Error (Choku.Client.Error.Connection_failed _) when attempts > 0 ->
           Eio.Time.sleep clock 0.01;
           connect (attempts - 1)
       | response -> response
     in
     result := Some (connect 100);
     Eio.Switch.fail sw Exit
   with Exit -> ());
  check
    (option (Alcotest.result reject client_error))
    "error"
    (Some (Error (Choku.Client.Error.Timeout Choku.Client.Error.Tls_handshake)))
    !result

let test_repeated_requests_under_one_switch () =
  require_network ();
  Eio_main.run @@ fun env ->
  let net = Eio.Stdenv.net env in
  let clock = Eio.Stdenv.clock env in
  let port = available_port () in
  let addr = `Tcp (Eio.Net.Ipaddr.V4.loopback, port) in
  let handled = ref 0 in
  try
    Eio.Switch.run @@ fun sw ->
    let socket = Eio.Net.listen ~reuse_addr:true ~backlog:16 ~sw net addr in
    Eio.Fiber.fork ~sw (fun () ->
        Eio.Net.run_server socket
          ~on_error:(function
            | Eio.Cancel.Cancelled _ as exn -> raise exn | _ -> ())
          (fun flow _addr ->
            incr handled;
            ignore (read_request_head flow : string);
            Eio.Flow.copy_string
              "HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nok" flow;
            Eio.Flow.shutdown flow `All));
    Eio.Switch.run @@ fun client_sw ->
    let client = Choku.Client.create ~net () in
    let rec request_once attempts =
      let request =
        request_ok ~meth:Choku.Method.GET
          ~url:(Printf.sprintf "http://127.0.0.1:%d/" port)
          ()
      in
      match Choku.Client.request ~sw:client_sw client request with
      | Error (Choku.Client.Error.Connection_failed _) when attempts > 0 ->
          Eio.Time.sleep clock 0.01;
          request_once (attempts - 1)
      | Ok response ->
          check string "body" "ok"
            (Choku.Body.to_string (Choku.Client.Response.body response))
      | Error error ->
          failf "unexpected response error: %a" Choku.Client.Error.pp error
    in
    for _ = 1 to 20 do
      request_once 100
    done;
    check int "handled" 20 !handled;
    Eio.Switch.fail sw Exit
  with Exit -> ()

let test_https_public_smoke () =
  require_network ();
  Mirage_crypto_rng_unix.use_default ();
  Eio_main.run @@ fun env ->
  let net = Eio.Stdenv.net env in
  Eio.Switch.run @@ fun sw ->
  let client = Choku.Client.create ~net () in
  let request =
    request_ok ~meth:Choku.Method.GET ~url:"https://example.com/" ()
  in
  match Choku.Client.request ~sw client request with
  | Error error ->
      failf "unexpected response error: %a" Choku.Client.Error.pp error
  | Ok response ->
      check int "status" 200
        (Choku.Status.code (Choku.Client.Response.status response))

let () =
  run "client"
    [
      ( "client",
        [
          test_case "request normalizes URL" `Quick test_request_normalizes_url;
          test_case "request normalizes HTTPS URL" `Quick
            test_request_normalizes_https_url;
          test_case "request defaults path and port" `Quick
            test_request_defaults_path_and_port;
          test_case "request defaults HTTPS path and port" `Quick
            test_request_defaults_https_path_and_port;
          test_case "request omits explicit default port from authority" `Quick
            test_request_omits_explicit_default_port_from_authority;
          test_case "request omits explicit HTTPS default port from authority"
            `Quick test_request_omits_explicit_https_default_port_from_authority;
          test_case "request accepts single-label HTTPS host" `Quick
            test_request_accepts_single_label_https_host;
          test_case "request rejects unsupported URL and method" `Quick
            test_request_rejects_unsupported_url_and_method;
          test_case "request replaces headers and body" `Quick
            test_request_replaces_headers_and_body;
          test_case "middleware order and response replacement" `Quick
            test_middleware_order_and_response_replacement;
          test_case "convenience preserves headers and body" `Quick
            test_convenience_preserves_headers_and_body;
          test_case "convenience methods use expected methods" `Quick
            test_convenience_methods_use_expected_methods;
          test_case "fetch preserves arbitrary method" `Quick
            test_fetch_preserves_arbitrary_method;
          test_case "fetch request construction error bypasses middleware"
            `Quick test_fetch_request_construction_error_bypasses_middleware;
          test_case "follow redirects GET chain" `Quick
            test_follow_redirects_get_chain;
          test_case "follow redirects strips sensitive headers cross-origin"
            `Quick test_follow_redirects_strips_sensitive_headers_cross_origin;
          test_case "follow redirects preserves sensitive headers same-origin"
            `Quick test_follow_redirects_preserves_sensitive_headers_same_origin;
          test_case "follow redirects strips Location fragment" `Quick
            test_follow_redirects_strips_location_fragment;
          test_case "follow redirects 303 rewrites to GET" `Quick
            test_follow_redirects_303_rewrites_to_get;
          test_case "follow redirects does not rewrite POST 302" `Quick
            test_follow_redirects_does_not_rewrite_post_302;
          test_case "follow redirects reports missing Location" `Quick
            test_follow_redirects_reports_missing_location;
          test_case "follow redirects reports too many redirects" `Quick
            test_follow_redirects_reports_too_many_redirects;
          test_case "create rejects invalid limits" `Quick
            test_create_rejects_invalid_limits;
          test_case "TLS CA file rejects empty file" `Quick
            test_tls_ca_file_rejects_empty_file;
          test_case "request wire and fixed response" `Quick
            test_request_wire_and_fixed_response;
          test_case "follow redirects over transport" `Quick
            test_follow_redirects_over_transport;
          test_case "chunked response skips informational" `Quick
            test_chunked_response_skips_informational;
          test_case "HEAD response is bodyless" `Quick
            test_head_response_is_bodyless;
          test_case "rejects ambiguous response framing" `Quick
            test_rejects_ambiguous_response_framing;
          test_case "rejects unsupported transfer-encoding" `Quick
            test_rejects_unsupported_transfer_encoding;
          test_case "rejects invalid content-length" `Quick
            test_rejects_invalid_content_length;
          test_case "rejects unsupported upgrade" `Quick
            test_rejects_unsupported_upgrade;
          test_case "rejects response body too large" `Quick
            test_rejects_response_body_too_large;
          test_case "zero response body limit allows empty only" `Quick
            test_zero_response_body_limit_allows_empty_only;
          test_case "rejects non-buffered request body" `Quick
            test_rejects_non_buffered_request_body;
          test_case "response head timeout" `Quick test_response_head_timeout;
          test_case "response body timeout" `Quick test_response_body_timeout;
          test_case "TLS handshake timeout" `Quick test_tls_handshake_timeout;
          test_case "repeated requests under one switch" `Quick
            test_repeated_requests_under_one_switch;
          test_case "HTTPS public smoke" `Quick test_https_public_smoke;
        ] );
    ]
