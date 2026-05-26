# Implement Server Cookie Support

## Status

Completed

## Objective

Implement server-side cookie helpers and response header appending according to
the accepted server cookie support draft.

## Context

- [Server Cookie Support Product Spec](../../product-specs/server-cookie-support.md)
- [Server Cookie Support Design](../../design-docs/server-cookie-support.md)
- [Minimal Server API](../../product-specs/minimal-server-api.md)
- [Minimal Server, Handler, and Middleware API](../../design-docs/minimal-server-handler-middleware-api.md)

## Clarifications

- Implement `Cookie` as explicit value-level helpers, not middleware.
- Preserve `Response.with_header` replacement semantics.
- Add `Response.add_header` for repeated response fields such as `Set-Cookie`.
- `SameSite=None` is represented by `No_restriction` and requires
  `~secure:true`.
- `Cookie.delete` emits both `Max-Age=0` and a fixed past `Expires`.

## Contract First

- Add `Response.add_header`.
- Add `Cookie.same_site`.
- Add `Cookie.get` and `Cookie.get_all`.
- Add `Cookie.set` and `Cookie.delete`.
- Export `Choku.Cookie`.

## Steps

- [x] Explore: inspect response/header contracts, docs, and tests.
- [x] Design review: request context-free third-party review and incorporate
      feedback.
- [x] Red: write failing behavior-focused tests for response header append and
      cookie parsing/formatting.
- [x] Green: implement the smallest change that satisfies the tests.
- [x] Refactor: improve structure while keeping tests green.
- [x] Static checks: run formatters and static analysis tools, then fix
      findings.
- [x] Code review: request context-free third-party review after implementation.
- [x] Re-review: fix review findings and repeat review until it passes.

## Decisions

- Restrict response cookie values to a safe unquoted subset. Quoted cookie
  values remain future work.
- Validate `Path` and `Domain` only for safe header serialization, not browser
  storage acceptance.
- Add an HTTP/1 serialization regression so repeated `Set-Cookie` values are
  proven to leave Choku as separate header fields.

## Verification

- `dune build @fmt`
- `dune exec test/test_cookie.exe`
- `dune exec test/test_response.exe`
- `dune exec test/test_http1.exe`
- `dune build @check`
- `dune build @all`
- `dune runtest`
- `dune build @install`

## Completion Notes

Added `Response.add_header`, a top-level `Choku.Cookie` module, focused cookie
tests, response append tests, and HTTP/1 response serialization coverage for
repeated `Set-Cookie` fields. Updated README and server API docs with the new
helpers.

Code review found no functional cookie helper bugs. It requested wire-level
`Set-Cookie` serialization coverage and plan/design bookkeeping updates; both
were addressed and re-reviewed.

## Commit

feat: add server cookie support
