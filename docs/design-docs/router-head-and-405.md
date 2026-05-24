# Router HEAD And 405 Semantics

## Status

Accepted

## Context

Choku's router is intentionally small: it stores method-and-path route entries,
checks them in insertion order, and falls back to a configurable not-found
handler when no route matches. That first milestone deferred automatic `HEAD`
handling and `405 Method Not Allowed`.

The server now has the HTTP/1.1 basics expected of a backend application server.
Adding these two router semantics is a small compatibility step that improves
ordinary HTTP behavior without widening the public API.

## Goals

- Keep route registration APIs unchanged.
- Preserve first-match route handling for ordinary methods and keep `HEAD`
  fallback deterministic.
- Add automatic `HEAD` fallback to `GET` routes.
- Add automatic 405 responses with `Allow`.
- Keep `Server.create_router` pre-body body-mode selection aligned with
  `Router.to_handler`.

## Non-Goals

- A configurable 405 handler.
- Route introspection.
- Automatic `OPTIONS` responses or CORS handling.
- Path normalization, trailing-slash redirects, or URI decoding.

## Proposed Design

Split router matching into path matching and method selection.

Internally, compute route matches by path first:

```ocaml
type path_match = {
  route : route_entry;
  params : Params.t;
}
```

Successful route selection is deterministic:

1. For non-`HEAD` requests, find the first route whose method and pattern match
   the request.
2. For `HEAD` requests, first find the first explicit `HEAD` route whose
   pattern matches the path.
3. If no explicit `HEAD` route matched, find the first `GET` route whose
   pattern matches the path.
4. Otherwise, if any route pattern matched the path, return an automatic 405
   response.
5. Otherwise, invoke the router's not-found handler.

This means an explicit `HEAD` route beats implicit `GET` fallback even when the
matching `GET` route was registered earlier. Within explicit `HEAD` matches and
within fallback `GET` matches, insertion order still decides the winner.

The fallback `GET` handler receives the original `HEAD` request. This avoids
manufacturing a modified `Request.t` and lets handlers inspect the true request
method if they care. The server already suppresses body bytes for `HEAD`
responses, so the router does not need response-specific logic.

## 405 Response

The default 405 response is generated inside `Router.to_handler`:

```ocaml
Response.text ~status:Status.method_not_allowed "Method Not Allowed\n"
|> Response.with_header "allow" allow_value
```

`allow_value` is built from path-matching routes in insertion order. Method
names use `Method.to_string`; duplicate names are omitted. If `GET` is allowed,
`HEAD` is added immediately after `GET` unless an explicit `HEAD` method has
already appeared.

Examples:

- routes: `GET /x`, `POST /x` -> `Allow: GET, HEAD, POST`
- routes: `HEAD /x`, `GET /x` -> `Allow: HEAD, GET`
- routes: `POST /x`, `GET /x` -> `Allow: POST, GET, HEAD`

This keeps `Allow` deterministic while avoiding method sorting rules or a new
method-set abstraction.

`Router.not_found` remains only a not-found hook. A customizable 405 hook can be
added later if users need one.

## Server Integration

`Router.Internal.match_route` is used by `Server.create_router` before reading a
request body. It should share the same route-selection helper as
`Router.to_handler` for allowed methods and HEAD fallback.

For `HEAD` fallback to `GET`, the matched route's `request_body_mode` is the
`GET` route's body mode. That is consistent with using the `GET` route handler.

405 responses do not require body-mode selection because the server still needs
to parse and validate the request body according to general HTTP framing before
invoking the router handler. This milestone does not add a pre-body reject path
for method-not-allowed requests.

## Contracts

- Explicit `HEAD` routes beat automatic `GET` fallback.
- Later explicit `HEAD` routes still beat earlier matching `GET` routes because
  the `GET` match is only an implicit fallback.
- `HEAD` fallback preserves the original `Request.t`.
- Automatic 405 happens only when at least one route pattern matches the path.
- The `Allow` header includes implicit `HEAD` when `GET` is allowed.
- Request framing and body-limit errors may take precedence over 405 in
  `Server.create_router`, because the server validates the request before
  invoking the router handler.
- `Router.Internal.match_route` and `Router.to_handler` agree on which route is
  selected for ordinary matches and `HEAD` fallback.
- No new public API is added.

## Alternatives Considered

- Require users to register explicit `HEAD` routes: rejected because `HEAD` for
  `GET` resources is a common HTTP expectation and the server already handles
  body suppression.
- Rewrite fallback `HEAD` requests to `GET`: rejected because it hides the
  actual method from handlers and requires changing or copying `Request.t`.
- Let custom not-found handlers handle method-not-allowed: rejected because
  method-not-allowed requires route-table knowledge that users cannot currently
  inspect.
- Add a public 405 customization hook now: deferred to keep this milestone
  narrow.

## Third-Party Review

Context-free review found ambiguity in `HEAD` precedence, product-level 405
body/error precedence, and `Allow` ordering. The design now explicitly states
that explicit `HEAD` routes beat implicit `GET` fallback even when registered
later, request framing and body-limit errors may take precedence over 405 in
`Server.create_router`, and implicit `HEAD` is inserted immediately after `GET`
in `Allow`.

## Validation

- Router unit tests for explicit `HEAD`, fallback `HEAD`, later explicit `HEAD`
  versus earlier `GET`, parameter/static shadowing, 405 status and body, `Allow`
  order, duplicate omission, implicit `HEAD`, path params in fallback, custom
  method names, query ignoring, and not-found separation.
- Internal route matching tests for `HEAD` fallback and explicit `HEAD`
  precedence.
- Server network tests proving `Server.create_router` returns a bodyless `HEAD`
  response for a `GET` route and sends 405 with `Allow` for path/method
  mismatch. Include method-mismatch requests with valid small bodies, oversized
  bodies, and pipelined follow-up requests to lock in body draining and error
  precedence.
- Standard Dune, format, install, and opam lint checks.

## Open Questions

None.
