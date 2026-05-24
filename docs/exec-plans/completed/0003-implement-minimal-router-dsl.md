# Implement Minimal Router DSL

## Status

Completed

## Objective

Implement `Choku.Router`, an optional method-and-path routing layer that
compiles to `Handler.t` and supports static paths plus simple named path
parameters.

## Context

- [Agent Guide](../../../AGENTS.md)
- [Minimal Router DSL Product Spec](../../product-specs/minimal-router-dsl.md)
- [Minimal Router DSL Design](../../design-docs/minimal-router-dsl.md)
- [Minimal Server API](../../product-specs/minimal-server-api.md)
- [Minimal Server, Handler, and Middleware API](../../design-docs/minimal-server-handler-middleware-api.md)
- [Project Layout and Tooling](../../design-docs/project-layout-and-tooling.md)

## Clarifications

- The router is optional and must compile to `Handler.t`.
- Do not change `Server.run`, `Server.create`, `Handler.t`, or middleware
  semantics.
- Do not store route parameters in `Request.t`.
- Do not implement regex routes, route groups, per-route middleware, 405
  generation, automatic `HEAD`, URI decoding, or path normalization in this
  milestone.
- Reject empty route-pattern segments except for the root pattern `/`.

## Contract First

Create public signatures and block comments for:

- `Router`;
- `Router.Params`;
- `Router.route_handler`;
- route registration functions;
- `Router.to_handler`.

Update the public `Choku` module and dune/test layout after the interface is
defined.

## Steps

- [x] Explore: inspect existing code, specs, design docs, and tests.
- [x] Design review: request context-free third-party review and incorporate
      feedback.
- [x] Red: write failing behavior-focused tests in `test/test_router.ml`.
- [x] Green: implement the smallest `lib/router.ml` that satisfies the tests.
- [x] Refactor: improve route pattern parsing and matching while keeping tests
      green.
- [x] Static checks: run formatters and static analysis tools, then fix
      findings.
- [x] Code review: request context-free third-party review after
      implementation.
- [x] Re-review: fix review findings and repeat review until it passes.

## Decisions

- Add `Choku.Router` as a new top-level module.
- Use a router-specific `route_handler = Params.t -> Request.t -> Response.t`.
- Keep `Request.t` unchanged.
- Match routes in insertion order.
- Match against `Request.path` so query strings are ignored.
- Support only static segments and `:name` parameter segments initially.
- Treat trailing slashes and repeated slashes in route patterns as invalid,
  except for the root pattern `/`.

## Verification

Verified commands:

```sh
dune build @all
dune runtest
dune build @fmt
dune build @check
dune build @install
opam lint choku.opam
```

Network integration tests are not required for the router because it should be
testable through `Router.to_handler` without sockets.

## Completion Notes

Implemented `Choku.Router` with immutable route registration, first-match
method/path routing, static and named-parameter path patterns, configurable
not-found handling, and `Router.to_handler`. Context-free code review reported
no blocking findings; low-severity feedback about keeping the source pattern and
testing the generic `Router.route` API was addressed.

## Commit

```text
feat: implement minimal router DSL
```
