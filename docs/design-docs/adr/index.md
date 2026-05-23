# Architecture Decision Records

ADRs record important decisions that future agents and maintainers should not
have to rediscover from commit history.

## Records

- [0001: Use OCaml 5.4 and Eio without cohttp, lwt, or async](0001-use-ocaml-54-and-eio.md)

## When To Write An ADR

Write an ADR when a decision:

- changes a major product or protocol requirement;
- changes the architecture or dependency policy;
- has meaningful tradeoffs or rejected alternatives;
- is likely to be questioned by future contributors;
- supersedes a previous design document.

## ADR Template

```markdown
# NNNN: Title

## Status

Proposed | Accepted | Superseded

## Date

YYYY-MM-DD

## Context

What forces made this decision necessary?

## Decision

What decision was made?

## Alternatives Considered

What else was considered?

## Consequences

What becomes easier, harder, or intentionally unsupported?

## References

- Related design docs, product specs, execution plans, issues, or external
  references.
```
