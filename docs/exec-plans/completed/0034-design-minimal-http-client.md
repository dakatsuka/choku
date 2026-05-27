# Design Minimal HTTP Client

## Status

Completed

## Objective

Design Choku's first HTTP Client milestone before implementation, including
separate client request/response types and a minimal client middleware stack.

## Context

- [Minimal HTTP Client](../../product-specs/minimal-http-client.md)
- [Minimal HTTP Client Design](../../design-docs/minimal-http-client.md)
- [HTTP Server Baseline And Client Readiness](../../design-docs/http-server-baseline-and-client-readiness.md)
- [Minimal Server API](../../product-specs/minimal-server-api.md)
- [HTTP/1.1 Persistent Connections](../../product-specs/http1-persistent-connections.md)

## Clarifications

- Client-side request and response types should be separate from server
  `Request.t` and `Response.t`.
- Include middleware from the first client milestone so users can implement
  optional policies outside core.
- Keep the first client minimal: plain HTTP/1.1, no TLS, no pool, no redirects,
  no cookies, no compression, no proxy support, and buffered responses.

## Contract First

- Define `Choku.Client` as the public namespace for the first client.
- Define separate `Client.Request.t` and `Client.Response.t`.
- Define explicit `Client.Request.make` URL validation and immutable request
  replacement helpers for middleware.
- Define `Client.Response.make` so middleware and tests can synthesize client
  responses.
- Define `Client.Handler.t = Request.t -> (Response.t, Error.t) result`.
- Define `Client.Middleware.t = Handler.t -> Handler.t`.
- Define middleware order to match server middleware order.
- Define one-connection-per-request HTTP/1.1 transport behavior.
- Define explicit client error categories before implementation.
- Define strict response body/no-body and transfer-length parsing rules.
- Define per-attempt resource cleanup for success, errors, and cancellation.

## Steps

- [x] Explore: inspect existing specs, server/client readiness notes, public
      request/response contracts, and middleware shape.
- [x] Draft: add HTTP Client product spec and design doc.
- [x] Design review: request context-free third-party review and incorporate
      feedback.
- [x] Static checks: run documentation-safe checks.
- [x] Completion: move this plan to completed after design review and checks.

## Decisions

- Use separate client request and response types rather than aliases to server
  request and response values.
- Reuse shared `Method.t`, `Headers.t`, `Status.t`, and buffered `Body.t`.
- Include client middleware in the first milestone.
- Keep first transport behavior to one plain HTTP/1.1 request and one fully
  buffered response per connection.
- Reject `CONNECT` and `101 Switching Protocols` in the first milestone.
- Use strict response framing rules: reject TE+CL, transfer-coding lists, and
  ambiguous or invalid content lengths.
- Add read-only authority, host, port, and target accessors for middleware.
- Require each transport attempt to close its flow on success, client error,
  non-cancellation exception mapping, and cancellation.
- Defer TLS, pooling, redirects, cookies, retries, compression, proxy support,
  and streaming client bodies.

## Verification

Passed:

- `dune build @fmt`
- `dune build @all`

## Completion Notes

Designed the first HTTP Client milestone as a deliberately small plain
HTTP/1.1 client with separate client request and response types, client
middleware from the beginning, one request per connection, buffered responses,
strict response framing, explicit no-body response handling, and per-attempt
resource cleanup.

Context-free review found issues around no-body response handling, `CONNECT`,
flow cleanup, transfer-length ambiguity, middleware access to normalized request
values, and response limit defaults. The design was revised and re-reviewed
with PASS.

## Commit

`docs: design minimal http client`
