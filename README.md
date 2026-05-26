# Choku

[![CI](https://github.com/dakatsuka/choku/actions/workflows/ci.yml/badge.svg)](https://github.com/dakatsuka/choku/actions/workflows/ci.yml)

Choku is an OCaml 5.4 HTTP server project built around Eio-native direct-style
IO.

The name "Choku" means "direct" in Japanese.

## Status

Choku is in early design and implementation. The first implementation
milestone is a minimal HTTP/1.1 server over plain TCP with:

- HTTP/1.1 persistent connection behavior;
- buffered and replayable request bodies by default;
- opt-in streaming request bodies;
- `Content-Length` and `Transfer-Encoding: chunked` request bodies;
- a low-level `Handler.t = Request.t -> Response.t` contract;
- middleware as `Handler.t -> Handler.t`;
- an optional method-and-path router;
- buffered and streaming `multipart/form-data` helpers;
- a minimal HTTP/1.1 client with plain HTTP and HTTPS;
- no HTTP/2 or HTTP/3 public APIs yet.

## Usage

Add `choku`, `eio`, and `eio_main` to your executable libraries:

```lisp
(executable
 (name app)
 (libraries choku eio eio_main))
```

### Server

Run a minimal server:

```ocaml
let handler request =
  let open Choku in
  match Request.(meth request, path request) with
  | Method.GET, "/" -> Response.text "hello from choku\n"
  | _ -> Response.text ~status:Status.not_found "not found\n"

let () =
  let open Choku in
  Eio_main.run @@ fun env ->
  Eio.Switch.run @@ fun sw ->
  let net = Eio.Stdenv.net env in
  let addr = `Tcp (Eio.Net.Ipaddr.V4.loopback, 8080) in
  let server = Server.create ~handler () in
  Server.run ~sw ~net ~addr server
```

HTTP/1.1 keep-alive is enabled by default. Buffered requests can reuse the same
connection sequentially, and Choku writes `Connection: keep-alive` when it will
wait for another request. Set `~keep_alive:false` if you need one response per
connection:

```ocaml
let server = Choku.Server.create ~keep_alive:false ~handler ()
```

When exposing Choku directly, consider setting `~request_head_timeout:(Some
seconds)` so idle keep-alive connections do not hold fibers indefinitely.

For small handlers, you can also pattern-match on `Request.path_segments`.
Router patterns such as `"/users/:id"` are only interpreted by `Choku.Router`;
direct pattern matching sees paths as ordinary raw segments.

```ocaml
let handler request =
  let open Choku in
  match Request.(meth request, path_segments request) with
  | Method.GET, [ "users"; id ] when not (String.equal id "") ->
      Response.text (Printf.sprintf "user %s\n" id)
  | Method.GET, [ "health" ] ->
      Response.text "ok\n"
  | _ ->
      Response.text ~status:Status.not_found "not found\n"
```

Use `Choku.Query` when a handler needs decoded URL query parameters:

```ocaml
let page request =
  let open Choku in
  match Query.of_request request with
  | Ok query ->
      let value = Query.get_or ~default:"1" "page" query in
      Response.text (Printf.sprintf "page %s\n" value)
  | Error error ->
      Response.text ~status:Status.bad_request
        (Format.asprintf "%a\n" Query.pp_error error)
```

Use `Choku.Cookie` to read request cookies and append `Set-Cookie` response
headers:

```ocaml
let remember request =
  let open Choku in
  let name = Option.value ~default:"guest" (Cookie.get_unique "name" request) in
  Response.text (Printf.sprintf "hello %s\n" name)
  |> Cookie.set ~path:"/" ~secure:true ~http_only:true ~same_site:Cookie.Lax
       "seen" "1"
```

Use the router when you want path parameters and first-match routing:

```ocaml
let router =
  let open Choku in
  Router.empty
  |> Router.get "/" (fun _ctx -> Response.text "hello\n")
  |> Router.get "/users/:id" (fun ctx ->
         match Router.Params.get "id" ctx.params with
         | None -> Response.text ~status:Status.not_found "not found\n"
         | Some id -> Response.text (Printf.sprintf "user %s\n" id))

let server =
  let open Choku in
  Server.create ~handler:(Router.to_handler router) ()
```

The router automatically handles `HEAD` requests with matching `GET` routes
unless an explicit `HEAD` route exists. If a path exists but the request method
is not allowed, it returns `405 Method Not Allowed` with an `Allow` header.

For router-backed servers, individual routes can opt into streaming request
bodies while other routes stay buffered:

```ocaml
let upload ctx =
  let open Choku in
  let user_id = Router.Params.get "id" ctx.params in
  match Multipart.Streaming.iter_request ctx.request ~on_part:save_part with
  | Ok () ->
      Response.text
        (Printf.sprintf "uploaded for user %s\n"
           (Option.value ~default:"unknown" user_id))
  | Error error ->
      Response.text ~status:Status.bad_request
        (Format.asprintf "%a\n" Multipart.pp_error error)

let router =
  let open Choku in
  Router.empty
  |> Router.get "/health" (fun _ctx -> Response.text "ok\n")
  |> Router.post
       ~request_body_mode:Request_body_mode.Streaming
       "/users/:id/avatar"
       upload

let server =
  let open Choku in
  Server.create_router router
```

Parse buffered multipart forms for small uploads:

```ocaml
let upload_buffered request =
  let open Choku in
  match Multipart.of_request request with
  | Error error ->
      Response.text ~status:Status.bad_request
        (Format.asprintf "%a\n" Multipart.pp_error error)
  | Ok multipart -> (
      match Multipart.get "avatar" multipart with
      | None ->
          Response.text ~status:Status.bad_request "missing avatar\n"
      | Some part ->
          let bytes = Multipart.Part.body part |> Body.to_string in
          Response.text
            (Printf.sprintf "received %d bytes\n" (String.length bytes)))
```

Use streaming request bodies for large multipart uploads. Streaming can be
enabled for a whole handler-backed server with `Server.create
~request_body_mode:Server.Streaming`, or for individual router routes with
`Router.post ~request_body_mode:Request_body_mode.Streaming` and
`Server.create_router`. Streaming part sources are valid only during the
`on_part` callback. When saving uploads, pass an application-owned temporary
directory and `Eio.Stdenv.secure_random env` to the tempfile helper.

Choose server-wide streaming when every route is expected to consume a streaming
body:

```ocaml
let server =
  let open Choku in
  Server.create ~request_body_mode:Server.Streaming
    ~handler:(upload_streaming ~upload_dir ~random) ()
```

Choose route-level streaming when most routes should stay buffered and only
upload routes need streaming bodies:

```ocaml
let router =
  let open Choku in
  Router.empty
  |> Router.get "/health" (fun _ctx -> Response.text "ok\n")
  |> Router.post
       ~request_body_mode:Request_body_mode.Streaming
       "/upload"
       upload

let server =
  let open Choku in
  Server.create_router router
```

```ocaml
let upload_streaming ~upload_dir ~random request =
  let open Choku in
  match
    Multipart.Streaming.iter_request request
      ~on_part:(fun part source ->
        match Multipart.Streaming.filename part with
        | None -> Eio.Flow.copy source (Eio.Flow.buffer_sink (Buffer.create 0))
        | Some filename ->
            let saved =
              Multipart.Tempfile.save_source ~dir:upload_dir ~random
                ~original_filename:filename source
            in
            Printf.printf "received %d bytes\n%!"
              (Multipart.Tempfile.size saved))
  with
  | Ok () -> Response.text "uploaded\n"
  | Error error ->
      Response.text ~status:Status.bad_request
        (Format.asprintf "%a\n" Multipart.pp_error error)

let server =
  let open Choku in
  Server.create ~request_body_mode:Server.Streaming
    ~handler:(upload_streaming ~upload_dir ~random) ()
```

When using the router, prefer `Server.create_router` and set
`~request_body_mode:Choku.Request_body_mode.Streaming` only on upload routes.
Routes without `~request_body_mode` keep the default buffered body behavior.
Route-level body-mode selection is not available when passing
`Router.to_handler router` to `Server.create ~handler`.

For a custom dispatcher that does not use `Router.t`, select body mode from the
parsed request head before the request body is read:

```ocaml
let request_body_mode head =
  let open Choku in
  match Request_head.(meth head, path head) with
  | Method.POST, "/upload" -> Request_body_mode.Streaming
  | _ -> Request_body_mode.Buffered

let server =
  Choku.Server.create_with_request_body_selector
    ~request_body_mode
    ~handler
    ()
```

Stream large or generated responses without buffering the whole body:

```ocaml
let download _request =
  let open Choku in
  Response.stream
    ~headers:(Headers.set "content-type" "application/octet-stream" Headers.empty)
    (fun sink ->
      List.iter (fun chunk -> Eio.Flow.copy_string chunk sink) chunks)
```

When `~content_length` is omitted, Choku uses HTTP/1.1 chunked transfer coding.
If the length is known, pass `~content_length:n` and write exactly `n` bytes.
Choku owns `Content-Length`, `Transfer-Encoding`, and `Connection` while writing
HTTP/1.1 responses, so application-provided values for those headers are
replaced.

The stream callback runs after the handler returns, in the connection fiber. The
sink is valid only during the callback, so open files and other stream-scoped
resources inside the callback:

```ocaml
let file_response path =
  Choku.Response.stream (fun sink ->
      Eio.Path.with_open_in path (fun source -> Eio.Flow.copy source sink))
```

If the callback raises or writes a different number of bytes than the declared
`~content_length`, Choku closes the connection. `HEAD`, `1xx`, `204`, and `304`
responses do not invoke the callback because no response body is written.

The repository includes runnable examples:

```sh
dune exec choku-hello
dune exec choku-upload-streaming
dune exec examples/input_binding.exe
```

`examples/input_binding.exe` shows one application-side pattern for composing
path parameters, query parameters, and URL-encoded form fields with OCaml
`Result` binding operators.

For deployment behind nginx, AWS ALB, Classic Load Balancer HTTP(S), or a
similar reverse proxy, see
[Reverse Proxy Deployment](docs/product-specs/reverse-proxy-deployment.md).

### Client

Send a simple HTTP client request:

```ocaml
let () =
  Eio_main.run @@ fun env ->
  Eio.Switch.run @@ fun sw ->
  let open Choku in
  let net = Eio.Stdenv.net env in
  let client = Client.create ~net () in
  match Client.get ~sw client ~url:"http://example.test/status" () with
  | Error error ->
      Format.eprintf "client error: %a@." Client.Error.pp error
  | Ok response ->
      Printf.printf "status: %d\n"
        (Status.code (Client.Response.status response));
      Printf.printf "%s"
        (Body.to_string (Client.Response.body response))
```

The client accepts absolute `http://` and `https://` URLs. It opens one
connection per request, sends `Connection: close`, and returns a fully buffered
response. HTTPS uses TLS 1.2 or newer with system CA roots by default. The first
HTTPS milestone supports DNS host names only; IP address literals in
`https://` URLs are rejected.

The default response limits are 16 KiB for the response head and 1 MiB for the
response body:

```ocaml
let client =
  Choku.Client.create
    ~net
    ~max_response_head_size:16_384
    ~max_response_body_size:1_048_576
    ()
```

Timeouts are disabled by default. Pass the Eio monotonic clock and finite
positive second values to bound individual transport phases:

```ocaml
let client =
  Choku.Client.create
    ~net
    ~mono_clock:(Eio.Stdenv.mono_clock env)
    ~connect_timeout:(Some 5.0)
    ~tls_handshake_timeout:(Some 5.0)
    ~request_write_timeout:(Some 5.0)
    ~response_head_timeout:(Some 10.0)
    ~response_body_timeout:(Some 30.0)
    ()
```

Programs that make HTTPS requests must initialize the Mirage Crypto RNG before
using TLS. Add `mirage-crypto-rng.unix` to the executable libraries:

```lisp
(executable
 (name app)
 (libraries choku eio eio_main mirage-crypto-rng.unix))
```

Then initialize the RNG before entering the Eio main loop and send an HTTPS
request:

```ocaml
let () =
  Mirage_crypto_rng_unix.use_default ();
  Eio_main.run @@ fun env ->
  Eio.Switch.run @@ fun sw ->
  let open Choku in
  let net = Eio.Stdenv.net env in
  let client = Client.create ~net () in
  match Client.Request.make ~meth:Method.GET ~url:"https://example.com/" () with
  | Error error ->
      Format.eprintf "request error: %a@." Client.Error.pp error
  | Ok request -> (
      match Client.request ~sw client request with
      | Error error ->
          Format.eprintf "client error: %a@." Client.Error.pp error
      | Ok response ->
          Printf.printf "status: %d\n"
            (Status.code (Client.Response.status response)))
```

Use `Client.Tls.ca_file` or `Client.Tls.ca_dir` when an application needs a
custom trust store:

```ocaml
let client_with_ca root net =
  match Choku.Client.Tls.ca_file root with
  | Error error -> Error error
  | Ok tls -> Ok (Choku.Client.create ~tls ~net ())
```

Try the client with the local fetch example:

```sh
dune exec examples/client_fetch.exe -- https://example.com/
```

It prints the response status and buffered body size:

```text
status: 200, body bytes: 528
```

The same helper accepts any supported absolute HTTP or HTTPS URL:

```sh
dune exec examples/client_fetch.exe -- https://blog.dakatsuka.jp/
```

Pass `--headers` or `--body` to inspect the buffered response:

```sh
dune exec examples/client_fetch.exe -- --headers https://example.com/
dune exec examples/client_fetch.exe -- --body https://example.com/
```

Send a buffered request body by passing `Body.string` and ordinary headers when
building the request. Choku owns wire framing headers such as `Host`,
`Content-Length`, `Transfer-Encoding`, and `Connection`, so user-provided values
for those headers are replaced during serialization.

```ocaml
let post_json sw net =
  let open Choku in
  let client = Client.create ~net () in
  let headers =
    Headers.empty
    |> Headers.set "content-type" "application/json"
    |> Headers.set "accept" "application/json"
  in
  Client.post ~sw client ~headers ~body:(Body.string {|{"name":"choku"}|})
    ~url:"http://example.test/widgets" ()
```

Use client middleware for request policies such as authentication, logging, or
test doubles:

```ocaml
let bearer token next request =
  request
  |> Choku.Client.Request.with_header "authorization" ("Bearer " ^ token)
  |> next

let client =
  Choku.Client.create
    ~net
    ~middlewares:[ bearer token ]
    ()
```

Middleware is applied in list order: for `[a; b]`, `a` sees the request before
`b` and sees the response or error after `b`.

Redirect following is opt-in middleware:

```ocaml
let client =
  Choku.Client.create
    ~net
    ~middlewares:[ Choku.Client.Middleware.follow_redirects () ]
    ()
```

The middleware follows up to five redirects by default. Pass `~max_redirects`
to change the limit. Cross-origin redirects strip `Authorization`, `Cookie`, and
`Proxy-Authorization`.

Small reverse proxy examples are available under `examples/`:

```sh
dune exec examples/hello.exe
dune exec examples/reverse_proxy.exe -- --listen-port 8081 --upstream http://127.0.0.1:8080
dune exec examples/reverse_proxy_rewrite.exe -- --listen-port 8082 --upstream http://127.0.0.1:8080
```

## Development

Expected local checks:

```sh
dune build @all
dune runtest
dune build @fmt
dune build @check
dune build @install
opam lint choku.opam
```

Network integration tests are disabled by default in local sandboxed
environments. Run them explicitly when sockets are available:

```sh
CHOKU_RUN_NETWORK_TESTS=1 dune exec test/test_server.exe
CHOKU_RUN_NETWORK_TESTS=1 dune exec test/test_client.exe
```

The project uses:

- dune for build orchestration;
- Alcotest for unit tests;
- ocamlformat for formatting;
- Eio for effects-based IO and structured concurrency.

## Documentation

Start with [AGENTS.md](AGENTS.md) for agent-facing workflow guidance.

Key design documents:

- [Project Charter](docs/product-specs/project-charter.md)
- [Minimal Server API](docs/product-specs/minimal-server-api.md)
- [Minimal HTTP/1.1 Server Milestone](docs/product-specs/minimal-http1-server.md)
- [Minimal HTTP Client](docs/product-specs/minimal-http-client.md)
- [HTTPS Client](docs/product-specs/https-client.md)
- [Minimal Server, Handler, and Middleware API](docs/design-docs/minimal-server-handler-middleware-api.md)
- [Project Layout and Tooling](docs/design-docs/project-layout-and-tooling.md)
