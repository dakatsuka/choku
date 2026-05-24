# Core Beliefs

## Status

Accepted

## Principles

- Choku is a pure Eio HTTP server for OCaml 5.
- The name "Choku" means "direct" in Japanese, reflecting the project's
  direct-style Eio programming model.
- The project optimizes for clear, inspectable OCaml rather than broad framework
  compatibility.
- Effects-based structured concurrency is a central design feature, not an
  adapter layer over another IO runtime.
- Protocol behavior should be specified before it is implemented.
- Public interfaces, signatures, types, and contracts should be designed before
  internal implementation.
- Implementation should follow an Explore -> Red -> Green -> Refactor cycle.
- Static analysis and formatters should be treated as required feedback loops
  where available.
- Agent-facing repository knowledge must be versioned, indexed, and local to the
  repository.

## Dependency Policy

Choku must not depend on `cohttp`, `lwt`, or `async`.

Allowed dependencies should be justified by one of these needs:

- OCaml build and test infrastructure;
- Eio runtime support;
- small, focused libraries for parsing, serialization, testing, or benchmarking
  when implementing them locally would distract from the HTTP server itself.

## Documentation Policy

Documentation is part of the harness. Agents should be able to infer project
intent from repository files rather than external conversation history.

Use:

- product specs for externally visible behavior;
- design docs for internal architecture;
- execution plans for complex implementation work;
- ADRs for important or irreversible decisions;
- references for external context that should be visible to future agents.

## Review Policy

Designs require context-free third-party review before implementation begins.
Implemented code requires context-free third-party review after tests and static
checks have run. Review findings must be fixed and reviewed again until no
blocking findings remain.
