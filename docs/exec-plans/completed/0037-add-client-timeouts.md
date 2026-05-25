# Add Client Timeouts

## Status

Completed

## Objective

Add optional timeout settings to `Choku.Client` so callers can bound DNS and TCP
connect, TLS handshake, request write, response-head read, and response-body
read phases.

## Context

- [Minimal HTTP Client](../../product-specs/minimal-http-client.md)
- [HTTPS Client](../../product-specs/https-client.md)
- [Minimal HTTP Client Design](../../design-docs/minimal-http-client.md)
- [HTTPS Client Design](../../design-docs/https-client.md)

## Clarifications

- The user asked to add timeout settings now.
- Redirect following remains a later middleware-oriented milestone.
- Convenience APIs such as `Client.get` are planned after timeouts.
- RFC 3986 URL parsing with `ocaml-uri` is a separate design topic.

## Contract First

- Add `Client.Error.Timeout of timeout_phase`.
- Add `Client.Error.timeout_phase`.
- Add optional `?mono_clock` and phase timeout settings to `Client.create`.
- Require finite positive timeout values.
- Require `mono_clock` when any timeout is configured.

## Steps

- [x] Explore: inspect existing client code, specs, design docs, and Eio timeout
      APIs.
- [x] Update specs and design docs with timeout behavior and API contracts.
- [x] Red: add failing behavior-focused tests for validation and timeout
      mapping.
- [x] Green: implement the smallest change that satisfies the tests.
- [x] Refactor: improve structure while keeping tests green.
- [x] Static checks: run formatters and static analysis tools, then fix
      findings.
- [x] Code review: request context-free third-party review after
      implementation.
- [x] Re-review: fix review findings and repeat review until it passes.

## Decisions

- Timeouts default to disabled for source compatibility.
- Timeout enforcement uses an Eio monotonic clock, matching the server timeout
  approach.
- The connect timeout covers DNS resolution and all TCP connect attempts.
- TLS handshake timeout applies only after TCP connect succeeds.
- Request write, response-head read, and response-body read get separate
  timeouts so callers can distinguish failures.

## Verification

- `dune build @fmt`
- `dune exec test/test_client.exe`
- `CHOKU_RUN_NETWORK_TESTS=1 dune exec test/test_client.exe`
- `dune build @all`

## Completion Notes

- Added optional phase timeouts to `Client.create`.
- Added `Client.Error.Timeout of timeout_phase` for timeout mapping.
- Required finite positive timeout values and a monotonic clock whenever any
  timeout is configured.
- Added validation tests and behavior tests for TLS handshake, response-head,
  and response-body timeouts.
- Documented timeout configuration in the README, product specs, and design
  docs.

## Commit

`feat(client): add request timeouts`
