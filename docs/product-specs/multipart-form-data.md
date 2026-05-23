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
- Support streaming upload handling through an explicit streaming API.

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
- `Multipart.Filename.sanitize ?max_length filename` returns a
  filesystem-friendly filename candidate for applications that need to retain a
  client supplied display name. It replaces path separators and other unsafe
  characters with `-`, collapses repeated separators and periods, removes
  leading periods and separators, and falls back to `upload`, truncated to
  `max_length`, when no safe characters remain.
- `Multipart.Tempfile.save_source` and `Multipart.Tempfile.save_part` write
  upload bytes to generated temporary files under an application-provided Eio
  directory capability. Storage names are generated from an explicit random
  source and never from client supplied filenames.
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

  module Filename : sig
    val sanitize : ?max_length:int -> string -> string
  end

  module Tempfile : sig
    type 'a t constraint 'a = [> Eio.Fs.dir_ty ]

    val path : 'a t -> 'a Eio.Path.t
    val original_filename : 'a t -> string option
    val display_filename : 'a t -> string option
    val size : 'a t -> int

    val save_source :
      dir:'a Eio.Path.t ->
      random:Eio.Flow.source_ty Eio.Resource.t ->
      ?original_filename:string ->
      Eio.Flow.source_ty Eio.Resource.t ->
      'a t

    val save_part :
      dir:'a Eio.Path.t ->
      random:Eio.Flow.source_ty Eio.Resource.t ->
      Part.t ->
      'a t
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

Streaming upload example:

```ocaml
let handler ~upload_dir ~random request =
  match Camelio.Multipart.Streaming.iter_request request ~on_part:(fun part source ->
    match Camelio.Multipart.Streaming.filename part with
    | None -> Eio.Flow.copy source (Eio.Flow.buffer_sink (Buffer.create 0))
    | Some filename ->
        let saved =
          Camelio.Multipart.Tempfile.save_source ~dir:upload_dir ~random
            ~original_filename:filename source
        in
        store_upload_metadata
          (Camelio.Multipart.Tempfile.display_filename saved)
          (Camelio.Multipart.Tempfile.path saved)
          (Camelio.Multipart.Tempfile.size saved))
  with
  | Ok () -> Camelio.Response.text "uploaded\n"
  | Error error ->
      Camelio.Response.text ~status:Camelio.Status.bad_request
        (Format.asprintf "%a\n" Camelio.Multipart.pp_error error)
```

## Phases

- Phase 1: buffered multipart parser over existing `Body.t`.
- Phase 2: part-level consumer helpers for copying file parts to Eio sinks and
  paths.
- Phase 3: opt-in server streaming request bodies and
  `Multipart.Streaming.iter_request` for callback-scoped streaming part sources.
- Phase 4: filename sanitization and generated tempfile helpers.

## Open Questions

- Should future helpers add a higher-level upload storage policy, or leave that
  entirely to applications?
- Should multipart streaming add route-level body mode integration once server
  routing policy exists?
