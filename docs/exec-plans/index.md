# Execution Plans

Execution plans are first-class development artifacts for substantial work.

## Directories

- `active/`: plans currently being implemented.
- `completed/`: finished plans with final notes and verification results.

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

## Steps

- [ ] Step one.
- [ ] Step two.

## Decisions

Record implementation decisions made during the work.

## Verification

List commands, tests, examples, or manual checks.

## Completion Notes

Summarize what changed and any follow-up work.
```
