# 0002: Introduce streaming bodies with buffered compatibility

## Status

Proposed

## Date

2026-05-23

## Context

Camelio's current `Body.t` is a replayable buffered string. That keeps the first
server, router, URL-encoded form parser, and buffered multipart parser simple,
but it requires full request buffering before handlers run. Large file uploads
need an Eio-native streaming path with backpressure and request-scoped resource
ownership.

## Decision

Camelio will evolve `Body.t` toward a representation that supports both
buffered and streaming bodies. Buffered construction remains available for
tests, small requests, and responses. Streaming request bodies will be consumed
through Eio direct-style sources scoped to the handler invocation.

`Body.to_string` remains available for buffered compatibility. New code that may
later consume streaming bodies should prefer a bounded read helper such as
`Body.to_string_limited`.

## Alternatives Considered

- Replace `Body.t` with only an Eio source: rejected because it makes small
  handlers and tests harder than necessary.
- Keep all request bodies buffered: rejected because large uploads would require
  unbounded or overly conservative memory limits.
- Add automatic tempfile-backed request bodies: rejected for now because cleanup,
  permissions, and storage policy need a separate design.
- Introduce callback-based streaming: rejected because Camelio should remain
  direct-style and Eio-native.

## Consequences

- Existing buffered workflows can remain ergonomic.
- Streaming request consumption can use Eio backpressure.
- Multipart streaming can build on the same body-source model.
- Code that needs to read a body into memory has an explicit bounded path,
  reducing the pressure to make `Body.to_string` handle every future use case.
- HTTP/1.1 connection reuse may remain limited when handlers do not consume
  streaming request bodies.

## References

- [Streaming Request Bodies](../streaming-request-bodies.md)
- [Multipart Form-Data Support](../multipart-form-data.md)
- [Minimal Server, Handler, and Middleware API](../minimal-server-handler-middleware-api.md)
