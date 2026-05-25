# HTTPS Client

## Status

Accepted

## Problem

The minimal HTTP client only supports plain `http://` URLs. Most practical
service-to-service and public Internet integrations require HTTPS with server
certificate verification.

## Goals

- Support `https://` absolute URLs in `Choku.Client`.
- Preserve the existing direct-style Eio client API.
- Reuse the existing HTTP/1.1 request serialization, response parsing, body
  buffering, limits, and middleware behavior over TLS.
- Verify server certificates by default.
- Use SNI and hostname verification based on the URL host.
- Keep HTTPS errors explicit and printable.

## Non-Goals

- HTTP/2 or HTTP/3.
- ALPN negotiation as user-visible behavior.
- Connection pooling or TLS session reuse.
- Redirect following.
- Proxy support or CONNECT.
- Client certificates and mutual TLS.
- Streaming request uploads or streaming responses.
- Custom cipher-suite or certificate-pinning policy in the first HTTPS
  milestone.

## Requirements

- `Client.Request.make` accepts absolute `https://` URLs.
- The default HTTPS port is `443`.
- An explicit `:443` port is omitted from normalized authority. Non-default
  ports are preserved in authority and `Host`.
- The first HTTPS milestone supports DNS host names only. IPv4 and IPv6 address
  literals in `https://` URLs are rejected with an explicit URL error instead
  of disabling or weakening certificate verification.
- The request target remains origin-form: path plus optional query.
- `http://` behavior remains unchanged.
- Unsupported schemes other than `http` and `https` still return
  `Unsupported_scheme`.
- The client opens one TCP connection per request.
- For `https://`, the client performs a TLS client handshake before writing the
  HTTP/1.1 request.
- The TLS peer name and SNI are derived from the URL host, not from
  user-provided headers.
- Server certificate verification is enabled by default.
- A client can be configured with system CA roots, a CA file, or a CA directory.
- TLS handshakes use TLS 1.2 or newer.
- The transport still owns `Host`, `Content-Length`, `Transfer-Encoding`, and
  `Connection` headers.
- The client sends `Connection: close` and closes the underlying flow after
  each request attempt.
- Middleware observes the same `Client.Request.t` and `Client.Response.t`
  values regardless of scheme.
- Eio cancellation is re-raised and is not converted to a client error.
- TLS configuration and handshake failures return explicit `Client.Error.t`
  values.
- TLS handshake timeout, when configured, returns
  `Client.Error.Timeout Tls_handshake`.
- Choku documents that HTTPS use requires Mirage Crypto RNG seeding while TLS is
  active. Examples use `Mirage_crypto_rng_unix.use_default ()`.

## Public Contracts

`Client.Request` exposes the parsed URL scheme:

```ocaml
module Client : sig
  module Request : sig
    type scheme = Http | Https

    val scheme : t -> scheme
  end
end
```

`Client.Tls` exposes a small TLS policy surface:

```ocaml
module Client : sig
  module Tls : sig
    type t

    val system : unit -> (t, Error.t) result
    val ca_file : _ Eio.Path.t -> (t, Error.t) result
    val ca_dir : _ Eio.Path.t -> (t, Error.t) result
  end

  val create :
    ?tls:Tls.t ->
    ?max_response_head_size:int ->
    ?max_response_body_size:int ->
    ?middlewares:Middleware.t list ->
    net:'a Eio.Net.t ->
    unit ->
    t
end
```

`Client.create` uses system CA roots by default for HTTPS. If system CA root
loading fails, `Client.create` does not raise; the client stores the
`(Tls.t, Error.t) result` and returns the error only when an HTTPS request is
made. Explicit `~tls` values are already loaded policies and cannot represent a
deferred loading error.

## Examples

```ocaml
let fetch sw net =
  let client = Choku.Client.create ~net () in
  match
    Choku.Client.Request.make
      ~meth:Choku.Method.GET
      ~url:"https://example.com/"
      ()
  with
  | Error error -> Error error
  | Ok request -> Choku.Client.request ~sw client request
```

For applications that need a custom CA file:

```ocaml
let client root net =
  match Choku.Client.Tls.ca_file root with
  | Error error -> Error error
  | Ok tls -> Ok (Choku.Client.create ~tls ~net ())
```

## Open Questions

None.
