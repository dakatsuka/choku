# 0001: Use OCaml 5.4 and Eio without cohttp, lwt, or async

## Status

Accepted

## Date

2026-05-23

## Context

Choku is starting as a new HTTP server project for OCaml 5. The project slogan
is "A pure Eio HTTP server for OCaml 5." Existing OCaml HTTP and concurrency
ecosystems provide useful precedent, but adopting them would make the project an
adapter around another runtime or server stack instead of a native Eio design.

## Decision

Choku targets OCaml 5.4 and Eio. It will not depend on `cohttp`, `lwt`, or
`async`.

## Alternatives Considered

- Build on `cohttp`: rejected because it would make Choku a wrapper around an
  existing HTTP stack.
- Support `lwt` or `async` adapters from the start: rejected because early design
  should focus on Eio-native resource ownership, cancellation, and structured
  concurrency.
- Keep runtime support abstract: rejected because a runtime abstraction would add
  complexity before the core server behavior exists.

## Consequences

- The initial implementation can model network IO, cancellation, and resource
  scopes directly with Eio.
- Some ecosystem integrations will be intentionally unavailable at first.
- Protocol behavior, parser behavior, and server lifecycle must be implemented
  and tested within this repository.
- Dependency additions need explicit justification against the project slogan.

## References

- [Core Beliefs](../core-beliefs.md)
- [Initial Architecture](../initial-architecture.md)
