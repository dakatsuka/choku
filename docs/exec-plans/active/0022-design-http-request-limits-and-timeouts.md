# Design HTTP Request Limits And Timeouts

## Status

Active

## Objective

Design HTTP/1.1 request-line/header-size limits and slowloris mitigation for
Camelio's Eio server.

## Context

- [Minimal HTTP/1.1 Server Milestone](../../product-specs/minimal-http1-server.md)
- [Minimal Server API](../../product-specs/minimal-server-api.md)
- [Minimal Server, Handler, and Middleware API](../../design-docs/minimal-server-handler-middleware-api.md)
- [Streaming Request Bodies](../../design-docs/streaming-request-bodies.md)
- [Future Work](../../design-docs/future-work.md)
- [Add HTTP Security Regression Tests](../completed/0021-add-http-security-regression-tests.md)

## Clarifications

- Continue from the security regression work.
- Do not implement limits until the public behavior and Eio timeout strategy are
  documented.
- Deferred topics for upload storage, generic pre-body selection, and router
  follow-ups are recorded in `docs/design-docs/future-work.md`.

## Contract First

Potential public contracts to design:

- request-line size limit;
- total request-header block size limit;
- optional header read timeout;
- error mapping for exceeded limits or timeout;
- `Server.create` and `Server.create_router` configuration shape, if public.

## Steps

- [x] Record deferred topics for later design.
- [ ] Explore: inspect Eio timeout APIs and current request-head read loop.
- [ ] Draft design doc for limits, timeout semantics, defaults, and validation.
- [ ] Design review: not delegated unless explicitly requested by the user.
- [ ] Completion: update plan status and commit documentation.

## Decisions

Pending.

## Verification

Pending.

## Completion Notes

Pending.

## Commit

Pending.
