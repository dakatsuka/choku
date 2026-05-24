# Implement Router HEAD And 405 Semantics

## Status

Completed

## Objective

Implement automatic router `HEAD` fallback to `GET` routes and automatic `405
Method Not Allowed` responses with `Allow` headers, without adding new public
router APIs.

## Context

- [Router HEAD And 405 Semantics](../../product-specs/router-head-and-405.md)
- [Router HEAD And 405 Semantics Design](../../design-docs/router-head-and-405.md)
- [Minimal Router DSL](../../product-specs/minimal-router-dsl.md)
- [Minimal Router DSL Design](../../design-docs/minimal-router-dsl.md)
- [Route-Level Body Mode](../../design-docs/route-level-body-mode.md)

## Clarifications

- Keep the scope limited to automatic `HEAD` fallback and automatic 405.
- Do not add route groups, OPTIONS automation, CORS, or configurable 405
  handlers.
- Preserve existing route insertion-order matching.

## Contract First

- No new public API is introduced.
- Update router docs to state:
  - explicit `HEAD` routes take precedence;
  - `HEAD` can fall back to matching `GET` routes;
  - path matches with disallowed methods return 405 with `Allow`;
  - `Router.not_found` customizes only no-path-match behavior.

## Steps

- [x] Explore: inspect router implementation, tests, status/method helpers, and
      existing router docs.
- [x] Design review: request context-free third-party review and incorporate
      feedback.
- [x] Red: add router and server tests for HEAD fallback, explicit HEAD
      precedence, 405/Allow, query handling, params, internal route matching,
      valid/oversized method-mismatch bodies, pipelined 405 reuse, and
      `Server.create_router` integration.
- [x] Green: implement shared route-selection helpers and default 405 response.
- [x] Refactor: keep matching stages readable and avoid public API growth.
- [x] Static checks: run formatters, focused tests, full tests, install, and
      lint checks.
- [x] Code review: request context-free third-party review after implementation.
- [x] Re-review: fix review findings and repeat review until it passes.

## Decisions

- Fallback `HEAD` handlers receive the original `HEAD` request.
- Explicit `HEAD` routes beat implicit `GET` fallback even when the explicit
  `HEAD` route is registered later.
- `Allow` preserves insertion order and adds implicit `HEAD` immediately after
  `GET` when needed.
- Custom not-found handlers do not customize automatic 405 responses.
- For `Server.create_router`, request framing and body-limit errors may take
  precedence over router-level 405.

## Verification

Passed:

- `dune build @fmt`
- `dune exec test/test_router.exe`
- `dune exec test/test_http1.exe`
- `dune exec test/test_server.exe`
- `CHOKU_RUN_NETWORK_TESTS=1 dune exec test/test_server.exe`
- `dune runtest`
- `dune build @all`
- `dune build @check`
- `dune build @install`
- `opam lint choku.opam`

## Completion Notes

Implemented router `HEAD` fallback to matching `GET` routes, automatic 405
responses with deterministic `Allow` headers, and matching `Router.Internal`
behavior for `Server.create_router` body-mode selection. Design review clarified
HEAD precedence, body-error precedence before 405 in server integration, and
`Allow` ordering. Code review passed; a low-severity test gap for malformed
method-mismatch bodies was closed with a server regression test.

## Commit

`feat: add router head and method-not-allowed semantics`
