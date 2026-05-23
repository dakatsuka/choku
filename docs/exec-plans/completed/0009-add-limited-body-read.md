# Add Limited Body Read

## Status

Completed

## Objective

Add a bounded body-to-string helper so future streaming body consumers have a
safe API for reading body bytes into memory without relying on unbounded
`Body.to_string`.

## Context

- [Agent Guide](../../../AGENTS.md)
- [Streaming Request Bodies](../../design-docs/streaming-request-bodies.md)
- [ADR 0002](../../design-docs/adr/0002-introduce-streaming-bodies-with-buffered-compatibility.md)
- [Add Body Consumers](../completed/0008-add-body-consumers.md)

## Clarifications

- Keep `Body.to_string` unchanged for backward compatibility.
- Add an explicit bounded helper and structured error.
- Keep `Body.t` internally buffered in this plan.

## Contract First

Extend `Body` with:

- `Body.error`;
- `Body.to_string_limited`;
- `Body.pp_error`.

## Steps

- [x] Explore: inspect current body API and streaming body design.
- [x] Design review: keep `to_string` stable and add a bounded alternative.
- [x] Red: write failing behavior-focused tests in `test/test_body.ml`.
- [x] Green: implement the smallest `lib/body.ml` change that satisfies the
      tests.
- [x] Refactor: keep error naming aligned with other modules.
- [x] Static checks: run formatters and static analysis tools, then fix
      findings.
- [x] Code review: perform local review and address findings.

## Decisions

- `Body.to_string_limited ~max_size body` returns `Error Body_too_large` when
  the buffered body length exceeds `max_size`.
- Negative `max_size` raises `Invalid_argument`.
- `Body.to_string` remains available and unchanged.

## Verification

Verified commands:

```sh
dune build @all
dune runtest
dune build @fmt
dune build @check
dune build @install
opam lint camelio.opam
```

## Completion Notes

Added `Body.to_string_limited`, `Body.error`, and `Body.pp_error`. The existing
`Body.to_string` API remains unchanged, while code preparing for streaming body
support now has an explicit bounded in-memory read path.

## Commit

```text
feat: add limited body read
```
