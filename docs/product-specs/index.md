# Product Specs

Product specs define externally visible behavior and user expectations.

## Current Specs

- [Project Charter](project-charter.md)

## When To Add Or Update A Product Spec

Create or update a product spec when work affects:

- public API behavior;
- supported HTTP methods, status codes, headers, bodies, or connection behavior;
- compatibility promises;
- examples, tutorials, or user-facing workflows;
- release criteria.

Implementation should not silently invent product behavior. If behavior matters
to users, capture it here before or during implementation.

## Product Spec Template

```markdown
# Title

## Status

Draft | Accepted | Superseded

## Problem

What user need or product requirement does this address?

## Goals

What must be true for users?

## Non-Goals

What is explicitly out of scope?

## Requirements

Specific behavior, compatibility, and error handling requirements.

## Examples

Representative usage or protocol examples.

## Open Questions

Unresolved product decisions.
```
