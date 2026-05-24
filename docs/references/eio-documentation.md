# Eio Documentation

## Source

- API documentation: https://ocaml-multicore.github.io/eio/
- Package source: https://github.com/ocaml-multicore/eio
- Documentation branch: https://github.com/ocaml-multicore/eio/tree/gh-pages
- opam package: https://opam.ocaml.org/packages/eio/
- Accessed: 2026-05-23

## Observed Version

The Eio odoc index showed `eio`, `eio_linux`, `eio_main`, `eio_posix`, and
`eio_windows` at version 1.2 on 2026-05-23.

The opam package page showed `eio` 1.3 as the latest release on 2026-05-23. This
means the published GitHub Pages manual may lag behind the latest package
release. Before relying on version-sensitive behavior, verify the Eio version
that Choku intends to build against and inspect the matching source tag or
package documentation.

## Summary

Eio is the core IO and concurrency dependency for Choku. The official package
documentation is generated with odoc and published at the GitHub Pages URL. The
published site is backed by the repository's `gh-pages` branch, while the main
GitHub repository contains tutorials, examples, issues, and implementation
history.

For implementation work, prefer the published API documentation for signatures
and module contracts. Use the GitHub repository when the generated documentation
does not explain behavior, examples, or recent changes well enough.

## Agent Usage

Before designing or implementing Eio-facing code, inspect the current
documentation for the relevant modules. Common starting points include:

- `Eio`: fibers, switches, resources, networking, byte streams, and errors;
- `Eio_main`: the default event loop entry point for applications;
- `Eio.Net`: network sockets, listening, accepting, and connecting;
- `Eio.Flow`: byte-stream reading and writing contracts;
- `Eio.Switch`: resource lifetime and cancellation scope;
- `Eio.Buf_read` and `Eio.Buf_write`: buffered protocol parsing and writing.

Record any Eio behavior that Choku depends on in the relevant product spec,
design doc, or ADR. Do not rely on a bare external link as the only statement of
required behavior.

If the published odoc version and latest opam release differ, prefer the
project's pinned Eio version once it exists. Until then, call out the version
assumption in the execution plan and avoid depending on APIs that are only
documented in one source.

## Update Policy

- Refresh this reference when updating Eio, changing OCaml versions, or touching
  server lifecycle, networking, flow, cancellation, or buffering code.
- If the observed Eio version changes, update this document and any affected
  design docs or ADRs.
- If a live documentation detail affects implementation, cite the exact module
  page and access date in the corresponding execution plan.
- If opam latest and the GitHub Pages manual disagree, document the mismatch and
  verify behavior against the intended package version before implementation.
