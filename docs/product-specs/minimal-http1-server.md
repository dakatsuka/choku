# Minimal HTTP/1.1 Server Milestone

## Status

Draft

## Problem

Camelio needs a deliberately small first implementation target so the core
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
- Chunked request or response bodies.
- Trailers.
- Connection upgrade or WebSocket.
- Compression.
- Static file serving.

## Requirements

- The server accepts request lines of the form
  `METHOD SP origin-form SP HTTP/1.1`.
- The server parses headers using the shared `Headers.t` contract.
- The server supports request bodies only when `Content-Length` is present and
  valid.
- Request bodies are buffered and replayable as `Body.t`.
- The default maximum request body size is `1_048_576` bytes.
- Users can override the maximum request body size with
  `Server.create ?max_request_body_size`.
- Requests whose declared or decoded body exceeds the maximum size do not invoke
  the handler. When possible, the server responds with `413 Payload Too Large`,
  `connection: close`, and then closes the connection.
- The server rejects unsupported request-target forms before handler invocation.
- The server rejects unsupported transfer encodings before handler invocation.
- Responses are serialized with a status line, headers, and buffered body.
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
| Invalid `Content-Length` | No | `400 Bad Request` | Close |
| Body larger than `max_request_body_size` | No | `413 Payload Too Large` | Close |
| Unsupported `Transfer-Encoding` | No | `400 Bad Request` | Close |
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
  match Camelio.Request.(meth request, path request) with
  | Camelio.Method.GET, "/" -> Camelio.Response.text "hello\n"
  | _ -> Camelio.Response.text ~status:Camelio.Status.not_found "not found\n"
```

Expected manual check:

```sh
curl -i http://127.0.0.1:8080/
```

## Open Questions

- Should a later milestone use more specific status codes for unsupported
  transfer encodings or HTTP versions?
