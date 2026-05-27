# Testing Support

## Status

Accepted

## Problem

Users building applications with Choku need to test handlers, routers,
middleware, outbound client policies, and full server/client behavior without
reimplementing fragile harness code in every project.

Choku already exposes value constructors and handler contracts that make many
tests possible without sockets. The missing product surface is an official,
small test-support library that documents the intended testing style and
provides stable Eio harness helpers for system-style tests.

## Goals

- Let users unit-test handlers and routers without opening network sockets.
- Let users unit-test client middleware and outbound policies with fake client
  handlers.
- Let users run loopback server/client system tests with deterministic listener
  setup and cleanup.
- Keep test helpers independent of Alcotest, OUnit, or any specific test
  framework.
- Keep the main `choku` runtime API free of test-framework dependencies.
- Provide helpers for constructing streaming request bodies in tests.

## Non-Goals

- Browser-level end-to-end testing.
- A test runner or assertion library.
- Mocking DNS, TLS certificate stores, clocks, or filesystems.
- A full HTTP fixture server DSL.
- Promising stable access to Choku internal parser or serializer modules.

## Requirements

- Test support is exposed as the `choku.test` library with OCaml module
  `Choku_test`.
- `choku.test` may depend on `choku` and Eio, but must not depend on a test
  framework.
- Users can create common server requests with a concise helper that delegates
  validation to `Choku.Request.make`.
- Users can read buffered server and client response bodies with concise
  helpers.
- Users can create a streaming `Choku.Body.t` from test bytes. The resulting
  body must be single-consumption and usable with `Body.to_string_limited` and
  APIs that consume `Body.with_source`.
- Users can run a Choku server against a pre-bound Eio listener on loopback with
  port `0`, inspect the actual selected address, and receive a base URL for
  client requests.
- The loopback server helper must attach server resources to an Eio switch and
  cancel/close them when the callback returns or raises.
- Users can send raw HTTP bytes to the running test server and collect the raw
  response bytes.
- The core server exposes a listener-based run entry point so test harnesses can
  bind a socket first, discover the actual address, and then start accepting
  connections without a port-selection race.

## Public Contracts

Expected test-support API:

```ocaml
module Choku_test : sig
  val request :
    ?meth:Choku.Method.t ->
    ?target:string ->
    ?headers:Choku.Headers.t ->
    ?body:Choku.Body.t ->
    unit ->
    Choku.Request.t

  val response_body_string : Choku.Response.t -> string
  val client_response_body_string : Choku.Client.Response.t -> string

  val streaming_body : ?content_length:int -> string -> Choku.Body.t

  val raw_request :
    sw:Eio.Switch.t ->
    net:_ Eio.Net.t ->
    addr:Eio.Net.Sockaddr.stream ->
    string ->
    string

  val with_server :
    ?mono_clock:Eio.Time.Mono.ty Eio.Resource.t ->
    ?addr:Eio.Net.Sockaddr.stream ->
    net:_ Eio.Net.t ->
    Choku.Server.t ->
    (sw:Eio.Switch.t ->
     addr:Eio.Net.Sockaddr.stream ->
     base_url:string ->
     'a) ->
    'a
end
```

Expected server harness API:

```ocaml
module Choku.Server : sig
  val run_listener :
    sw:Eio.Switch.t ->
    ?mono_clock:Eio.Time.Mono.ty Eio.Resource.t ->
    socket:_ Eio.Net.listening_socket ->
    t ->
    unit
end
```

`with_server` defaults to
`` `Tcp (Eio.Net.Ipaddr.V4.loopback, 0) ``. For TCP listeners, `base_url` is
an `http://` URL using the actual listening address and port. Unix-domain
listener base URLs are out of scope for the first helper and may raise
`Invalid_argument`.

## Examples

Handler unit test without sockets:

```ocaml
let request = Choku_test.request ~target:"/health" () in
let response = Choku.Server.handle server request in
assert (Choku_test.response_body_string response = "ok\n")
```

System-style test with a real server and client:

```ocaml
Eio_main.run @@ fun env ->
let net = Eio.Stdenv.net env in
let server = Choku.Server.create ~handler () in
Choku_test.with_server ~net server @@ fun ~sw ~addr:_ ~base_url ->
let client = Choku.Client.create ~net () in
let request =
  Choku.Client.Request.make
    ~meth:Choku.Method.GET
    ~url:(base_url ^ "/health")
    ()
  |> Result.get_ok
in
match Choku.Client.request ~sw client request with
| Ok response -> assert (Choku_test.client_response_body_string response = "ok\n")
| Error _ -> assert false
```

## Open Questions

- Should framework-specific `Alcotest.testable` values live in a separate
  optional library such as `choku.test.alcotest`?
- Should future helpers support local TLS fixtures once HTTPS server support
  exists?
