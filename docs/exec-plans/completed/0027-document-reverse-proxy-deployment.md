# Document Reverse Proxy Deployment

## Status

Completed

## Objective

Add a concise user-facing deployment guide for running Choku behind nginx, AWS
ALB, ELB, or similar reverse proxies and load balancers.

## Context

- [Reverse Proxy Deployment](../../product-specs/reverse-proxy-deployment.md)
- [Reverse Proxy Deployment References](../../references/reverse-proxy-deployment.md)
- [HTTP/1.1 Persistent Connections](../../product-specs/http1-persistent-connections.md)
- [HTTP Request Limits And Timeouts](../../design-docs/http-request-limits-and-timeouts.md)
- [Multipart Form-Data Support](../../product-specs/multipart-form-data.md)

## Clarifications

- This is a documentation milestone, not a server implementation change.
- Keep the guide short and implementation-aligned.
- Avoid exhaustive vendor-specific configuration manuals.
- Capture external references in repository-local docs.

## Contract First

- Add a product-facing reverse proxy deployment guide.
- Add repository-local reference notes for nginx and AWS documentation used by
  the guide.
- Link the guide from product spec and reference indexes.
- Link the guide from README.

## Steps

- [x] Explore: inspect existing keep-alive, timeout, router, upload, and README
      documentation.
- [x] Draft: add the deployment guide and local reference notes.
- [x] Design review: request context-free review of the documentation.
- [x] Revise: incorporate review feedback.
- [x] Static checks: run format and documentation-safe build/test checks.
- [x] Code review: request context-free review if substantive source-adjacent
      docs changed after the first review.

## Decisions

- Put the guide under `docs/product-specs/` because it documents user-facing
  deployment expectations.
- Put external source summaries under `docs/references/`.
- Do not add new Choku behavior in this milestone.

## Verification

Passed:

- `dune build @fmt`
- `dune runtest`
- `dune build @all`
- `dune build @check`
- `dune build @install`
- `opam lint choku.opam`

## Completion Notes

Added a reverse proxy deployment guide, linked it from README, and captured
repository-local reference notes for AWS Elastic Load Balancing and nginx.
Review feedback tightened backend idle-timeout alignment, slow upload caveats,
`X-Forwarded-*` trust guidance, and AWS load balancer scope.

## Commit

`docs: add reverse proxy deployment guide`
