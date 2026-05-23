# Bootstrap Project Harness

## Status

Completed

## Objective

Create the repository-local documentation harness that lets future agents capture
specifications, designs, execution plans, references, and architecture decisions.

## Context

- [Agent Guide](../../../AGENTS.md)
- [Design Docs](../../design-docs/index.md)
- [Product Specs](../../product-specs/index.md)
- [References](../../references/index.md)

## Steps

- [x] Create the agent entry point.
- [x] Create documentation directories and indexes.
- [x] Capture the initial product spec and design constraints.
- [x] Add an ADR process and the first ADR.
- [x] Commit the bootstrap harness.

## Decisions

- Use `AGENTS.md` as the canonical agent entry point.
- Keep detailed guidance in `docs/` rather than expanding `AGENTS.md`.
- Record major specification changes as ADRs in addition to updating design docs.

## Verification

- Documentation-only change; verified with file review and Git status.

## Completion Notes

The initial agent-facing documentation harness is in place. Future substantive
work should start from the relevant index and create or update specs, design
docs, execution plans, references, and ADRs as appropriate.
