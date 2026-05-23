# Multipart Form-Data Support

## Status

Draft

## Problem

Camelio should support browser file upload forms without forcing multipart parts
into the URL-encoded `Form` abstraction. The first implementation can parse
buffered request bodies, but the API should leave room for future Eio streaming
parts.

## Goals

- Provide an optional `Camelio.Multipart` module for `multipart/form-data`.
- Parse buffered multipart request bodies into ordered parts.
- Preserve part headers, field names, filenames, content types, and body bytes.
- Return structured parse errors instead of raising for malformed user input.
- Keep URL-encoded forms and multipart forms as separate modules.
- Leave future streaming upload support as an explicit later phase.

## Non-Goals

- Streaming multipart parsing in the first phase.
- Writing uploaded files automatically.
- Nested multipart parsing.
- RFC 5987 extended parameter decoding such as `filename*`.
- Header continuation lines.
- MIME transfer encoding.
- Character set transcoding or UTF-8 validation.

## Requirements

- `Multipart.t` is an immutable ordered collection of parts.
- `Multipart.Part.t` exposes part headers, field name, filename, content type,
  and buffered body.
- `Multipart.decode ~boundary body` parses a raw multipart body.
- `Multipart.of_request request` checks `Content-Type`, extracts `boundary`,
  and parses `Request.body`.
- `Multipart.of_request_limited ~max_size request` checks `Content-Type`,
  extracts `boundary`, reads at most `max_size` bytes from `Request.body`, and
  parses the resulting buffered multipart body.
- `Multipart.of_request_limited` supports server-created streaming request
  bodies by using `Body.to_string_limited`; it is an interim bounded adapter,
  not a true streaming multipart parser.
- `Multipart.Streaming.iter_request ?max_header_size request ~on_part` streams
  canonical CRLF multipart parts without buffering whole part bodies.
- Streaming part sources are valid only during the `on_part` callback. If the
  callback returns before fully consuming the part source, the iterator drains
  the remainder of that part before reading the next part.
- Callback exceptions propagate unchanged. The iterator does not drain the
  current part when the callback raises.
- `max_header_size` applies per part header block, defaults to `8192` bytes,
  rejects negative values with `Invalid_argument`, and returns `Malformed_body`
  when exceeded.
- `Content-Type` matching is case-insensitive for the media type and supports
  parameters.
- Missing `Content-Type` returns `Missing_content_type`.
- Unsupported `Content-Type` returns `Unsupported_content_type value`.
- Missing or empty boundary returns `Missing_boundary`.
- Malformed multipart syntax returns `Malformed_body`.
- Repeated field names are preserved in insertion order.
- Part field names and filenames are parsed from `Content-Disposition:
  form-data`.
- Unknown part headers are preserved.

## Public Contracts

Initial contracts:

```ocaml
module Multipart : sig
  type t

  type error =
    | Missing_content_type
    | Unsupported_content_type of string
    | Missing_boundary
    | Malformed_body
    | Body_too_large
    | Unexpected_end_of_body

  module Part : sig
    type t

    val headers : t -> Headers.t
    val name : t -> string option
    val filename : t -> string option
    val content_type : t -> string option
    val body : t -> Body.t
    val copy_to_sink : t -> _ Eio.Flow.sink -> unit
    val save_to_path :
      ?append:bool -> create:Eio.Fs.create -> _ Eio.Path.t -> t -> unit
  end

  module Streaming : sig
    type part

    val headers : part -> Headers.t
    val name : part -> string option
    val filename : part -> string option
    val content_type : part -> string option

    val iter_request :
      ?max_header_size:int ->
      Request.t ->
      on_part:(part -> Eio.Flow.source_ty Eio.Resource.t -> unit) ->
      (unit, error) result
  end

  val decode : boundary:string -> string -> (t, error) result
  val of_request : Request.t -> (t, error) result
  val of_request_limited : max_size:int -> Request.t -> (t, error) result
  val parts : t -> Part.t list
  val get : string -> t -> Part.t option
  val get_all : string -> t -> Part.t list
  val pp_error : Format.formatter -> error -> unit
end
```

Public `.mli` files must document these contracts with block comments.

## Examples

```ocaml
match Camelio.Multipart.of_request request with
| Error error ->
    Camelio.Response.text ~status:Camelio.Status.bad_request
      (Format.asprintf "%a\n" Camelio.Multipart.pp_error error)
| Ok multipart -> (
    match Camelio.Multipart.get "avatar" multipart with
    | None -> Camelio.Response.text ~status:Camelio.Status.bad_request "missing avatar\n"
    | Some part ->
        let filename = Camelio.Multipart.Part.filename part in
        let bytes = Camelio.Body.to_string (Camelio.Multipart.Part.body part) in
        (* Phase 1 keeps part bodies buffered. *)
        Camelio.Response.text
          (Printf.sprintf "filename=%s bytes=%d\n"
             (Option.value ~default:"" filename)
             (String.length bytes)))
```

## Phases

- Phase 1: buffered multipart parser over existing `Body.t`.
- Phase 2: part-level consumer helpers for copying file parts to Eio sinks and
  paths.
- Phase 3: streaming `Body.t` or protocol-level multipart parsing with Eio
  backpressure and resource scopes.

## Open Questions

- Which streaming body abstraction should Phase 3 expose?
- Should Phase 2 add filename sanitization helpers or leave storage policy
  entirely to applications?
