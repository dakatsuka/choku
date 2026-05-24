# Implement Buffered Multipart Form-Data

## Status

Completed

## Objective

Implement Phase 1 of `Choku.Multipart`: a buffered parser for
`multipart/form-data` request bodies with ordered parts, part metadata, and
structured parse errors.

## Context

- [Agent Guide](../../../AGENTS.md)
- [Multipart Form-Data Product Spec](../../product-specs/multipart-form-data.md)
- [Multipart Form-Data Design](../../design-docs/multipart-form-data.md)
- [URL-Encoded Form Support](../../product-specs/form-urlencoded.md)
- [Minimal Server API](../../product-specs/minimal-server-api.md)

## Clarifications

- Implement only Phase 1 buffered multipart parsing in this plan.
- Keep `Request.t`, `Body.t`, and `Server` unchanged.
- Do not implement streaming upload, tempfile management, nested multipart, or
  extended MIME parameter decoding.
- Return result errors for malformed multipart input instead of raising.

## Contract First

Create public signatures and block comments for:

- `Multipart`;
- `Multipart.error`;
- `Multipart.Part`;
- raw decoding and request parsing functions;
- ordered part accessors;
- error formatter.

Update the public `Choku` module and dune/test layout after the interface is
defined.

## Steps

- [x] Explore: inspect existing code, specs, design docs, and tests.
- [x] Design review: document the Phase 1 design and delegation constraint.
- [x] Red: write failing behavior-focused tests in `test/test_multipart.ml`.
- [x] Green: implement the smallest `lib/multipart.ml` that satisfies the tests.
- [x] Refactor: improve parser clarity while keeping tests green.
- [x] Static checks: run formatters and static analysis tools, then fix
      findings.
- [x] Code review: perform local review and address findings.

## Decisions

- Add `Choku.Multipart` as a new top-level module.
- Keep `Multipart.t` abstract and ordered.
- Represent Phase 1 part bodies with existing buffered `Body.t`.
- Keep URL-encoded `Form` separate from multipart parts.
- Defer Eio streaming upload behavior to later phases.

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

Implemented `Choku.Multipart` Phase 1 with buffered multipart/form-data
parsing, request `Content-Type` and boundary handling, ordered parts, part
metadata accessors, structured errors, and error formatting. Eio streaming
upload behavior remains deferred to later phases.

## Commit

```text
feat: implement buffered multipart form-data
```
