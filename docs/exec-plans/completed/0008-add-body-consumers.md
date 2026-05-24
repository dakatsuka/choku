# Add Body Consumers

## Status

Completed

## Objective

Add `Body.copy_to_sink` and `Body.save_to_path` as direct-style Eio consumers
for body bytes, then make multipart part consumers delegate to those helpers.

## Context

- [Agent Guide](../../../AGENTS.md)
- [Streaming Request Bodies](../../design-docs/streaming-request-bodies.md)
- [ADR 0002](../../design-docs/adr/0002-introduce-streaming-bodies-with-buffered-compatibility.md)
- [Add Buffered Body Source Access](../completed/0007-add-buffered-body-source.md)

## Clarifications

- Keep `Body.t` internally buffered in this plan.
- Do not implement live request streaming yet.
- Use `Body.with_source` for sink copying so future streaming support has one
  shared body-consumption path.

## Contract First

Extend `Body` with documented helpers:

- `copy_to_sink`;
- `save_to_path`.

## Steps

- [x] Explore: inspect current `Body` and `Multipart.Part` consumers.
- [x] Design review: keep the change as a non-breaking stepping stone.
- [x] Red: write failing behavior-focused tests in `test/test_body.ml`.
- [x] Green: implement `Body` consumers and delegate multipart consumers.
- [x] Refactor: keep multipart consumers thin wrappers.
- [x] Static checks: run formatters and static analysis tools, then fix
      findings.
- [x] Code review: perform local review and address findings.

## Decisions

- `copy_to_sink` uses `with_source` and `Eio.Flow.copy`.
- `save_to_path` uses `Eio.Path.save` while bodies remain buffered.
- `Multipart.Part.copy_to_sink` and `save_to_path` delegate to `Body`.

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

Added `Body.copy_to_sink` and `Body.save_to_path`. Multipart part consumers now
delegate to the shared `Body` helpers, keeping one body-consumption path for the
future streaming implementation.

## Commit

```text
feat: add body consumers
```
