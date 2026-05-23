# Harness Engineering Notes

## Source

- URL: https://openai.com/ja-JP/index/harness-engineering/
- Accessed: 2026-05-23

## Summary

OpenAI's harness engineering article describes an agent-first development model
where humans design the environment, clarify intent, and build feedback loops for
agents. A key recommendation is to avoid a single large agent instruction file.
Instead, the repository should use a short `AGENTS.md` as a map and keep deeper
knowledge in structured, versioned documentation.

The article's repository knowledge layout includes design documents, execution
plans, product specs, and references. Plans are treated as first-class artifacts,
and repository-local knowledge is preferred because agents cannot reliably use
context that is only stored in external conversations or people's memory.

## Implications For Camelio

- Keep `AGENTS.md` short and navigational.
- Store durable project knowledge under `docs/`.
- Use execution plans for complex work.
- Record major design changes as ADRs so future agents can understand why the
  design moved.
- Keep references local when they materially shape implementation.
