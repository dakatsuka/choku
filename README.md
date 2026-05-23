# Camelio

[![CI](https://github.com/dakatsuka/camelio/actions/workflows/ci.yml/badge.svg)](https://github.com/dakatsuka/camelio/actions/workflows/ci.yml)

Camelio is an OCaml 5.4 HTTP server project built around Eio-native direct-style
IO.

> A pure Eio HTTP server for OCaml 5.

## Status

Camelio is in early design and implementation. The first implementation
milestone is a minimal HTTP/1.1 server over plain TCP with:

- `Connection: close` behavior;
- buffered and replayable request bodies by default;
- opt-in streaming request bodies;
- a low-level `Handler.t = Request.t -> Response.t` contract;
- middleware as `Handler.t -> Handler.t`;
- an optional method-and-path router;
- buffered and streaming `multipart/form-data` helpers;
- no HTTP Client, TLS, HTTP/2, or HTTP/3 public APIs yet.

## Usage

Add `camelio`, `eio`, and `eio_main` to your executable libraries:

```lisp
(executable
 (name app)
 (libraries camelio eio eio_main))
```

Run a minimal server:

```ocaml
let handler request =
  let open Camelio in
  match Request.(meth request, path request) with
  | Method.GET, "/" -> Response.text "hello from camelio\n"
  | _ -> Response.text ~status:Status.not_found "not found\n"

let () =
  let open Camelio in
  Eio_main.run @@ fun env ->
  Eio.Switch.run @@ fun sw ->
  let net = Eio.Stdenv.net env in
  let addr = `Tcp (Eio.Net.Ipaddr.V4.loopback, 8080) in
  let server = Server.create ~handler () in
  Server.run ~sw ~net ~addr server
```

For small handlers, you can also split `Request.path` yourself. Router patterns
such as `"/users/:id"` are only interpreted by `Camelio.Router`; direct pattern
matching sees paths as ordinary strings.

```ocaml
let handler request =
  let open Camelio in
  match Request.(meth request, path request |> String.split_on_char '/') with
  | Method.GET, [ ""; "users"; id ] ->
      Response.text (Printf.sprintf "user %s\n" id)
  | Method.GET, [ ""; "health" ] ->
      Response.text "ok\n"
  | _ ->
      Response.text ~status:Status.not_found "not found\n"
```

Use the router when you want path parameters and first-match routing:

```ocaml
let router =
  let open Camelio in
  Router.empty
  |> Router.get "/" (fun _ _ -> Response.text "hello\n")
  |> Router.get "/users/:id" (fun params _ ->
         match Router.Params.get "id" params with
         | None -> Response.text ~status:Status.not_found "not found\n"
         | Some id -> Response.text (Printf.sprintf "user %s\n" id))

let server =
  let open Camelio in
  Server.create ~handler:(Router.to_handler router) ()
```

For router-backed servers, individual routes can opt into streaming request
bodies while other routes stay buffered:

```ocaml
let upload params request =
  let open Camelio in
  let user_id = Router.Params.get "id" params in
  match Multipart.Streaming.iter_request request ~on_part:save_part with
  | Ok () ->
      Response.text
        (Printf.sprintf "uploaded for user %s\n"
           (Option.value ~default:"unknown" user_id))
  | Error error ->
      Response.text ~status:Status.bad_request
        (Format.asprintf "%a\n" Multipart.pp_error error)

let router =
  let open Camelio in
  Router.empty
  |> Router.get "/health" (fun _ _ -> Response.text "ok\n")
  |> Router.post
       ~request_body_mode:Request_body_mode.Streaming
       "/users/:id/avatar"
       upload

let server =
  let open Camelio in
  Server.create_router router
```

Parse buffered multipart forms for small uploads:

```ocaml
let upload_buffered request =
  let open Camelio in
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
  let open Camelio in
  Server.create ~request_body_mode:Server.Streaming
    ~handler:(upload_streaming ~upload_dir ~random) ()
```

Choose route-level streaming when most routes should stay buffered and only
upload routes need streaming bodies:

```ocaml
let router =
  let open Camelio in
  Router.empty
  |> Router.get "/health" (fun _ _ -> Response.text "ok\n")
  |> Router.post
       ~request_body_mode:Request_body_mode.Streaming
       "/upload"
       upload

let server =
  let open Camelio in
  Server.create_router router
```

```ocaml
let upload_streaming ~upload_dir ~random request =
  let open Camelio in
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
  let open Camelio in
  Server.create ~request_body_mode:Server.Streaming
    ~handler:(upload_streaming ~upload_dir ~random) ()
```

When using the router, prefer `Server.create_router` and set
`~request_body_mode:Camelio.Request_body_mode.Streaming` only on upload routes.
Routes without `~request_body_mode` keep the default buffered body behavior.
Route-level body-mode selection is not available when passing
`Router.to_handler router` to `Server.create ~handler`.

The repository includes runnable examples:

```sh
dune exec camelio-hello
dune exec camelio-upload-streaming
```

## Development

Expected local checks:

```sh
dune build @all
dune runtest
dune build @fmt
dune build @check
dune build @install
opam lint camelio.opam
```

Network integration tests are disabled by default in local sandboxed
environments. Run them explicitly when sockets are available:

```sh
CAMELIO_RUN_NETWORK_TESTS=1 dune exec test/test_server.exe
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
- [Minimal Server, Handler, and Middleware API](docs/design-docs/minimal-server-handler-middleware-api.md)
- [Project Layout and Tooling](docs/design-docs/project-layout-and-tooling.md)
