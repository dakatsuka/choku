# Implement URL-Encoded Form Support

## Status

Completed

## Objective

Implement `Camelio.Form`, an optional parser for
`application/x-www-form-urlencoded` request bodies that exposes ordered repeated
fields and structured parse errors.

## Context

- [Agent Guide](../../../AGENTS.md)
- [URL-Encoded Form Product Spec](../../product-specs/form-urlencoded.md)
- [URL-Encoded Form Design](../../design-docs/form-urlencoded.md)
- [Minimal Server API](../../product-specs/minimal-server-api.md)
- [Minimal Server, Handler, and Middleware API](../../design-docs/minimal-server-handler-middleware-api.md)

## Clarifications

- Implement only URL-encoded forms in this milestone.
- Keep multipart design and implementation for later phased work.
- Keep `Request.t` and `Body.t` unchanged.
- Return result errors for malformed form input instead of raising.
- Decode bytes without character set transcoding or UTF-8 validation.

## Contract First

Create public signatures and block comments for:

- `Form`;
- `Form.error`;
- decoding and request parsing functions;
- ordered multimap accessors;
- error formatter.

Update the public `Camelio` module and dune/test layout after the interface is
defined.

## Steps

- [x] Explore: inspect existing code, specs, design docs, and tests.
- [x] Design review: document the narrow design and delegation constraint.
- [x] Red: write failing behavior-focused tests in `test/test_form.ml`.
- [x] Green: implement the smallest `lib/form.ml` that satisfies the tests.
- [x] Refactor: improve parser clarity while keeping tests green.
- [x] Static checks: run formatters and static analysis tools, then fix
      findings.
- [x] Code review: perform local review and address findings.

## Decisions

- Add `Camelio.Form` as a new top-level module.
- Keep `Form.t` abstract and ordered.
- Use `decode` for raw payloads and `of_request` for content-type checked
  request parsing.
- Treat multipart as separate future work.

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

Implemented `Camelio.Form` with URL-encoded payload decoding, request
`Content-Type` checks, ordered repeated fields, structured errors, and error
formatting. Multipart remains deferred to a separate phased design.

## Commit

```text
feat: implement url-encoded form support
```
