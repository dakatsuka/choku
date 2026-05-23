# Initial Architecture

## Status

Draft

## Context

Camelio starts from an empty Git repository and targets OCaml 5.4 with Eio. The
project should provide an HTTP server without depending on existing OCaml HTTP
server stacks such as `cohttp`, and without using alternative concurrency
runtimes such as `lwt` or `async`.

## Goals

- Define a small server architecture that maps naturally to Eio fibers,
  switches, flows, and cancellation.
- Keep parsing, request handling, response writing, and connection lifecycle
  responsibilities separate.
- Make protocol behavior testable without opening real network sockets where
  possible.
- Leave room for HTTP/1.1 first, with later extension points for TLS,
  observability, benchmarks, and additional protocol features.

## Non-Goals

- Supporting `cohttp`, `lwt`, or `async` compatibility layers.
- Implementing HTTP/2 or HTTP/3 in the initial design.
- Providing a full web framework, router, template system, or middleware stack
  before the core server behavior is specified.

## Candidate Module Boundaries

- `Camelio`: public entry point.
- `Camelio.Server`: accept loop, connection lifecycle, handler invocation.
- `Camelio.Http`: request, response, method, header, status, and body types.
- `Camelio.Http1`: HTTP/1 parser and encoder.
- `Camelio.Body`: streaming request and response body abstractions.
- `Camelio.Error`: public and internal error classification.
- `Camelio.Test_support`: helpers for protocol-level tests.

These names are provisional until the first implementation plan confirms package
layout and build tooling.

## Concurrency Model

Each accepted connection should run in an Eio fiber under a switch owned by the
server. Connection-local resources must be tied to the connection scope. Request
handling should honor Eio cancellation and must not require a secondary runtime.

## Validation

The initial implementation plan should introduce:

- a build system;
- unit tests for HTTP value types and parser behavior;
- integration tests for a minimal Eio server loop;
- an example server that can be manually exercised.

## Open Questions

- Which test framework should be used?
- Should the first parser be handwritten or built with a parser combinator?
- What is the minimum supported HTTP/1.1 feature set for the first release?
