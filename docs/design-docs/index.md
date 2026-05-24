# Design Docs

This directory is the source of truth for Choku's technical design.

## Current Documents

- [Core Beliefs](core-beliefs.md)
- [Future Work](future-work.md)
- [HTTP Request Limits And Timeouts](http-request-limits-and-timeouts.md)
- [HTTP/1.1 Chunked Request Bodies](http1-chunked-request-bodies.md)
- [HTTP/1.1 Persistent Connections](http1-persistent-connections.md)
- [Initial Architecture](initial-architecture.md)
- [Minimal Router DSL](minimal-router-dsl.md)
- [Minimal Server, Handler, and Middleware API](minimal-server-handler-middleware-api.md)
- [Multipart Form-Data Support](multipart-form-data.md)
- [Project Layout and Tooling](project-layout-and-tooling.md)
- [Router HEAD And 405 Semantics](router-head-and-405.md)
- [Response Streaming](response-streaming.md)
- [Route-Level Body Mode](route-level-body-mode.md)
- [Streaming Request Bodies](streaming-request-bodies.md)
- [URL-Encoded Form Support](form-urlencoded.md)
- [ADR Index](adr/index.md)

## When To Add Or Update A Design Doc

Create or update a design document when a change affects:

- module boundaries or package structure;
- public APIs or long-lived internal interfaces;
- concurrency, resource ownership, cancellation, or error handling;
- parser, encoder, protocol, or network behavior;
- performance, observability, reliability, or security posture.

For a major specification change, update the relevant design document and add an
ADR that records the decision, alternatives, and consequences.

## Suggested Design Doc Template

```markdown
# Title

## Status

Draft | Accepted | Superseded

## Context

What problem exists, what constraints matter, and what prior documents apply?

## Goals

What must this design achieve?

## Non-Goals

What is intentionally out of scope?

## Proposed Design

Describe the architecture, interfaces, and important behaviors.

## Contracts

List public APIs, function signatures, types, and invariants that must be stable
enough to implement against. Public contracts must be documented with block
comments in source files.

## Alternatives Considered

List credible alternatives and why they were not chosen.

## Third-Party Review

Record feedback from a context-free sub-agent review and how the design changed
before implementation.

## Validation

How will tests, benchmarks, examples, or reviews prove this design works?

## Open Questions

List unresolved decisions that block or shape implementation.
```
