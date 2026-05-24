# Minimal HTTP/1.1 Server Milestone

## Status

Draft

## Problem

Choku needs a deliberately small first implementation target so the core
server, handler, middleware, and shared HTTP value types can be validated before
streaming, routing, TLS, client support, or additional HTTP protocol versions are
designed.

## Goals

- Accept basic HTTP/1.1 requests over plain TCP.
- Invoke a `Handler.t` and serialize its `Response.t`.
- Support middleware through `Server.create`.
- Support socket-free unit tests for HTTP values and middleware.
- Support a small integration test or example that can be exercised with `curl`.

## Non-Goals

- HTTP client support.
- TLS or HTTPS.
- HTTP/2 or HTTP/3.
- Router DSL.
- Keep-alive and request pipelining.
- Chunked response bodies.
- Trailers.
- Connection upgrade or WebSocket.
- Compression.
- Static file serving.

## Requirements

- The server accepts request lines of the form
  `METHOD SP origin-form SP HTTP/1.1`.
- The accepted origin-form target is a slash-prefixed path with an optional query
  string. It must not contain a fragment marker, control bytes, spaces, or DEL.
- HTTP/1.1 requests must contain exactly one non-empty `Host` header. Missing,
  empty, or duplicate `Host` headers are rejected before handler invocation.
- The server parses headers using the shared `Headers.t` contract.
- The server supports request bodies framed by a valid `Content-Length` or by
  `Transfer-Encoding: chunked`.
- Request bodies are buffered and replayable as `Body.t` by default.
- When `Server.create ?request_body_mode:Streaming` is used, request bodies are
  single-consumption and backed by an Eio source scoped to the handler
  invocation.
- The default maximum request body size is `1_048_576` bytes.
- Users can override the maximum request body size with
  `Server.create ?max_request_body_size`.
- Requests whose declared or decoded body exceeds the maximum size do not invoke
  the handler. When possible, the server responds with `413 Payload Too Large`,
  `connection: close`, and then closes the connection.
- Fixed-length streaming request bodies are capped to the declared
  `Content-Length`. Chunked streaming request bodies are decoded by the protocol
  source and capped by the configured decoded body limit.
- If a streaming body ends before the declared `Content-Length`,
  `Body.to_string_limited` returns `Unexpected_end_of_body`; lower-level source
  consumers observe `Body.Unexpected_end_of_body_read` from the source.
- The server rejects unsupported request-target forms before handler invocation.
- The server accepts `Transfer-Encoding: chunked` request bodies, rejects
  unsupported transfer encodings before handler invocation, and rejects requests
  that include both `Transfer-Encoding` and `Content-Length`.
- Chunked request bodies are decoded before reaching handlers. Chunk extensions
  are tolerated but ignored, and trailers are read to complete the body but are
  not exposed through `Request.t`.
- Chunk-size lines, chunk extensions, and trailer-section bytes are bounded by a
  per-request chunk metadata budget equal to `max_request_head_size`.
- Responses are serialized with a status line, headers, and buffered body.
  Explicit `HEAD` requests preserve the serialized `Content-Length` that a `GET`
  response would have used, but do not write response body bytes.
- The default response behavior is `Connection: close`.
- Uncaught non-cancellation handler exceptions before response writing produce
  the default `500 Internal Server Error` response already defined by the
  minimal server API.
- `Eio.Cancel.Cancelled _` remains cancellation and is not converted into HTTP
  500.

## Error Policy

| Error class | Handler invoked | Response | Connection |
| --- | --- | --- | --- |
| Invalid request line | No | `400 Bad Request` | Close |
| Unsupported HTTP version | No | `400 Bad Request` | Close |
| Unsupported request-target form | No | `400 Bad Request` | Close |
| Malformed header field | No | `400 Bad Request` | Close |
| Missing, empty, or duplicate `Host` | No | `400 Bad Request` | Close |
| Invalid `Content-Length` | No | `400 Bad Request` | Close |
| Malformed chunked body | No, unless already in streaming body consumption | `400 Bad Request` or `Body.Malformed_body`/`Body.Malformed_body_read` | Close |
| Declared, buffered, or pre-handler body larger than `max_request_body_size` | No | `413 Payload Too Large` | Close |
| Streaming chunked body larger than `max_request_body_size` | Yes, if discovered during consumption | `Body.Body_too_large`/`Body.Body_too_large_read`; uncaught handler exception maps to `413 Payload Too Large` | Close |
| Unsupported or ambiguous `Transfer-Encoding` | No | `400 Bad Request` | Close |
| Handler raises non-cancellation exception before response writing | Yes | `500 Internal Server Error` | Close |
| Handler raises `Eio.Cancel.Cancelled _` | Yes | No synthesized response | Preserve cancellation |

## Public Contracts

This milestone implements the contracts from:

- [Minimal Server API](minimal-server-api.md)
- [Minimal Server, Handler, and Middleware API](../design-docs/minimal-server-handler-middleware-api.md)

No Router, Client, TLS, HTTP/2, or HTTP/3 public contracts are introduced in this
milestone.

## Examples

Expected minimal server shape:

```ocaml
let handler request =
  match Choku.Request.(meth request, path request) with
  | Choku.Method.GET, "/" -> Choku.Response.text "hello\n"
  | _ -> Choku.Response.text ~status:Choku.Status.not_found "not found\n"
```

Expected manual check:

```sh
curl -i http://127.0.0.1:8080/
```

## Open Questions

- Should a later milestone use more specific status codes for unsupported
  transfer encodings or HTTP versions?
