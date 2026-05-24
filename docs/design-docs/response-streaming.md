# Response Streaming

## Status

Accepted

## Context

Choku's current response path is fully buffered. `Response.t` stores a
`Body.t`; `Http1.serialize_response` calls `Body.to_string`, computes
`Content-Length`, and returns a single response string. `Server.write_response`
then copies that string to the socket.

This design keeps simple buffered responses intact while allowing handlers to
return streaming response bodies that the HTTP/1.1 server writes incrementally.

## Goals

- Preserve existing buffered response behavior.
- Add a small public streaming response API with scoped ownership.
- Keep `Handler.t = Request.t -> Response.t`.
- Use direct-style Eio sources and sinks.
- Implement HTTP/1.1 chunked transfer coding only for responses that need it.
- Keep connection reuse conservative and correct.

## Non-Goals

- Implementing the feature in this design pass.
- HTTP/2 or HTTP/3 flow-control design.
- Response trailers.
- Compression or content negotiation.
- Sendfile, mmap, or zero-copy transfer.
- A high-level SSE, file download, or static file API.
- A source-backed public API whose lifetime can outlive the handler by
  accident.

## Proposed Design

Extend `Body.t` so it can represent streaming response writers as well as
buffered bodies and server-created streaming request bodies:

```ocaml
type t =
  | Buffered of string
  | Source of source_stream
  | Writer of writer_stream

type source_stream = {
  source : Eio.Flow.source_ty Eio.Resource.t;
  content_length : int option;
  mutable state : consumption_state;
}

type writer_stream = {
  write : Eio.Flow.sink_ty Eio.Resource.t -> unit;
  content_length : int option;
  mutable state : consumption_state;
}
```

The existing source-backed streaming representation remains useful internally
for request bodies. The first public response API should be writer-callback
based so handlers do not accidentally return a source whose scope has already
closed before the server serializes the response.

The preferred public API is:

```ocaml
val Response.stream :
  ?status:Status.t ->
  ?headers:Headers.t ->
  ?content_length:int ->
  (Eio.Flow.sink_ty Eio.Resource.t -> unit) ->
  Response.t
```

`content_length` must be non-negative. Buffered bodies remain replayable.
Streaming response writers are single-consumption, enforced at runtime as
request streaming bodies are today.

An implementation should add an internal body view for serializers:

```ocaml
module Body.Internal : sig
  type view =
    | Buffered of string
    | Source of {
        content_length : int option;
        with_source : (Eio.Flow.source_ty Eio.Resource.t -> 'a) -> 'a;
      }
    | Writer of {
        content_length : int option;
        write : Eio.Flow.sink_ty Eio.Resource.t -> unit;
      }

  val view : Body.t -> view
end
```

The exact internal shape can vary, but the writer must be able to inspect
whether a body is buffered, known-length streaming, or unknown-length streaming
without consuming it.

## Response Writing

Replace the all-at-once `Http1.serialize_response` server path with a writer
that can write the response head and then stream the body:

```ocaml
val write_response :
  include_body:bool ->
  connection:string ->
  Eio.Flow.sink_ty Eio.Resource.t ->
  Response.t ->
  (unit, write_error) result
```

The existing string serializer can remain for tests and buffered helpers, but
the server should use the writer path.

For buffered bodies:

- set `Content-Length` to the buffered byte length;
- remove any application-provided `Transfer-Encoding`;
- write the head and buffered body when `include_body = true`.

For streaming bodies with `content_length = Some n`:

- set `Content-Length: n`;
- remove any application-provided `Transfer-Encoding`;
- wrap the sink so exactly `n` bytes may be written when `include_body = true`;
- if the writer writes fewer than `n` bytes, close the connection after the
  write failure;
- if the writer attempts to write more than `n` bytes, the wrapper raises and
  the connection closes.

The implementation should not try to detect overflow by reading one byte beyond
a source's declared length, because that can block indefinitely for generated
sources. The fixed-length writer contract is enforced by counting bytes written
to the wrapped sink.

For streaming bodies with `content_length = None`:

- set `Transfer-Encoding: chunked`;
- remove any application-provided `Content-Length`;
- wrap the sink so every write becomes one HTTP chunk;
- write the terminating `0\r\n\r\n` chunk on successful EOF.

Choku owns the final HTTP/1.1 framing headers. Existing application headers are
preserved except for `Content-Length`, `Transfer-Encoding`, and `Connection`,
which are controlled by the server serializer.

The implementation will likely need `Headers.remove` or an internal equivalent
so the writer can discard application-provided framing headers before setting
the server-owned framing.

