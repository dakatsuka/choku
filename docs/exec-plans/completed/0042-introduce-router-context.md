# Introduce Router Context

## Status

Completed

## Objective

Change router route handlers to receive one `Router.Context.t` value that
contains route parameters and the original request.

## Context

- [Minimal Router DSL](../../product-specs/minimal-router-dsl.md)
- [Minimal Router DSL Design](../../design-docs/minimal-router-dsl.md)
- [Route-Level Body Mode](../../design-docs/route-level-body-mode.md)

## Clarifications

The requested API shape is a context record passed as the single route-handler
argument.

## Contract First

`Router.Context.t` is exposed as a private record:

```ocaml
module Context : sig
  type t = private { params : Params.t; request : Request.t }
end

type route_handler = Context.t -> Response.t
```

Users can read `ctx.params` and `ctx.request`, but only the router constructs
context values.

## Steps

- [x] Explore: inspect existing code, specs, design docs, and tests.
- [x] Design review: request context-free third-party review and incorporate
      feedback.
- [x] Red: update router tests to require the new one-argument context handler.
- [x] Green: implement the router context API and migrate call sites.
- [x] Refactor: improve structure while keeping tests green.
- [x] Static checks: run formatters and static analysis tools, then fix
      findings.
- [x] Code review: request context-free third-party review after implementation.
- [x] Re-review: fix review findings and repeat review until it passes.

## Decisions

- No ADR is required because this changes one optional public API shape without
  changing module ownership or server architecture.
- `Context.t` is private in the public interface so later router-owned fields
  can be added without encouraging application-side record construction.
- The change is a breaking API migration from `fun params request -> ...` to
  `fun ctx -> ...`.

## Verification

- PASS: `dune build @fmt`
- PASS: `dune build @check`
- PASS: `dune exec test/test_router.exe`
- PASS: `dune exec test/test_server.exe`
- PASS: `dune runtest`
- PASS: `CHOKU_RUN_NETWORK_TESTS=1 dune exec test/test_server.exe`

The first sandboxed network-test attempt failed with `Unix.EPERM` on socket
creation. The same command passed after local socket permission was approved.

## Completion Notes

Introduced `Router.Context.t` as the single route-handler input, migrated
router implementation, tests, examples, README snippets, and public
documentation, and recorded the breaking migration path.

## Commit

Not committed.
