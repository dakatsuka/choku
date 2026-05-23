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

let with_server handler f =
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
  let server = Camelio.Server.create ~max_request_body_size:4 ~handler () in
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

let test_run_bad_request () =
  require_network ();
  let response =
    with_server
      (fun _ -> fail "handler should not run")
      (request "GET /bad path HTTP/1.1\r\n\r\n")
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
          test_case "run bad request" `Quick test_run_bad_request;
          test_case "run payload too large" `Quick test_run_payload_too_large;
          test_case "run handler exception" `Quick test_run_handler_exception;
        ] );
    ]
