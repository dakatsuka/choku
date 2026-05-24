# Add Multipart Tempfile Helper

## Status

Completed

## Objective

Add a small multipart tempfile helper that writes buffered or streaming upload
bytes to an application-provided temporary directory using generated storage
names.

## Context

- [Agent Guide](../../../AGENTS.md)
- [Multipart Form-Data Support](../../product-specs/multipart-form-data.md)
- [Multipart Form-Data Design](../../design-docs/multipart-form-data.md)
- [File Upload Filename Safety](../../references/file-upload-filename-safety.md)

## Clarifications

- The user wants to proceed with a tempfile helper after reviewing the design
  tradeoffs.
- Do not make Choku choose `/tmp` or any global temporary directory.
- Do not use client supplied filenames as storage names.

## Contract First

Add:

```ocaml
module Multipart.Tempfile : sig
  type 'a t constraint 'a = [> Eio.Fs.dir_ty ]

  val path : 'a t -> 'a Eio.Path.t
  val original_filename : 'a t -> string option
  val display_filename : 'a t -> string option
  val size : 'a t -> int

  val save_source :
    dir:'a Eio.Path.t ->
    random:Eio.Flow.source_ty Eio.Resource.t ->
    ?original_filename:string ->
    Eio.Flow.source_ty Eio.Resource.t ->
    'a t

  val save_part :
    dir:'a Eio.Path.t ->
    random:Eio.Flow.source_ty Eio.Resource.t ->
    Part.t ->
    'a t
end
```

`save_source` generates a storage filename with secure random bytes from the
provided source, creates the file with `` `Exclusive 0o600 ``, streams bytes to
it, and best-effort unlinks the partial file if copying fails. Successful files
remain application-owned and are not automatically cleaned up.

## Steps

- [x] Explore: inspect existing body, multipart, Eio path, and random APIs.
- [x] Design review: not delegated because the available multi-agent tool only
      allows delegation on explicit user request.
- [x] Red: add tempfile behavior tests to `test/test_multipart.ml`.
- [x] Green: implement `Multipart.Tempfile`.
- [x] Refactor: keep generation/copy helpers small and local.
- [x] Static checks: run formatters and static analysis tools, then fix
      findings.
- [x] Code review: not delegated because the available multi-agent tool only
      allows delegation on explicit user request.
- [x] Re-review: self-review after checks.

## Decisions

- Accept an Eio secure random source explicitly rather than depending on global
  randomness.
- Accept an application-owned temp directory capability rather than choosing a
  global temp location.
- Use generated storage names only; client filenames are retained as metadata
  and sanitized display candidates.
- Leave successful tempfile cleanup to applications. Only failed writes get
  best-effort cleanup.

## Verification

- `dune build @fmt`
- `dune exec test/test_multipart.exe`
- `dune build @all`
- `dune runtest`
- `dune build @check`
- `dune build @install`
- `opam lint choku.opam`

## Completion Notes

Added `Multipart.Tempfile` with generated exclusive tempfiles under an
application-provided Eio directory capability. Tests cover source saving,
buffered part saving, collision retry, metadata, byte counts, and failed-copy
cleanup. The streaming upload example now persists file parts to generated
tempfiles under `_choku_uploads`.

## Commit

`feat: add multipart tempfile helper`
