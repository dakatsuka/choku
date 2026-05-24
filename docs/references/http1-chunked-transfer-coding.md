# HTTP/1.1 Chunked Transfer Coding

## Source

- RFC 9112: HTTP/1.1, sections on message body length, Transfer-Encoding,
  Content-Length, and chunked transfer coding:
  https://www.rfc-editor.org/rfc/rfc9112.html
- Accessed: 2026-05-24

## Summary

RFC 9112 defines chunked transfer coding as a way to send HTTP/1.1 content as a
sequence of chunks, each with a hexadecimal size, followed by a zero-sized final
chunk, optional trailer fields, and a final empty line.

For requests, a server can determine message length from Transfer-Encoding when
chunked is the final transfer coding. If Transfer-Encoding is present and
chunked is not final, the request body length is unreliable and the server must
respond with 400 and close the connection.

Transfer-Encoding overrides Content-Length for message framing, but the
combination is a request-smuggling risk. Choku's initial chunked support should
reject requests that include both fields instead of attempting to normalize
them.

Chunk extensions are part of the wire format but do not affect decoded content.
The initial server can ignore extension parameters after validating that the
chunk-size prefix is valid hexadecimal.

Trailer fields are part of the chunked terminator. Choku should read and
validate the trailer section enough to find the end of the request body, but the
first milestone should not expose trailers through `Request.t`.

## Implications

- Support `Transfer-Encoding: chunked` for request bodies.
- Reject unsupported transfer coding values and transfer-coding lists other than
  final `chunked`.
- Reject requests that contain both `Transfer-Encoding` and `Content-Length`.
- Enforce `max_request_body_size` against decoded body bytes, not encoded wire
  bytes.
- Preserve the current close-after-response connection behavior.
