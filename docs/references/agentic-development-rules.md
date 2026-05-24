# Agentic Development Rules

## Source

- Origin: Maintainer-provided repository policy.
- Captured: 2026-05-23

## Summary

Choku development should use explicit feedback loops around design,
implementation, review, tests, and static analysis.

## Rules

- Ask clarifying questions when instructions are unclear.
- After design work, request context-free third-party review from a sub-agent and
  incorporate feedback before implementation.
- After implementation, request context-free code review from a sub-agent. Fix
  findings and repeat review until it passes.
- Use an Explore -> Red -> Green -> Refactor cycle.
- Keep modules, classes, functions, and values focused on minimal
  responsibilities.
- Decide public APIs, signatures, and types before implementing internals.
- Explain interfaces and contracts with block comments.
- Prefer naming and structure that remain readable to future maintainers and
  agentic AI.
- Run available static analysis and formatting tools, then fix their findings.
  Use tools for mechanically checkable formatting instead of relying on prompts
  or manual AI edits.
- Write commit messages according to Conventional Commits.
- Create unit test files per module. For OCaml, use one unit test file per
  source file under test.
