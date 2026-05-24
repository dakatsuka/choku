# Minimal HTTP/1.1 Server Milestone

## Status

Accepted

## Problem

Choku needs a small but practical HTTP/1.1 application-server baseline before
HTTP Client, TLS, HTTP/2, HTTP/3, or edge-server features are designed. The
baseline should be sufficient for applications running behind nginx, AWS load
balancers, or a similar reverse proxy, while keeping protocol behavior explicit
and testable.

## Goals

- Accept HTTP/1.1 requests over plain TCP using Eio.
- Invoke `Handler.t` and serialize `Response.t`.
- Support middleware, router-backed servers, and handler-backed servers.
- Support bounded buffered and streaming request bodies.
- Support buffered and streaming responses.
- Support conservative HTTP/1.1 persistent connections.
- Keep socket-free unit tests for shared HTTP values and handler logic.
- Keep shared HTTP values suitable for future HTTP Client design where their
  contracts fit.

## Non-Goals

- HTTP Client support.
- TLS or HTTPS transport.
- HTTP/2 or HTTP/3.
- Concurrent request processing on one connection.
- Response trailers.
- Automatic compression.
- Static file serving, range requests, sendfile, or zero-copy transfer.
- Connection upgrade, WebSocket, CONNECT, or proxy behavior.
- Automatic `Date` header generation.
- Automatic `Server` header generation.
- `Expect: 100-continue`.
- Absolute-form server request targets.

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
- Requests that include both `Transfer-Encoding` and `Content-Length` are
  rejected before handler invocation.
- Unsupported transfer encodings are rejected before handler invocation.
- Chunked request bodies are decoded before reaching buffered handlers. Chunk
  extensions are tolerated but ignored, and trailers are read to complete the
  body but are not exposed through `Request.t`.
- Chunk-size lines, chunk extensions, and trailer-section bytes are bounded by a
  per-request chunk metadata budget equal to `max_request_head_size`.
- Request bodies are buffered and replayable as `Body.t` by default.
- `Server.create ?request_body_mode:Streaming` invokes the handler with a
  single-consumption request body source.
- `Server.create_router` can select request body mode from route metadata before
  request body delivery.
- `Server.create_with_request_body_selector` can select request body mode from a
  parsed `Request_head.t` before request body delivery.
- The default maximum request body size is `1_048_576` bytes.
- Users can override the maximum request body size with
  `Server.create ?max_request_body_size`.
- Users can override request head size and request head timeout with
  `?max_request_head_size` and `?request_head_timeout`.
- Requests whose declared or decoded body exceeds the maximum size do not invoke
  the handler when the overflow is discovered before handler invocation. When
  possible, the server responds with `413 Payload Too Large`,
  `connection: close`, and then closes the connection.
- Fixed-length streaming request bodies are capped to the declared
  `Content-Length`. Chunked streaming request bodies are decoded by the protocol
  source and capped by the configured decoded body limit.
- If a streaming body ends before the declared `Content-Length`,
  `Body.to_string_limited` returns `Unexpected_end_of_body`; lower-level source
  consumers observe `Body.Unexpected_end_of_body_read`.
- Responses may be buffered or streaming.
- Buffered responses use `Content-Length`.
- Streaming responses with `~content_length` use `Content-Length` and must write
  exactly the declared number of bytes.
- Streaming responses without `~content_length` use
  `Transfer-Encoding: chunked`.
- Choku owns `Content-Length`, `Transfer-Encoding`, and `Connection` during
  response serialization. Application-provided values for those headers are
  replaced.
- Explicit `HEAD` requests preserve the response framing headers that a matching
  `GET` response would have used, but do not write response body bytes or invoke
  streaming response writers.
- Informational `1xx`, `204 No Content`, and `304 Not Modified` responses do not
  write body bytes, do not include body framing headers, and do not invoke
  streaming response writers.
- The default response behavior is HTTP/1.1 persistent connection reuse, as
  specified by [HTTP/1.1 Persistent Connections](http1-persistent-connections.md).
- Successful streaming responses may keep the connection alive.
- Streaming request bodies close the connection after the response.
- Response streaming failures after the response head is written close the
  connection.
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
| Request body selector raises non-cancellation exception | No | `500 Internal Server Error` when possible | Close |
| Handler raises non-cancellation exception before response writing | Yes | `500 Internal Server Error` | Close |
| Response stream raises after response head is written | Yes | No synthesized replacement response | Close |
| Known-length response stream writes too few or too many bytes | Yes | No synthesized replacement response | Close |
| Handler or selector raises `Eio.Cancel.Cancelled _` | Maybe | No synthesized response | Preserve cancellation |

## Current Limitations

- The server does not add automatic `Date` headers.
- The server does not add automatic `Server` headers.
- The server does not implement `Expect: 100-continue`.
- The server does not accept absolute-form request targets.
- The server does not expose request trailers or response trailers.
- The server does not provide graceful connection-drain APIs beyond Eio switch
  cancellation.
- Protocol-level observability hooks are not yet provided; applications can use
  middleware for application-level logging and metrics.

## Public Contracts

This milestone is implemented by the public contracts from:

- [Minimal Server API](minimal-server-api.md)
- [HTTP/1.1 Persistent Connections](http1-persistent-connections.md)
- [Generic Pre-Body Selector](generic-pre-body-selector.md)
- [Router HEAD And 405 Semantics](router-head-and-405.md)
- [Response Streaming](response-streaming.md)
- [Minimal Server, Handler, and Middleware API](../design-docs/minimal-server-handler-middleware-api.md)

The current `Request.t` target contract is server/application oriented. HTTP
Client design must decide whether outbound requests reuse `Request.t` or use a
separate client request type.

## Examples

Minimal handler:

```ocaml
let handler request =
  match Choku.Request.(meth request, path request) with
  | Choku.Method.GET, "/" -> Choku.Response.text "hello\n"
  | _ -> Choku.Response.text ~status:Choku.Status.not_found "not found\n"
```

Streaming response:

```ocaml
let report _request =
  Choku.Response.stream (fun sink ->
      List.iter (fun line -> Eio.Flow.copy_string line sink) report_lines)
```

Expected manual check:

```sh
curl -i http://127.0.0.1:8080/
```

## Open Questions

None.
