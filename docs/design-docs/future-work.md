# Future Work

## Status

Accepted

## Context

This document records deferred design topics that are important enough to keep
visible, but not yet ready for an execution plan.

## Deferred Topics

### Optional Upload Storage Policy

`Multipart.Filename.sanitize` and `Multipart.Tempfile.save_*` currently provide
low-level helpers for application-owned upload storage. A higher-level upload
storage policy may eventually add route-local controls for destination
selection, limits, cleanup, accepted files, and returned metadata.

This should not become default server behavior without a separate design pass.
Lightweight HTTP ecosystems tend to keep persistence policy in application code,
route-local middleware, or optional helpers rather than core server parsing. See
[Lightweight HTTP Upload Storage](../references/lightweight-http-upload-storage.md).

### Generic Pre-Body Selector API

`Server.create_router` can select `Request_body_mode.t` before reading the body
because it has structured router metadata. A future API could expose a generic
pre-body selector for users who do not want `Router.t` but still need to choose
buffered or streaming bodies from request-head metadata.

This requires deciding what stable request-head type Camelio should expose
publicly.

### Router Follow-Up Features

Future router work may include:

- automatic `HEAD` handling for `GET` routes;
- `405 Method Not Allowed` responses;
- route introspection for documentation or diagnostics;
- typed path converters or regex-like segments;
- trailing-slash and repeated-slash policy.

These should be handled as separate router milestones because each changes
public routing semantics.

## Current Next Priority

The next planned security-oriented work is request-line/header-size limits and
slowloris mitigation for HTTP/1.1 request reading.
