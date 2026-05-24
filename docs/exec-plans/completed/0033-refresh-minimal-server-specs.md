# Refresh Minimal Server Specs

## Status

Completed

## Objective

Update the stale minimal server product specs to describe the current accepted
application-server baseline before HTTP Client design begins.

## Context

- [HTTP Server Baseline And Client Readiness](../../design-docs/http-server-baseline-and-client-readiness.md)
- [Minimal HTTP/1.1 Server Milestone](../../product-specs/minimal-http1-server.md)
- [Minimal Server API](../../product-specs/minimal-server-api.md)
- [HTTP/1.1 Persistent Connections](../../product-specs/http1-persistent-connections.md)
- [Response Streaming](../../product-specs/response-streaming.md)
- [Generic Pre-Body Selector](../../product-specs/generic-pre-body-selector.md)
- [Router HEAD And 405 Semantics](../../product-specs/router-head-and-405.md)

## Clarifications

- This milestone is documentation-only.
- Mark the stale specs `Accepted` after bringing them current.
- Document deferred limitations such as automatic `Date` and
  `Expect: 100-continue`.
- Keep HTTP Client API design out of scope, but capture server/client shared
  type boundaries that must inform the next milestone.

## Contract First

- Current server behavior is the accepted baseline for application-server use
  behind a reverse proxy.
- `Request.t` remains server/application oriented until HTTP Client design
  decides outbound request representation.
- Streaming support is sufficient for the minimal server baseline.

## Steps

- [x] Explore: inspect stale specs and the accepted baseline inventory.
- [x] Draft: update `minimal-http1-server.md` and `minimal-server-api.md`.
- [x] Review: request context-free review and incorporate feedback.
- [x] Static checks: run documentation-safe checks.
- [x] Completion: move plan to completed.

## Decisions

- Mark both minimal server specs `Accepted`.
- Treat the current server as an application-server baseline for reverse-proxy
  deployment rather than an edge-server baseline.
- Explicitly document automatic `Date`, automatic `Server`, and
  `Expect: 100-continue` as current limitations.
- Keep `Request.t` server/application oriented until HTTP Client design decides
  outbound request representation.
- Refresh the persistent-connection spec where it still described response
  streaming and chunked responses as out of scope.

## Verification

Passed:

- `dune build @fmt`
- `dune build @all`

## Completion Notes

Refreshed `minimal-http1-server.md` and `minimal-server-api.md` to describe the
current accepted application-server baseline. The specs now include router
integration, generic pre-body request body selection, request and response
streaming, persistent connections, explicit current limitations, and the
server/application orientation of `Request.t` before HTTP Client design.

Also refreshed the persistent-connections spec where it still described
response streaming and chunked responses as out of scope.

Context-free review and re-review passed with no blocking findings.

## Commit

`docs: refresh minimal server specs`
