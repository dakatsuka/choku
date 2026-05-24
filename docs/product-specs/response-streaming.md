# Response Streaming

## Status

Accepted

## Problem

Choku currently serializes every `Response.t` by converting its body to a
string, computing `Content-Length`, and writing one buffered response. This is
simple and works for small responses, but it prevents handlers from producing
large downloads, generated output, or long-running response streams without
buffering all bytes in memory first.

Choku should add response streaming in a way that fits the existing
direct-style Eio handler model and keeps ordinary buffered responses unchanged.

## Goals

- Let handlers return streaming response bodies without buffering all bytes in
  memory.
- Preserve the existing `Handler.t = Request.t -> Response.t` contract.
- Preserve existing buffered `Response.text` and `Response.make` behavior.
- Use HTTP/1.1 chunked transfer coding for streaming responses with unknown
  length.
- Allow fixed-length streaming responses when the application knows the length.
- Keep response streaming compatible with HTTP/1.1 keep-alive when the stream
  completes successfully.
- Keep HEAD responses bodyless while preserving the headers that the matching
  GET response would use.
- Keep streaming source lifetime safe for ordinary handlers.

## Non-Goals

- HTTP/2 or HTTP/3 flow control.
- Response trailers.
- Compression.
- Range requests.
- Sendfile or zero-copy file transfer.
- Server-Sent Events convenience APIs.
- WebSocket, CONNECT, or protocol upgrades.
- Background response fibers that outlive the request handler.
- Automatic retry or resume of partially written responses.

## Requirements

- Buffered response APIs remain source-compatible.
- A new public API creates streaming response bodies from a scoped writer
  callback.
- Streaming response bodies are single-consumption.
- A streaming response body is consumed by the server after the handler returns.
- The callback is invoked by the server while writing the response and receives
  a sink that is valid only for the callback duration.
- Streaming responses with a known non-negative content length are serialized
  with `Content-Length`.
- Streaming responses without a known content length are serialized with
  `Transfer-Encoding: chunked`.
- Choku owns `Content-Length`, `Transfer-Encoding`, and `Connection` during
  HTTP/1.1 serialization. Application-provided values for those headers are
  ignored and replaced.
- HEAD responses do not write body bytes. Their framing headers reflect the
  response that would have been sent for GET:
  - known-length streaming HEAD responses include `Content-Length`;
  - unknown-length streaming HEAD responses may include `Transfer-Encoding:
    chunked` but write no chunks.
- Responses with body-forbidden status codes do not write body bytes and do not
  include `Content-Length` or `Transfer-Encoding`. This includes informational
  `1xx`, `204 No Content`, and `304 Not Modified` responses.
- If a streaming response source raises while bytes are being written, Choku
  cannot synthesize a replacement HTTP response because the response head may
  already be on the wire. It closes the connection.
- HTTP/1.1 keep-alive remains possible after successful buffered responses and
  successful streaming responses whose body framing completes.
- The connection closes after streaming write failure, handler failure, request
  streaming bodies, or any other existing close condition.
- Middleware can inspect and replace `Response.t`, but consuming a streaming
  response body inside middleware makes it unavailable to the server.

## Public Contracts

Expected API shape:

```ocaml
module Response : sig
  val stream :
    ?status:Status.t ->
    ?headers:Headers.t ->
    ?content_length:int ->
    (Eio.Flow.sink_ty Eio.Resource.t -> unit) ->
    t
end
```

The callback must write at most `content_length` bytes when a content length is
provided. Choku does not read beyond a declared fixed length to detect overflow;
overwriting too many bytes is a protocol error by the application and closes the
connection if detected by the sink wrapper.

## Examples

Known-length response:

```ocaml
let download _request =
  Choku.Response.stream
    ~headers:(Choku.Headers.set "content-type" "application/octet-stream"
                Choku.Headers.empty)
    ~content_length:14
    (fun sink -> Eio.Flow.copy_string "large bytes..." sink)
```

Unknown-length generated response:

```ocaml
let stream_report _request =
  Choku.Response.stream
    ~headers:(Choku.Headers.set "content-type" "text/plain" Choku.Headers.empty)
    (fun sink ->
      List.iter (fun line -> Eio.Flow.copy_string line sink) (report_lines ()))
```

## Open Questions

- Should a later milestone also expose a lower-level source-backed constructor
  for applications that already have a clearly scoped source lifetime?
