# Camelio Agent Guide

Camelio is an OCaml 5.4 HTTP server project built around the slogan:

> A pure Eio HTTP server for OCaml 5.

This file is the small, stable entry point for agentic development. Treat the
repository documentation as the source of truth; do not turn this file into a
large manual.

## Repository Map

- `docs/design-docs/`: architecture, design constraints, subsystem designs,
  and Architecture Decision Records.
- `docs/exec-plans/`: active and completed execution plans for substantial
  implementation work.
- `docs/product-specs/`: product-facing requirements, API behavior, and
  compatibility expectations.
- `docs/references/`: copied or summarized external references that agents need
  during implementation.

Start with the relevant index before making changes:

- [Design Docs](docs/design-docs/index.md)
- [Execution Plans](docs/exec-plans/index.md)
- [Product Specs](docs/product-specs/index.md)
- [References](docs/references/index.md)

## Engineering Constraints

- Target OCaml 5.4.
- Use Eio for effects-based IO and concurrency.
- Do not depend on `cohttp`, `lwt`, or `async`.
- Prefer small, explicit modules with behavior documented by tests.
- Keep public APIs narrow until requirements are captured in a product spec.
- Write repository documentation, source comments, commit messages, and public
  technical artifacts in English.

## Documentation Workflow

- New product behavior starts in `docs/product-specs/`.
- New architecture or internal design starts in `docs/design-docs/`.
- Substantial implementation work gets an execution plan in
  `docs/exec-plans/active/`, then moves to `docs/exec-plans/completed/` when
  finished.
- Major design changes require both an updated design document and a new ADR in
  `docs/design-docs/adr/`.
- External references that materially affect implementation should be captured
  under `docs/references/` so future agents can operate from repository-local
  context.

## Quality Bar

- Before finishing implementation work, run the most specific available test
  command and record the result in the final response.
- If no test harness exists yet, state that explicitly and prefer adding one as
  part of the next implementation plan.
- Do not hide unresolved design questions in code comments; record them in the
  relevant spec, design doc, or execution plan.
