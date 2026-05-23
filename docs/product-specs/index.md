# Product Specs

Product specs define externally visible behavior and user expectations.

## Current Specs

- [Minimal HTTP/1.1 Server Milestone](minimal-http1-server.md)
- [Minimal Router DSL](minimal-router-dsl.md)
- [Minimal Server API](minimal-server-api.md)
- [Project Charter](project-charter.md)
- [URL-Encoded Form Support](form-urlencoded.md)

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

## Public Contracts

User-visible APIs, function signatures, types, and invariants that design and
implementation must preserve.

## Examples

Representative usage or protocol examples.

## Open Questions

Unresolved product decisions. Ask clarifying questions instead of proceeding by
assumption when these affect implementation.
```
