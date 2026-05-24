# Add Buffered Body Source Access

## Status

Completed

## Objective

Add a non-breaking `Body.with_source` helper for current buffered bodies so
applications and future multipart code can consume body bytes through Eio source
APIs before full streaming request bodies are implemented.

## Context

- [Agent Guide](../../../AGENTS.md)
- [Streaming Request Bodies](../../design-docs/streaming-request-bodies.md)
- [ADR 0002](../../design-docs/adr/0002-introduce-streaming-bodies-with-buffered-compatibility.md)

## Clarifications

- Keep `Body.t` internally buffered in this plan.
- Do not change `Request.t`, `Server`, or HTTP/1.1 body buffering behavior.
- Add only compatibility helpers that make future streaming APIs easier to adopt.

## Contract First

Extend `Body` with documented helpers:

- `is_buffered`;
- `with_source`.

## Steps

- [x] Explore: inspect existing body implementation and Eio source APIs.
- [x] Design review: use the streaming body design as the guiding contract.
- [x] Red: write failing behavior-focused tests in `test/test_body.ml`.
- [x] Green: implement the smallest `lib/body.ml` change that satisfies the
      tests.
- [x] Refactor: keep the body abstraction simple.
- [x] Static checks: run formatters and static analysis tools, then fix
      findings.
- [x] Code review: perform local review and address findings.

## Decisions

- `is_buffered` returns `true` for all current bodies.
- `with_source` creates an `Eio.Flow.string_source` for the buffered body bytes
  and passes it to the caller in direct style.

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

Added `Body.is_buffered` and `Body.with_source` for existing replayable buffered
bodies. `with_source` currently exposes an `Eio.Flow.string_source`, providing a
non-breaking stepping stone toward future streaming request bodies.

## Commit

```text
feat: add buffered body source access
```
