# Implement Minimal HTTP/1.1 Server

## Status

Active

## Objective

Implement the first buildable Camelio milestone: a minimal Eio-native HTTP/1.1
server with shared HTTP value types, handler and middleware contracts, per-module
unit tests, and a small example server.

## Context

- [Agent Guide](../../../AGENTS.md)
- [Project Layout and Tooling](../../design-docs/project-layout-and-tooling.md)
- [Minimal Server, Handler, and Middleware API](../../design-docs/minimal-server-handler-middleware-api.md)
- [Minimal HTTP/1.1 Server Milestone](../../product-specs/minimal-http1-server.md)
- [Minimal Server API](../../product-specs/minimal-server-api.md)
- [Eio Documentation](../../references/eio-documentation.md)

## Clarifications

- Use Alcotest for unit tests.
- Use a per-source-file unit test file for OCaml modules.
- Do not implement Router, HTTP Client, TLS, HTTP/2, or HTTP/3 in this
  milestone.
- Use HTTP/1.1 over plain TCP only.
- Prefer `Connection: close` behavior for the first implementation.
- Use `Server.create ?max_request_body_size` with default `1_048_576` bytes.
- Apply the error policy from the minimal HTTP/1.1 server product spec.

## Contract First

Create public signatures and block comments for:

- `Method`;
- `Headers`;
- `Status`;
- `Body`;
- `Request`;
- `Response`;
- `Handler`;
- `Middleware`;
- `Http1`;
- `Server`.

The signatures should follow the contracts in the design docs before internal
implementation is added.

## Steps

- [x] Explore: inspect existing code, specs, design docs, and tests.
- [x] Design review: request context-free third-party review and incorporate
      feedback.
- [ ] Red: write failing behavior-focused tests, with unit test files organized
      per module. For OCaml, create one unit test file per source file under
      test.
- [ ] Green: implement the smallest change that satisfies the tests.
- [ ] Refactor: improve structure while keeping tests green.
- [ ] Static checks: run formatters and static analysis tools, then fix findings.
- [ ] Code review: request context-free third-party review after implementation.
- [ ] Re-review: fix review findings and repeat review until it passes.

## Decisions

- Build with dune.
- Test with Alcotest.
- Format with ocamlformat.
- Keep source modules in `lib/`.
- Keep per-module tests in `test/`.
- Keep a small runnable example in `examples/`.
- Expose shared HTTP value modules as top-level `Camelio.*` modules.
- Defer Router, Client, TLS, HTTP/2, and HTTP/3 public APIs.
- Context-free design review passed with no blocking findings after resolving
  stale open questions and policy gaps.

## Verification

Planned commands:

```sh
dune build @all
dune runtest
dune fmt
```

Manual check after implementation:

```sh
curl -i http://127.0.0.1:8080/
```

## Completion Notes

Pending implementation.

## Commit

Use a Conventional Commits-compliant message, likely:

```text
feat: implement minimal HTTP/1.1 server
```
