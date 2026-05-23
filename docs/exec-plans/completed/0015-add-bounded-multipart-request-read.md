# Add Bounded Multipart Request Read

## Status

Completed

## Objective

Add a bounded multipart request helper that can consume both buffered and
server-created streaming request bodies without using unbounded `Body.to_string`.

## Context

- [Agent Guide](../../../AGENTS.md)
- [Multipart Form-Data Support](../../product-specs/multipart-form-data.md)
- [Streaming Request Bodies](../../design-docs/streaming-request-bodies.md)
- [Add Opt-In Streaming Request Bodies](../completed/0014-add-opt-in-streaming-request-bodies.md)

## Clarifications

- Do not implement true streaming multipart parsing in this plan.
- Preserve existing `Multipart.of_request` behavior for buffered request bodies.
- Add an explicit bounded API for code that may receive streaming request bodies.

## Contract First

Extend `Multipart` with:

```ocaml
type error =
  | Missing_content_type
  | Unsupported_content_type of string
  | Missing_boundary
  | Malformed_body
  | Body_too_large
  | Unexpected_end_of_body

val of_request_limited :
  max_size:int -> Request.t -> (t, error) result
```

`of_request_limited ~max_size request` validates the `Content-Type` and boundary
like `of_request`, then reads the request body with `Body.to_string_limited
~max_size`. `Body.Body_too_large` maps to `Multipart.Body_too_large`.
`Body.Unexpected_end_of_body` maps to `Multipart.Unexpected_end_of_body`.

## Steps

- [x] Explore: inspect current Multipart, Body streaming behavior, docs, and
      tests.
- [x] Design review: request context-free third-party review before
      implementation.
- [x] Red: add tests for bounded multipart request parsing and streaming-body
      error mapping.
- [x] Green: implement the bounded helper with shared content-type handling.
- [x] Refactor: keep existing buffered `of_request` behavior stable.
- [x] Static checks: run formatters and static analysis tools, then fix
      findings.
- [x] Code review: request context-free third-party review after implementation.
- [x] Re-review: fix review findings and repeat review until it passes.

## Decisions

- Add direct `Multipart.error` variants instead of exposing `Body.error` through
  a wrapper.
- Validate `Content-Type` and boundary before consuming the request body, because
  streaming request bodies are single-consumption.
- Keep `Multipart.of_request` as the buffered compatibility helper. It continues
  to use `Body.to_string` and is not streaming-capable.

## Verification

- `dune build @fmt`
- `dune build @all`
- `dune runtest`
- `dune build @check`
- `dune build @install`
- `opam lint camelio.opam`

## Completion Notes

Added `Multipart.of_request_limited ~max_size` as a bounded adapter for parsing
multipart request bodies that may be streaming. The helper validates negative
limits first, validates content type and boundary before consuming the body, then
uses `Body.to_string_limited` and maps body read errors into `Multipart.error`.

Existing `Multipart.of_request` remains a buffered compatibility helper and
continues to use `Body.to_string`.

Code review found one low-severity validation-order issue for negative
`max_size`; it was fixed and re-review passed.

## Commit

Pending.
