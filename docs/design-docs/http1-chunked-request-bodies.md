# HTTP/1.1 Chunked Request Bodies

## Status

Accepted

## Context

Choku currently supports request bodies framed by `Content-Length` and rejects
all `Transfer-Encoding` request headers before invoking handlers. This keeps
the minimal server small, but ordinary HTTP/1.1 clients can send request bodies
with `Transfer-Encoding: chunked`, especially when the body length is not known
up front.

The server already has two body delivery modes:

- `Buffered`, which reads and stores the full request body before invoking the
  handler;
- `Streaming`, which invokes the handler with a single-consumption Eio source.

Chunked support must fit both modes without adding keep-alive, response
chunking, or trailer APIs.

## Goals

- Accept HTTP/1.1 request bodies with `Transfer-Encoding: chunked`.
- Decode chunked bodies before exposing them through `Body.t`.
- Enforce `max_request_body_size` against decoded body bytes.
- Bound chunk framing metadata that is not counted in decoded body bytes.
- Preserve existing buffered and streaming body modes.
- Preserve current request-smuggling protections by rejecting
  `Transfer-Encoding` plus `Content-Length`.
- Read the final chunk and trailer terminator before considering a chunked body
  complete.

## Non-Goals

- Chunked response bodies.
- Keep-alive or request pipelining.
- Trailer exposure through `Request.t`.
- Transfer codings other than chunked.
- Chunk extension interpretation beyond syntax tolerance.
- Per-route body-size limits or body read timeouts.

## Proposed Design

Introduce an internal request body framing decision after request-head parsing:

```ocaml
type request_body_framing =
  | Fixed of int
  | Chunked
```

`Content-Length` keeps the current fixed-length behavior. A request with
`Transfer-Encoding: chunked` and no `Content-Length` uses chunked framing.
All `Transfer-Encoding` field values are parsed as HTTP list values with
optional whitespace trimmed and transfer-coding names compared
case-insensitively. Choku accepts only a complete list of exactly one coding:
`chunked`. Multiple `Transfer-Encoding` fields, comma lists such as
`gzip, chunked`, non-final `chunked`, transfer-coding parameters, empty list
members, or any request with both `Transfer-Encoding` and `Content-Length`
return `400 Bad Request` before handler invocation where possible.

For buffered mode, the server decodes all chunks into a replayable `Body.t`
before invoking the handler. If decoded bytes exceed `max_request_body_size`,
the handler is not invoked and the server responds with `413 Payload Too Large`.

Chunk framing metadata is also bounded. The server counts chunk-size lines,
chunk extensions, and trailer-section bytes against a per-request chunk metadata
budget equal to `max_request_head_size`. Exceeding that budget is a malformed
request and maps to `400 Bad Request` before handler invocation in buffered mode
or `Body.Malformed_body_read` during streaming consumption.

Chunk-size parsing must be overflow-safe. Invalid hexadecimal sizes are
malformed. A syntactically valid chunk size larger than the remaining decoded
body budget is treated as body-size overflow without reading the chunk data.

For streaming mode, the server invokes the handler with a source that yields
decoded chunk data. The source owns chunk framing state and reads through the
zero-sized final chunk and trailer terminator before reporting end-of-file. If
decoded bytes exceed `max_request_body_size`, body consumers observe
`Body.Body_too_large_read`; malformed chunk syntax, invalid trailers, incomplete
chunk data, or exceeded chunk metadata budget raise `Body.Malformed_body_read`.
`Body.to_string_limited` converts those exceptions to `Error Body_too_large` and
`Error Malformed_body` respectively.

Because chunked length is not known before decoding, streaming chunked requests
cannot always be rejected before handler invocation. This is the same tradeoff
as any streaming body whose total size is learned only while consuming it. The
connection remains close-oriented, so unconsumed chunked body bytes are not
drained for reuse.

`Body.t` should support streaming bodies with unknown total length:

```ocaml
module Body.Internal : sig
  val streaming :
    ?content_length:int -> Eio.Flow.source_ty Eio.Resource.t -> Body.t
end
```

Known fixed-length streaming keeps the existing behavior. Unknown-length
streaming reads until the source reports end-of-file, enforcing only the limit
passed to `Body.to_string_limited` and protocol limits implemented by the
source.

## Contracts

- `Transfer-Encoding: chunked` requests expose decoded content bytes only.
- `Content-Length` is ignored only by rejecting the request when
  `Transfer-Encoding` is also present; Choku does not normalize mixed framing.
- `Body.to_string_limited` returns `Error Body_too_large` when a streaming
  source reports decoded body-size overflow.
- `Body.to_string_limited` returns `Error Malformed_body` when a streaming
  source reports malformed chunked framing.
- Uncaught `Body.Body_too_large_read` from a handler maps to `413 Payload Too
  Large` before response writing.
- Uncaught `Body.Malformed_body_read` from a handler maps to `400 Bad Request`
  before response writing.
- Malformed chunk syntax maps to `400 Bad Request` in buffered mode and to the
  streaming body error path in streaming mode.
- Buffered chunked over-limit requests map to `413 Payload Too Large` before
  handler invocation.
- Streaming chunked malformed or over-limit requests may invoke the handler and
  surface the failure while the body is consumed.

## Alternatives Considered

- Support chunked only in buffered mode: rejected because unknown-size uploads
  are one of the main reasons clients use chunked framing.
- Accept `Transfer-Encoding` plus `Content-Length` and prefer chunked: rejected
  for the initial implementation because rejecting ambiguous framing preserves
  the existing request-smuggling posture.
- Expose trailers immediately: rejected because it would change the public
  request model and needs a separate product decision.

## Third-Party Review

Context-free review found that the initial design needed explicit limits for
chunk metadata, explicit streaming malformed-body errors, overflow-safe
chunk-size parsing, a split product error policy for streaming over-limit
requests, and precise `Transfer-Encoding` list normalization rules. The design
was updated to add those contracts before implementation.

## Validation

- Parser tests for accepted chunked request strings, malformed chunk syntax,
  oversized chunk metadata, chunk-size overflow, unsupported transfer codings,
  duplicate/list `Transfer-Encoding`, case/OWS handling, and mixed
  `Transfer-Encoding`/`Content-Length`.
- Server network tests for buffered chunked decoding, buffered over-limit 413,
  streaming chunked decoding, and streaming over-limit consumer errors.
- Existing tests for fixed `Content-Length` bodies, request smuggling rejection,
  and unsupported transfer encodings must be updated to the new contract.

## Open Questions

None.
