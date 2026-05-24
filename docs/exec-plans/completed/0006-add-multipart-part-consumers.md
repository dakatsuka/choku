# Add Multipart Part Consumers

## Status

Completed

## Objective

Add Phase 2 convenience helpers for consuming buffered multipart parts through
Eio sinks and paths, without changing `Request.t`, `Body.t`, or the Phase 1
multipart parser.

## Context

- [Agent Guide](../../../AGENTS.md)
- [Multipart Form-Data Product Spec](../../product-specs/multipart-form-data.md)
- [Multipart Form-Data Design](../../design-docs/multipart-form-data.md)
- [Buffered Multipart Form-Data Plan](../completed/0005-implement-buffered-multipart-form-data.md)

## Clarifications

- Keep part bodies buffered in this phase.
- Add direct-style Eio consumer helpers so upload handlers can write part bytes
  to an application-owned sink or path.
- Do not add streaming request bodies, automatic tempfile management, filename
  sanitization, or storage policy.

## Contract First

Extend `Multipart.Part` with documented helpers:

- `copy_to_sink`;
- `save_to_path`.

## Steps

- [x] Explore: inspect Eio sink/path APIs and current multipart implementation.
- [x] Design review: keep the change scoped to buffered consumer helpers.
- [x] Red: write failing behavior-focused tests in `test/test_multipart.ml`.
- [x] Green: implement the smallest `lib/multipart.ml` change that satisfies
      the tests.
- [x] Refactor: keep helper naming and contracts clear.
- [x] Static checks: run formatters and static analysis tools, then fix
      findings.
- [x] Code review: perform local review and address findings.

## Decisions

- `copy_to_sink` uses `Eio.Flow.copy_string` over the buffered part body.
- `save_to_path` uses `Eio.Path.save` with caller-provided creation policy.
- The application remains responsible for filename validation and destination
  selection.

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

## Completion Notes

Added `Multipart.Part.copy_to_sink` and `Multipart.Part.save_to_path` so
handlers can consume buffered part bodies through caller-owned Eio sinks and
paths. Storage policy, filename validation, and streaming bodies remain deferred
to later phases.

## Commit

```text
feat: add multipart part consumers
```
