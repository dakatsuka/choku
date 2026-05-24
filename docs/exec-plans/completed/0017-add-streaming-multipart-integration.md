# Add Streaming Multipart Integration

## Status

Completed

## Objective

Verify and demonstrate streaming multipart uploads through the real HTTP server
path.

## Context

- [Agent Guide](../../../AGENTS.md)
- [Multipart Form-Data Support](../../product-specs/multipart-form-data.md)
- [Streaming Request Bodies](../../design-docs/streaming-request-bodies.md)
- [Add Opt-In Streaming Request Bodies](../completed/0014-add-opt-in-streaming-request-bodies.md)
- [Add Streaming Multipart Iterator](../completed/0016-add-streaming-multipart-iterator.md)

## Clarifications

- No library API changes are planned.
- Add end-to-end network tests for `Server.create ~request_body_mode:Streaming`
  plus `Multipart.Streaming.iter_request`.
- Add an example server that streams uploaded file parts to an application-owned
  sink.

## Contract First

No public contract changes. The tests and example should exercise the existing
contracts:

- server streaming request bodies;
- `Multipart.Streaming.iter_request` callback-scoped part sources;
- malformed multipart errors surfaced to handlers as `Multipart.error`.

## Steps

- [x] Explore: inspect server tests, examples, multipart docs, and current
      streaming APIs.
- [x] Design review: request context-free third-party review before
      implementation.
- [x] Red: add server-level streaming multipart tests.
- [x] Green: implement example and any test helpers needed.
- [x] Refactor: keep tests focused and example minimal.
- [x] Static checks: run formatters and static analysis tools, then fix
      findings.
- [x] Code review: request context-free third-party review after implementation.
- [x] Re-review: fix review findings and repeat review until it passes.

## Decisions

- Keep integration tests focused on the composition path: actual HTTP request,
  streaming server mode, streaming request body, and
  `Multipart.Streaming.iter_request`.
- Count file-part bytes from the part source with a small buffer instead of
  reading the file part into a string in the handler.
- Treat malformed multipart handling as application-owned: the handler maps
  `Multipart.error` to `400 Bad Request`.
- The example counts uploaded file bytes and leaves storage policy to the
  application.

## Verification

- `dune build @fmt`
- `dune build @all`
- `dune runtest`
- `CHOKU_RUN_NETWORK_TESTS=1 dune exec test/test_server.exe`
- `dune build @check`
- `dune build @install`
- `opam lint choku.opam`

## Completion Notes

Added server-level streaming multipart integration tests and a
`choku-upload-streaming` example. The successful network test exercises an
actual HTTP multipart upload through `Server.create ~request_body_mode:Streaming`
and `Multipart.Streaming.iter_request`. The malformed multipart integration test
shows the handler mapping multipart parser errors to `400 Bad Request`.

Code review found stale product-spec phase text; it was updated and re-review
passed.

## Commit

`test: add streaming multipart server integration`
