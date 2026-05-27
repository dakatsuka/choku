# Inventory HTTP Server Baseline

## Status

Completed

## Objective

Inventory the remaining basic HTTP server behaviors before starting HTTP Client
work, and classify what should be implemented now, deferred, or intentionally
left to applications.

## Context

- [Minimal HTTP/1.1 Server Milestone](../../product-specs/minimal-http1-server.md)
- [Minimal Server API](../../product-specs/minimal-server-api.md)
- [Response Streaming](../../product-specs/response-streaming.md)
- [HTTP/1.1 Persistent Connections](../../product-specs/http1-persistent-connections.md)
- [Reverse Proxy Deployment](../../product-specs/reverse-proxy-deployment.md)
- [Future Work](../../design-docs/future-work.md)

## Clarifications

- This milestone is documentation-only.
- Prioritize application-server readiness behind reverse proxies.
- Consider what HTTP Client work should reuse or avoid changing.

## Contract First

- Record what server behavior is already good enough.
- Record what should be done before HTTP Client development.
- Record what should be deferred until after the HTTP Client exists.
- Record what belongs outside the core server.

## Steps

- [x] Explore: inspect existing server specs, response streaming docs, and
      future-work notes.
- [x] Draft: add a design inventory document.
- [x] Review: request context-free review and incorporate feedback.
- [x] Static checks: run documentation-safe checks.
- [x] Completion: move plan to completed.

## Decisions

- Treat current streaming support as sufficient for the minimal
  application-server baseline.
- Do not add edge-server features before HTTP Client work.
- Update stale minimal server specs before client design.
- Treat request-target and URI representation as the main shared/server-only
  boundary to resolve before HTTP Client implementation.
- When refreshing stale server specs, explicitly call out automatic `Date` and
  `Expect: 100-continue` as deferred limitations.

## Verification

Passed:

- `dune build @fmt`
- `dune build @all`

## Completion Notes

Added an accepted server baseline and HTTP Client readiness inventory. The
inventory records that the current server is sufficient as a reverse-proxy
backed application server, recommends refreshing stale minimal server specs
before client design, and identifies request-target/URI representation as the
main boundary to resolve before HTTP Client implementation.

Context-free design review passed with no blocking findings. The review noted
that automatic `Date` and `Expect: 100-continue` should be made explicit as
deferred limitations in the next stale-spec refresh; the inventory now records
that.

## Commit

`docs: inventory http server baseline`
