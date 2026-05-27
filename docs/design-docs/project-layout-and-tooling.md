# Project Layout and Tooling

## Status

Superseded

This document records the pre-bootstrap layout design. The current repository
layout is represented by the checked-in Dune files, public interfaces, tests,
and the completed bootstrap execution plan.

## Context

Choku needs a small OCaml project structure before implementation starts. The
repository currently contains design and product documentation only. The first
implementation milestone should introduce build, test, formatting, and source
layout together so later agents can follow a stable convention.

## Goals

- Use a conventional dune-based OCaml library layout.
- Keep source modules small and aligned with public contracts.
- Create unit tests per OCaml source file.
- Use Alcotest for unit tests.
- Use ocamlformat for formatting.
- Avoid implementation files in this design step.

## Non-Goals

- Creating source, test, dune, opam, or formatter files in this design step.
- Selecting release metadata beyond what the first implementation plan needs.
- Adding benchmark, fuzzing, coverage, or CI infrastructure before the minimal
  server exists.

## Proposed Layout

The first implementation plan should create this layout:

```text
lib/
  choku.ml
  method.ml
  method.mli
  headers.ml
  headers.mli
  status.ml
  status.mli
  body.ml
  body.mli
  request.ml
  request.mli
  response.ml
  response.mli
  handler.ml
  handler.mli
  middleware.ml
  middleware.mli
  http1.ml
  http1.mli
  server.ml
  server.mli

test/
  test_method.ml
  test_headers.ml
  test_status.ml
  test_body.ml
  test_request.ml
  test_response.ml
  test_handler.ml
  test_middleware.ml
  test_http1.ml
  test_server.ml

examples/
  hello.ml
```

Each implementation module should have a corresponding `.mli` once it exposes a
public contract. Public interfaces must use block comments for contracts and
behavior.

The public module shape is top-level under the `Choku` library:
`Choku.Method`, `Choku.Headers`, `Choku.Status`, `Choku.Body`,
`Choku.Request`, `Choku.Response`, `Choku.Handler`,
`Choku.Middleware`, `Choku.Http1`, and `Choku.Server`.

## Tooling

The first implementation plan should introduce:

- `dune-project`;
- `lib/dune`;
- `test/dune`;
- `examples/dune`;
- `.ocamlformat`;
- `.github/workflows/ci.yml`;
- `choku.opam`, generated from `dune-project`.

Initial dependencies:

- runtime: `eio`, `eio_main`;
- test: `alcotest`;
- build: `dune`;
- formatting: `ocamlformat`.

Use the conventional ocamlformat profile. The initial checked-in formatter
version should match the version available in the development switch.

The expected verification commands are:

```sh
dune build @all
dune runtest
dune build @fmt
dune build @check
dune build @install
opam lint choku.opam
```

Run Dune commands sequentially in local and agent-driven harnesses. Dune uses a
shared workspace lock, so concurrent invocations such as `dune build @all` and
`dune runtest` can fail with lock contention that does not indicate a code
failure.

If additional static analysis becomes available later, add it to the execution
plan and fix findings before implementation review.

## CI

GitHub Actions should use `ocaml/setup-ocaml@v3` with OCaml 5.4 on
`ubuntu-latest`. The workflow should install dependencies with test and
development setup dependencies, then run the local checks plus CI-only network
integration tests:

```sh
opam exec -- dune build @all
opam exec -- dune runtest
opam exec -- env CHOKU_RUN_NETWORK_TESTS=1 dune exec test/test_server.exe
opam exec -- dune build @fmt
opam exec -- dune build @check
opam exec -- dune build @install
opam lint choku.opam
```

CI may express the workflow as separate steps, but it should not run multiple
Dune commands concurrently against the same checkout.

Loopback integration tests are gated locally because sandboxed environments may
forbid socket creation. They should run in CI.

## Test Organization

Unit tests must be organized per module. For OCaml, each source file under test
gets a corresponding unit test file:

- `lib/headers.ml` -> `test/test_headers.ml`;
- `lib/middleware.ml` -> `test/test_middleware.ml`;
- `lib/http1.ml` -> `test/test_http1.ml`.

Integration tests may share files when they test cross-module behavior such as
`Server.run` with a real Eio listener.

## Contracts

Public `.mli` files should be created before or alongside implementations. The
implementation plan should start by adding signatures and contract comments,
then write failing tests against those signatures before filling in internals.

## Alternatives Considered

- `ppx_expect`: useful for parser snapshots, but Alcotest keeps the initial test
  dependency set smaller and works well with module-level unit tests.
- OUnit2: mature, but Alcotest has a compact API and good fit for small value
  tests.
- Single large `http.ml`: rejected because method, header, status, body, request,
  and response behavior need independent contracts and per-module tests.

## Third-Party Review

Initial context-free sub-agent review found blocking issues around request body
limit policy, HTTP parser error policy, public module shape, and execution-plan
review status. This document was updated to make the public module shape
explicit. Final context-free re-review reported no blocking findings and
confirmed that the pre-implementation docs are consistent enough to stop before
implementation.

## Validation

This design should be validated by reviewing whether the planned layout supports
the minimal server API, per-module unit tests, contract-first implementation, and
tool-driven formatting.

## Open Questions

- Should benchmark, fuzzing, coverage, or CI infrastructure be added after the
  minimal server exists?
