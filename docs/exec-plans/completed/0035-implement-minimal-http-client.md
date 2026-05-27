# Implement Minimal HTTP Client

## Status

Completed

## Objective

Implement Choku's first HTTP Client milestone from the accepted design: a small
plain HTTP/1.1 client with separate client request/response types, client
middleware, one request per connection, and fully buffered responses.

## Context

- [Minimal HTTP Client](../../product-specs/minimal-http-client.md)
- [Minimal HTTP Client Design](../../design-docs/minimal-http-client.md)
- [Design Minimal HTTP Client](../completed/0034-design-minimal-http-client.md)
- [Minimal Server API](../../product-specs/minimal-server-api.md)

## Clarifications

- Keep `Client.Request.t` and `Client.Response.t` separate from server
  `Request.t` and `Response.t`.
- Implement `Client.request` only; defer `Client.get` convenience helpers.
- Keep TLS, pooling, redirects, cookies, compression, proxies, and streaming
  client bodies out of this milestone.

## Contract First

- Add public `Choku.Client`.
- Add client-specific `Error`, `Request`, `Response`, `Handler`, and
  `Middleware` contracts.
- Add request URL validation and normalized `authority`, `host`, `port`, and
  `target` accessors.
- Add one-attempt HTTP/1.1 request serialization and response parsing.
- Preserve Eio cancellation and close each transport flow on every exit path.

## Steps

- [x] Explore: inspect existing HTTP/1.1 parser/writer, body/chunk helpers,
      server network tests, and public module exports.
- [x] Red: add focused tests for client request construction, middleware, and
      HTTP/1.1 transport behavior.
- [x] Green: implement the minimal client API and transport.
- [x] Refactor: keep parsing/serialization helpers small and internal.
- [x] Static checks: run formatters and build checks.
- [x] Code review: request context-free review and incorporate feedback.
- [x] Re-review: fix review findings and repeat review until it passes.
- [x] Completion: move this plan to completed.

## Decisions

- Keep the first implementation in `Client` plus a private `Http1_client`
  helper if the transport code needs separation.
- Use `Eio.Net.getaddrinfo_stream` and `Eio.Net.connect` for plain TCP.
- Use network tests gated by `CHOKU_RUN_NETWORK_TESTS=1`, matching existing
  server integration tests.

## Verification

Passed:

- `dune build @fmt`
- `CHOKU_RUN_NETWORK_TESTS=1 dune exec test/test_client.exe`
- `dune runtest`
- `dune build @all`
- `dune build @check`
- `dune build @install`
- `CHOKU_RUN_NETWORK_TESTS=1 dune exec test/test_server.exe`
- `opam lint choku.opam`

## Completion Notes

Implemented `Choku.Client` with separate client request and response values,
client middleware, plain HTTP/1.1 one-request-per-connection transport,
bounded buffered responses, fixed-length and chunked response decoding,
informational response skipping, bodyless response handling, strict response
framing validation, and explicit flow cleanup.

Context-free code review found flow cleanup, default-port authority
normalization, and test coverage gaps. The implementation now closes flows with
`Eio.Flow.close`, normalizes explicit `:80` out of authority, and adds tests for
the reviewed edge cases. Re-review passed.

## Commit

`feat: add minimal http client`
