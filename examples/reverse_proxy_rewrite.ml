let hop_by_hop_headers =
  [
    "connection";
    "keep-alive";
    "proxy-authenticate";
    "proxy-authorization";
    "proxy-connection";
    "te";
    "trailer";
    "transfer-encoding";
    "upgrade";
  ]

let remove_hop_by_hop headers =
  List.fold_left
    (fun headers name -> Choku.Headers.remove name headers)
    headers hop_by_hop_headers

let upstream_url base target =
  let base =
    if String.ends_with ~suffix:"/" base then
      String.sub base 0 (String.length base - 1)
    else base
  in
  base ^ target

let gateway_error error =
  Choku.Response.text ~status:Choku.Status.bad_gateway
    (Format.asprintf "upstream error: %a\n" Choku.Client.Error.pp error)

let forwarded_headers request =
  request |> Choku.Request.headers |> remove_hop_by_hop
  |> Choku.Headers.set "x-forwarded-by" "choku-rewrite-example"
  |> Choku.Headers.set "x-forwarded-host"
       (Option.value
          (Choku.Headers.get "host" (Choku.Request.headers request))
          ~default:"")
  |> Choku.Headers.set "x-forwarded-proto" "http"

let is_text_response headers =
  match Choku.Headers.get "content-type" headers with
  | None -> false
  | Some content_type ->
      content_type |> String.lowercase_ascii |> String.trim
      |> String.starts_with ~prefix:"text/"

let rewrite_response response =
  let headers =
    response |> Choku.Client.Response.headers |> remove_hop_by_hop
    |> Choku.Headers.set "x-proxied-by" "choku"
  in
  let body = Choku.Body.to_string (Choku.Client.Response.body response) in
  let body =
    if
      Choku.Status.code (Choku.Client.Response.status response) = 200
      && is_text_response headers
    then "proxied by choku\n\n" ^ body
    else body
  in
  Choku.Response.make ~headers ~body:(Choku.Body.string body)
    (Choku.Client.Response.status response)

let make_handler ~sw ~client ~upstream =
 fun request ->
  let url = upstream_url upstream (Choku.Request.target request) in
  let headers = forwarded_headers request in
  let body = Choku.Request.body request in
  match
    Choku.Client.Request.make ~headers ~body
      ~meth:(Choku.Request.meth request)
      ~url ()
  with
  | Error error -> gateway_error error
  | Ok outbound -> (
      match Choku.Client.request ~sw client outbound with
      | Error error -> gateway_error error
      | Ok response -> rewrite_response response)

let () =
  let listen_port = ref 8082 in
  let upstream = ref "http://127.0.0.1:8080" in
  let usage =
    "Usage: reverse_proxy_rewrite [--listen-port PORT] [--upstream URL]\n\
     Forward requests while adding forwarding headers and rewriting responses."
  in
  let specs =
    [
      ("--listen-port", Arg.Set_int listen_port, " Port to listen on");
      ("--upstream", Arg.Set_string upstream, " Upstream origin URL");
    ]
  in
  Arg.parse specs
    (fun value -> raise (Arg.Bad ("unexpected argument: " ^ value)))
    usage;
  Mirage_crypto_rng_unix.use_default ();
  Eio_main.run @@ fun env ->
  Eio.Switch.run @@ fun sw ->
  let net = Eio.Stdenv.net env in
  let mono_clock = Eio.Stdenv.mono_clock env in
  let client =
    Choku.Client.create ~net ~mono_clock ~connect_timeout:(Some 5.0)
      ~tls_handshake_timeout:(Some 5.0) ~request_write_timeout:(Some 5.0)
      ~response_head_timeout:(Some 10.0) ~response_body_timeout:(Some 30.0) ()
  in
  let handler = make_handler ~sw ~client ~upstream:!upstream in
  let server = Choku.Server.create ~handler () in
  let addr = `Tcp (Eio.Net.Ipaddr.V4.loopback, !listen_port) in
  Format.printf "rewrite proxy listening on http://127.0.0.1:%d -> %s@."
    !listen_port !upstream;
  Choku.Server.run ~sw ~net ~addr server
