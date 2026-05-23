# Execution Plans

Execution plans are first-class development artifacts for substantial work.

## Directories

- `active/`: plans currently being implemented.
- `completed/`: finished plans with final notes and verification results.

## Active Plans

None.

## Completed Plans

- [Bootstrap Project Harness](completed/0001-bootstrap-project-harness.md)
- [Implement Minimal HTTP/1.1 Server](completed/0002-implement-minimal-http1-server.md)
- [Implement Minimal Router DSL](completed/0003-implement-minimal-router-dsl.md)
- [Implement URL-Encoded Form Support](completed/0004-implement-form-urlencoded.md)
- [Implement Buffered Multipart Form-Data](completed/0005-implement-buffered-multipart-form-data.md)
- [Add Multipart Part Consumers](completed/0006-add-multipart-part-consumers.md)
- [Add Buffered Body Source Access](completed/0007-add-buffered-body-source.md)
- [Add Body Consumers](completed/0008-add-body-consumers.md)
- [Add Limited Body Read](completed/0009-add-limited-body-read.md)
- [Extract HTTP/1.1 Request Head Parser](completed/0010-extract-http1-request-head-parser.md)
- [Split Server Request Reading](completed/0011-split-server-request-reading.md)
- [Introduce Body Internal Variants](completed/0012-introduce-body-internal-variants.md)
- [Build Server Request From Parsed Head](completed/0013-build-server-request-from-head.md)
- [Add Opt-In Streaming Request Bodies](completed/0014-add-opt-in-streaming-request-bodies.md)

## When To Create A Plan

Create an execution plan when work spans multiple files, introduces a subsystem,
changes public behavior, or requires staged verification.

Small local fixes may be completed without a checked-in plan if the relevant
product spec and design docs are already clear.

## Plan Template

```markdown
# Title

## Status

Active | Completed | Abandoned

## Objective

What outcome should exist when this plan is complete?

## Context

Which specs, design docs, ADRs, and references govern this work?

## Clarifications

List questions asked before implementation and the answers that removed
ambiguity. Do not proceed on unclear instructions by guessing.

## Contract First

List public APIs, function signatures, types, and contract comments to create
before internal implementation.

## Steps

- [ ] Explore: inspect existing code, specs, design docs, and tests.
- [ ] Design review: request context-free third-party review and incorporate
      feedback.
- [ ] Red: write failing behavior-focused tests, with unit test files organized
      per module. For OCaml, create one unit test file per source file under
      test.
- [ ] Green: implement the smallest change that satisfies the tests.
- [ ] Refactor: improve structure while keeping tests green.
- [ ] Static checks: run formatters and static analysis tools, then fix findings.
- [ ] Code review: request context-free third-party review after implementation.
- [ ] Re-review: fix review findings and repeat review until it passes.

## Decisions

Record implementation decisions made during the work.

## Verification

List test commands, static analysis commands, format commands, examples, or
manual checks.

## Completion Notes

Summarize what changed and any follow-up work.

## Commit

Record the Conventional Commits-compliant commit message used for the work.
```
