# Design Route-Level Body Mode

## Status

Completed

## Objective

Design how Choku should support route-level request body delivery modes
without implementing the feature yet.

## Context

- [Agent Guide](../../../AGENTS.md)
- [Minimal Server API](../../product-specs/minimal-server-api.md)
- [Minimal Router DSL](../../product-specs/minimal-router-dsl.md)
- [Streaming Request Bodies](../../design-docs/streaming-request-bodies.md)
- [Minimal Router DSL Design](../../design-docs/minimal-router-dsl.md)
- [Multipart Form-Data Support](../../product-specs/multipart-form-data.md)

## Clarifications

- The user explicitly requested design, usage assumptions, documentation, and
  review only. Do not implement code in this plan.

## Contract First

Proposed public API shape for a future implementation:

```ocaml
module Request_body_mode : sig
  type t = Buffered | Streaming
end

module Router : sig
  type body_mode = Request_body_mode.t

  val route :
    ?request_body_mode:body_mode ->
    Method.t ->
    string ->
    route_handler ->
    t ->
    t

  val get : ?request_body_mode:body_mode -> string -> route_handler -> t -> t
  val post : ?request_body_mode:body_mode -> string -> route_handler -> t -> t
  val put : ?request_body_mode:body_mode -> string -> route_handler -> t -> t
  val patch : ?request_body_mode:body_mode -> string -> route_handler -> t -> t
  val delete :
    ?request_body_mode:body_mode -> string -> route_handler -> t -> t
  val options :
    ?request_body_mode:body_mode -> string -> route_handler -> t -> t

  val to_handler : t -> Handler.t
end

module Server : sig
  val create_router :
    ?max_request_body_size:int ->
    ?middlewares:Middleware.t list ->
    Router.t ->
    t
end
```

The exact server-side entry point name should be refined during implementation,
but the design should avoid exposing internal HTTP/1.1 parser details as public
API.

## Steps

- [x] Explore: inspect current router, server, streaming body, multipart specs,
      and APIs.
- [x] Design review: request context-free review and incorporate feedback.
- [x] Documentation: add design notes and usage examples.
- [x] Completion: record review feedback and final recommendation.

## Decisions

- Use `Request_body_mode.t` as the shared body-mode type to avoid a
  `Router`/`Server` module dependency cycle.
- Keep `Server.request_body_mode` as a compatibility alias so existing
  server-wide usage remains readable.
- Prefer `Server.create_router` over exposing an HTTP/1.1 request-head selector
  as public API.
- Preserve `Router.to_handler` for already-constructed requests and tests.
- Unmatched routes use buffered mode and remain subject to
  `max_request_body_size`.

## Verification

Documentation-only work.

- Context-free design review by Banach.
- Re-review by Banach after dependency-cycle and contract clarifications.
- `git diff` review.

## Completion Notes

Added route-level body mode design documentation, product-spec notes, usage
examples, and cross-links from streaming/multipart docs. Review feedback led to
the `Request_body_mode.t` shared type, explicit middleware and `Server.handle`
contracts, unmatched oversized request behavior, and matcher parity validation
requirements.

## Commit

`docs: design route-level body mode`
