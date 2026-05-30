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

The interoperability boundary is captured in
[Input Mapping Interoperability](input-mapping-interoperability.md). Follow-up
work should stay within that boundary:

- keep low-level input collections simple and predictable;
- make it easy to lift missing fields and parse errors into application-defined
  error types;
- document examples that compose with third-party validators or typed
  converters;
- add only tiny helper contracts, such as `Router.Params.get_all`, when they
  remove integration friction without owning validation policy.

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

1. Add response streaming follow-up APIs such as file responses or server-sent
   events when a concrete use case needs them.
2. Design an optional upload storage policy only if route-local application
   upload code keeps repeating the same safe-storage decisions.
3. Defer production reverse proxy features until streaming proxy behavior and
   upstream policy are ready for a dedicated milestone.
