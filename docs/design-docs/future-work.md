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

### Response Streaming Follow-Up APIs

Response streaming now supports callback-scoped stream writers. Future
follow-ups may add convenience APIs for files, server-sent events, trailers, and
HTTP/2 or HTTP/3 flow control.

### Input Mapping And Validation Strategy

`Router.Params`, `Query`, and `Form` expose small string-based accessors.
Choku should not grow a general-purpose validator until requirements are clear,
but applications still need a smooth path from HTTP inputs to application-owned
types.

Future design work should focus on interoperability rather than a built-in
validation framework:

- keep low-level input collections simple and predictable;
- make it easy to lift missing fields and parse errors into application-defined
  error types;
- document examples that compose with third-party validators or typed
  converters;
- consider tiny helper contracts only when they remove integration friction
  without owning validation policy.

### HTTP Client Convenience APIs

The minimal client exposes `Client.Request.make` and `Client.request`. Future
client work may add convenience functions such as `Client.get` or `Client.post`
if they remain thin wrappers over the existing request contract.

This is likely smaller than a validation layer because the core client behavior
already exists. The design should decide whether convenience helpers improve
common use without hiding method, header, body, timeout, redirect, or TLS
semantics that applications need to control.

### Router Follow-Up Features

Future router work may include:

- route introspection for documentation or diagnostics;
- typed path converters or regex-like segments;
- trailing-slash and repeated-slash policy.

These should be handled as separate router milestones because each changes
public routing semantics.

### Reverse Proxy Library Capabilities

The current reverse proxy examples are intentionally buffered examples. A
production-oriented reverse proxy layer should remain deferred until Choku is
ready to design streaming proxying, upstream connection management,
hop-by-hop-header policy, retry behavior, load balancing, and observability as
one coherent subsystem.

## Current Next Priorities

1. Design and implement thin HTTP Client convenience APIs if they keep the
   existing explicit client contract intact.
2. Design an input mapping and validation interoperability strategy that helps
   users map Choku inputs into their own application types without making Choku
   own validation policy.
3. Add response streaming follow-up APIs such as file responses or server-sent
   events when a concrete use case needs them.
4. Defer production reverse proxy features until streaming proxy behavior and
   upstream policy are ready for a dedicated milestone.
