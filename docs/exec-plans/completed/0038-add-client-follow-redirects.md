# Add Client Follow Redirects

## Status

Completed

## Objective

Add an opt-in client middleware that follows ordinary HTTP redirects for
replayable requests while keeping the transport layer focused on one request per
connection.

## Context

- [Minimal HTTP Client](../../product-specs/minimal-http-client.md)
- [Minimal HTTP Client Design](../../design-docs/minimal-http-client.md)
- [HTTPS Client](../../product-specs/https-client.md)

## Clarifications

- The user identified redirect following as the next HTTP client task after
  timeouts.
- Redirect following should be middleware-oriented, similar to Faraday's
  follow-redirects middleware model.
- RFC 3986 URL parsing with `ocaml-uri` remains a separate design topic.

## Contract First

- Add `Client.Error.Too_many_redirects`.
- Add `Client.Error.Redirect_missing_location`.
- Add `Client.Middleware.follow_redirects ?max_redirects ()`.
- Require `max_redirects >= 0`.
- Follow `301`, `302`, `307`, and `308` only for `GET` and `HEAD`.
- Follow `303` for any method by rewriting to `GET`, except `HEAD` remains
  `HEAD`.
- Resolve absolute redirect URLs, scheme-relative locations, path-absolute
  locations, and query-only locations.
- Strip redirect URL fragments before constructing the next request.
- Strip `Authorization`, `Cookie`, and `Proxy-Authorization` on cross-origin
  redirects.

## Steps

- [x] Explore: inspect existing client middleware, URL model, specs, design
      docs, and tests.
- [x] Update specs and design docs with redirect behavior and API contracts.
- [x] Red: add failing behavior-focused tests for redirect middleware.
- [x] Green: implement the smallest change that satisfies the tests.
- [x] Refactor: improve structure while keeping tests green.
- [x] Static checks: run formatters and static analysis tools, then fix
      findings.
- [x] Code review: request context-free third-party review after
      implementation.
- [x] Re-review: fix review findings and repeat review until it passes.

## Decisions

- Redirect following is opt-in middleware, not a default transport behavior.
- The default redirect limit is 5.
- The first redirect implementation intentionally does not add a full RFC 3986
  resolver; it supports common absolute, scheme-relative, path-absolute, and
  query-only `Location` values.
- Cross-origin redirects do not forward credential-bearing request headers.

## Verification

- `dune build @fmt`
- `dune exec test/test_client.exe`
- `CHOKU_RUN_NETWORK_TESTS=1 dune exec test/test_client.exe`
- `dune build @all`

## Completion Notes

- Added opt-in `Client.Middleware.follow_redirects`.
- Added explicit redirect errors for missing `Location` and redirect limit
  exhaustion.
- Implemented method/status handling for `301`, `302`, `303`, `307`, and
  `308`.
- Implemented common redirect URL resolution for absolute, scheme-relative,
  path-absolute, and query-only locations.
- Stripped fragments from redirect locations before building the next request.
- Stripped credential-bearing headers on cross-origin redirects.
- Documented redirect behavior in README, product specs, and design docs.

## Commit

`feat(client): add follow redirects middleware`
