# Router HEAD And 405 Semantics

## Status

Accepted

## Problem

Choku's router currently treats a path registered for another method as a normal
not-found case. It also requires users to register `HEAD` routes separately even
when a `GET` route already describes the resource.

For a small HTTP application server, router behavior should cover these common
HTTP semantics without becoming a full web framework.

## Goals

- Automatically support `HEAD` requests for matching `GET` routes.
- Return `405 Method Not Allowed` when a path matches one or more routes but the
  request method is not allowed for that path.
- Include an `Allow` header in automatic 405 responses.
- Preserve deterministic route selection while making explicit `HEAD` routes
  more specific than implicit `GET` fallback.
- Keep the public router API small.

## Non-Goals

- Route groups, nested routers, mounts, filters, or per-route middleware.
- Automatic `OPTIONS *` or CORS behavior.
- Path normalization, percent-decoding, trailing-slash redirects, or query-based
  routing.
- A public route introspection API.
- Configurable 405 response handlers in this milestone.

## Requirements

- If a non-`HEAD` request method and path match a registered route, the first
  matching route handles the request exactly as before.
- For `HEAD` requests, Choku first searches explicit `HEAD` routes in insertion
  order. If one matches the path, it handles the request.
- If no explicit `HEAD` route matches, Choku searches matching `GET` routes in
  insertion order. If one matches the path, it handles the request.
- The request delivered to a `GET` route through automatic `HEAD` fallback keeps
  its original method, `HEAD`.
- The HTTP server continues to suppress response body bytes for `HEAD` requests.
- If no route handles the request method but one or more route patterns match
  the path, the router returns `405 Method Not Allowed`.
- For requests served through `Server.create_router`, normal request-head and
  request-body framing validation still happens before the router handler runs.
  Malformed or oversized method-mismatch requests may therefore return the
  existing `400` or `413` response before the router can return `405`.
- Automatic 405 responses include an `Allow` header containing the allowed
  methods for the path.
- When a path allows `GET`, the `Allow` header also includes `HEAD`.
- The `Allow` header preserves route insertion order, omits duplicate method
  names, and inserts implicit `HEAD` immediately after `GET` when `GET` is
  present and `HEAD` has not already appeared.
- If no route pattern matches the path, the router uses its configured
  not-found handler as before.
- `Router.not_found` customizes only not-found responses; it does not customize
  automatic 405 responses.
- `Router.Internal.match_route` uses the same HEAD fallback semantics so
  `Server.create_router` can select the correct request body mode before body
  reads.

## Public Contracts

No new public functions or types are introduced.

Existing router behavior changes:

```ocaml
Router.empty
|> Router.get "/health" (fun _ _ -> Response.text "ok\n")
```

now handles both `GET /health` and `HEAD /health`. A `POST /health` request
returns `405 Method Not Allowed` with an `Allow` header.

## Examples

```ocaml
let router =
  Choku.Router.empty
  |> Choku.Router.get "/health" (fun _ _ -> Choku.Response.text "ok\n")

let server = Choku.Server.create_router router
```

Expected behavior:

- `GET /health`: `200 OK` with body.
- `HEAD /health`: `200 OK` with the same headers and no body bytes.
- `POST /health`: `405 Method Not Allowed` with `Allow: GET, HEAD`.
- `GET /missing`: configured 404 not-found behavior.

## Open Questions

None.
