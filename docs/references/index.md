# References

References store external context that future agents need available inside the
repository.

## Current References

- [Agentic Development Rules](agentic-development-rules.md)
- [Eio Documentation](eio-documentation.md)
- [File Upload Filename Safety](file-upload-filename-safety.md)
- [Harness Engineering Notes](harness-engineering-notes.md)
- [HTTP Server Limits And Timeouts](http-server-limits-and-timeouts.md)
- [Lightweight HTTP Upload Storage](lightweight-http-upload-storage.md)

## Reference Policy

- Prefer concise summaries over large copied documents.
- Include source URLs and access dates for external material.
- Capture only context that materially changes implementation or process.
- Update or remove stale references when they no longer guide the project.
- For actively developed library manuals, keep a repository-local reference card
  with canonical URLs, access date, observed version, update policy, and the
  specific API areas that agents should inspect before implementation.
- Pin exact behavior in Camelio specs or design docs when relying on it. Treat
  external documentation links as live references, not permanent requirements.

## Reference Template

```markdown
# Title

## Source

- URL:
- Accessed:

## Summary

What matters for this repository?

## Implications

How should agents or maintainers apply this reference?
```