## Body-Forbidden Statuses

Some HTTP responses must not carry a message body. Choku should suppress body
bytes and omit `Content-Length` and `Transfer-Encoding` for:

- informational `1xx` responses;
- `204 No Content`;
- `304 Not Modified`.

For these statuses, the streaming writer is not invoked. `HEAD` remains a
method-specific body suppression rule; unlike no-body statuses, `HEAD` preserves
the framing headers that a corresponding GET response would have used.

## HEAD Responses

For `HEAD`, the server should write the response head but no body bytes.

- Buffered body: write `Content-Length` for the buffered body length.
- Known-length streaming body: write `Content-Length` for the declared length.
- Unknown-length streaming body: write `Transfer-Encoding: chunked`, but invoke
  no writer and write no chunks.

The streaming writer should not be invoked for `HEAD`. This preserves the
current behavior where handlers can construct a response as if it were a GET
response and the server suppresses only the wire body.

## Connection Reuse

Connection reuse is allowed when response writing completes successfully and the
existing request/response connection decision allows keep-alive.

Connection reuse is forbidden when:

- handler execution failed;
- request body mode was streaming;
- request or response `Connection: close` was present;
- response streaming failed after the head or partial body was written;
- a known-length stream ended early or produced too many bytes.

If streaming fails after bytes are written, Choku cannot send an HTTP error
response. It should close the connection and let the client observe an
incomplete response body or chunked framing error.

## Cancellation And Ownership

The streaming callback is invoked by the request-serving fiber after the handler
returns. The sink passed to the callback is valid only for that callback
invocation. Applications can open files or allocate stream-local resources
inside the callback and close them when it returns.

This design deliberately avoids background response fibers in the first
milestone. The handler still returns `Response.t`; response writing happens in
the same connection fiber.

For example, this is safe because the file is scoped to the write callback:

```ocaml
Response.stream (fun sink ->
  Eio.Path.with_open_in path (fun source -> Eio.Flow.copy source sink))
```

This source-backed shape is intentionally not the first public API because the
file can close before response serialization:

```ocaml
let source =
  Eio.Path.with_open_in path (fun source -> source)
in
Response.stream_from_source source
```

A later source-backed helper may still be added for applications that can prove
the source lifetime outlives response writing.

## Contracts

- Buffered responses remain source-compatible.
- Streaming responses are single-consumption.
- Choku owns `Content-Length`, `Transfer-Encoding`, and `Connection` during
  HTTP/1.1 serialization.
- Unknown-length streaming responses use chunked transfer coding.
- Known-length streaming responses use `Content-Length`.
- Body-forbidden statuses write no body and no body framing headers.
- `HEAD` responses do not invoke streaming writers.
- Failed streaming writes close the connection.
- Successful streaming responses may keep the connection alive.

## Alternatives Considered

- Require `Content-Length` for all streaming responses: rejected because many
  generated responses do not know their final length.
- Always close the connection for unknown-length streaming responses instead of
  chunking: rejected because it prevents keep-alive and makes response framing
  less explicit.
- Add a source-backed public API first: rejected because it is easy to return a
  source whose owner has already closed before serialization begins.
- Make `Body.Internal.streaming` public directly with no `Response.stream`
  helper: rejected because response construction should stay ergonomic and
  source lifetime should be safer by default.

## Third-Party Review

Context-free review found that a raw source-backed public API was too easy to
misuse because the server consumes the response after the handler returns. The
design now prefers a callback/scoped writer API. The review also required an
internal body view for serializers, body-forbidden status handling, a single
policy for server-owned framing headers, concrete known-length overflow
semantics, and additional validation cases.

## Validation

Implementation should add tests for:

- buffered response behavior unchanged;
- known-length streaming response writes `Content-Length`;
- unknown-length streaming response writes chunked response bytes;
- body-forbidden statuses suppress body bytes and body framing headers;
- `HEAD` with buffered, known-length streaming, and unknown-length streaming
  responses;
- keep-alive after successful streaming responses;
- close after streaming writer failure before the first chunk and after partial
  chunks;
- underflow and overflow for known-length writers;
- application-provided `Content-Length` and `Transfer-Encoding` being replaced
  by server framing;
- any new `Headers.remove` behavior or internal framing-header removal helper;
- zero-length streaming bodies;
- zero-byte writer calls if the chosen Eio sink path can observe them;
- middleware that accidentally consumes a streaming response before the server
  writes it;
- `Body.to_string` continuing to reject streaming bodies.

## Open Questions

- Should a later implementation expose a source-backed helper in addition to the
  callback-based `Response.stream`?
