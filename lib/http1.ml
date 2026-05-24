[@@@alert "-internal"]

type error =
  | Invalid_request_line
  | Unsupported_http_version
  | Unsupported_request_target
  | Malformed_header
  | Invalid_content_length
  | Body_too_large
  | Malformed_chunked_body
  | Request_head_too_large
  | Request_head_timeout
  | Unsupported_transfer_encoding

let error_to_string = function
  | Invalid_request_line -> "invalid request line"
  | Unsupported_http_version -> "unsupported HTTP version"
  | Unsupported_request_target -> "unsupported request target"
  | Malformed_header -> "malformed header"
  | Invalid_content_length -> "invalid content-length"
  | Body_too_large -> "body too large"
  | Malformed_chunked_body -> "malformed chunked body"
  | Request_head_too_large -> "request head too large"
  | Request_head_timeout -> "request head timeout"
  | Unsupported_transfer_encoding -> "unsupported transfer-encoding"

module Error = struct
  type nonrec t = error

  let equal = ( = )
  let pp fmt t = Format.pp_print_string fmt (error_to_string t)
end

type request_head = { meth : Method.t; target : string; headers : Headers.t }
type request_body_framing = Fixed of int | Chunked

let default_max_request_body_size = 1_048_576

let split_lines headers =
  headers |> String.split_on_char '\n'
  |> List.map (fun line ->
      if String.length line > 0 && Char.equal line.[String.length line - 1] '\r'
      then String.sub line 0 (String.length line - 1)
      else line)

let parse_request_line = function
  | [ meth; target; "HTTP/1.1" ] -> (
      match Method.of_string meth with
      | exception Invalid_argument _ -> Error Invalid_request_line
      | meth ->
          if not (Request_target.is_valid_origin_form target) then
            Error Unsupported_request_target
          else Ok (meth, target))
  | [ _meth; _target; version ] when String.starts_with ~prefix:"HTTP/" version
    ->
      Error Unsupported_http_version
  | _ -> Error Invalid_request_line

let parse_header line =
  match String.index_opt line ':' with
  | None -> Error Malformed_header
  | Some 0 -> Error Malformed_header
  | Some index ->
      let name = String.sub line 0 index in
      let value =
        String.sub line (index + 1) (String.length line - index - 1)
        |> String.trim
      in
      if
        (not (Headers.is_valid_name name)) || not (Headers.is_valid_value value)
      then Error Malformed_header
      else Ok (name, value)

let parse_headers lines =
  let rec loop headers = function
    | [] -> Ok headers
    | "" :: rest -> loop headers rest
    | line :: rest -> (
        match parse_header line with
        | Error error -> Error error
        | Ok (name, value) -> loop (Headers.add name value headers) rest)
  in
  loop Headers.empty lines

let validate_host headers =
  match Headers.get_all "host" headers with
  | [ host ] when not (String.equal (String.trim host) "") -> Ok ()
  | _ -> Error Malformed_header

let is_digit = function '0' .. '9' -> true | _ -> false

let parse_content_length_value value =
  if String.length value = 0 || not (String.for_all is_digit value) then None
  else try Some (int_of_string value) with Failure _ -> None

let content_length headers =
  match Headers.get_all "content-length" headers with
  | [] -> Ok 0
  | first :: rest -> (
      match parse_content_length_value (String.trim first) with
      | None -> Error Invalid_content_length
      | Some length ->
          let same =
            List.for_all
              (fun value ->
                match parse_content_length_value (String.trim value) with
                | Some other -> other = length
                | None -> false)
              rest
          in
          if same then Ok length else Error Invalid_content_length)

let split_transfer_encoding value =
  value |> String.split_on_char ',' |> List.map String.trim

let transfer_encoding headers =
  match Headers.get_all "transfer-encoding" headers with
  | [] -> Ok None
  | values ->
      let codings = List.concat_map split_transfer_encoding values in
      let valid_singleton_chunked =
        match codings with
        | [ coding ] -> String.equal (String.lowercase_ascii coding) "chunked"
        | _ -> false
      in
      if valid_singleton_chunked then Ok (Some Chunked)
      else Error Unsupported_transfer_encoding

let request_body_framing headers =
  match transfer_encoding headers with
  | Error error -> Error error
  | Ok (Some Chunked) ->
      if Headers.get_all "content-length" headers = [] then Ok Chunked
      else Error Unsupported_transfer_encoding
  | Ok (Some (Fixed _)) -> assert false
  | Ok None -> (
      match content_length headers with
      | Ok length -> Ok (Fixed length)
      | Error error -> Error error)

let parse_request_head_string raw =
  match split_lines raw with
  | [] -> Error Invalid_request_line
  | request_line :: header_lines -> (
      match parse_request_line (String.split_on_char ' ' request_line) with
      | Error error -> Error error
      | Ok (meth, target) -> (
          match parse_headers header_lines with
          | Error error -> Error error
          | Ok headers -> (
              match validate_host headers with
              | Error error -> Error error
              | Ok () -> (
                  match request_body_framing headers with
                  | Error error -> Error error
                  | Ok _ -> Ok { meth; target; headers }))))

let make_request ~meth ~target ~headers ~body =
  try Request.make ~meth ~target ~headers ~body |> Result.ok
  with Invalid_argument _ -> Error Unsupported_request_target

let parse_request_string
    ?(max_request_body_size = default_max_request_body_size) raw =
  match Http1_wire.find_header_end raw with
  | None -> Error Malformed_header
  | Some header_end -> (
      let header_block = String.sub raw 0 header_end in
      match parse_request_head_string header_block with
      | Error error -> Error error
      | Ok { meth; target; headers } -> (
          let body_start = header_end + 4 in
          let available_body = String.length raw - body_start |> max 0 in
          match request_body_framing headers with
          | Error error -> Error error
          | Ok (Fixed body_length) ->
              if body_length > max_request_body_size then Error Body_too_large
              else if available_body < body_length then
                Error Invalid_content_length
              else
                let body =
                  String.sub raw body_start body_length |> Body.string
                in
                make_request ~meth ~target ~headers ~body
          | Ok Chunked -> (
              let encoded_body = String.sub raw body_start available_body in
              match
                Http1_chunked.decode_string ~max_body_size:max_request_body_size
                  encoded_body
              with
              | Ok decoded ->
                  make_request ~meth ~target ~headers
                    ~body:(Body.string decoded)
              | Error Http1_chunked.Body_too_large -> Error Body_too_large
              | Error Http1_chunked.Malformed -> Error Malformed_chunked_body)))

type write_error = Response_body_write_failed

exception Response_body_length_mismatch

let body_forbidden_status status =
  match Status.class_ status with
  | Informational -> true
  | Successful | Redirection | Client_error | Server_error ->
      let code = Status.code status in
      code = 204 || code = 304

let response_framing_headers headers =
  headers
  |> Headers.remove "content-length"
  |> Headers.remove "transfer-encoding"
  |> Headers.remove "connection"

let response_head_string ~connection status headers =
  let headers = Headers.set "connection" connection headers in
  let status_line =
    Printf.sprintf "HTTP/1.1 %d %s\r\n" (Status.code status)
      (Status.reason status)
  in
  let header_lines =
    headers |> Headers.to_list
    |> List.map (fun (name, value) -> name ^ ": " ^ value ^ "\r\n")
    |> String.concat ""
  in
  status_line ^ header_lines ^ "\r\n"

let serialize_response ?(include_body = true) ?(connection = "close") response =
  let status = Response.status response in
  let body_forbidden = body_forbidden_status status in
  let body = Response.body response |> Body.to_string in
  let headers =
    Response.headers response |> response_framing_headers |> fun headers ->
    if body_forbidden then headers
    else
      Headers.set "content-length" (string_of_int (String.length body)) headers
  in
  response_head_string ~connection status headers
  ^ if include_body && not body_forbidden then body else ""

let cstructs_length =
  List.fold_left (fun length buffer -> length + Cstruct.length buffer) 0

let write_cstructs flow buffers =
  List.iter
    (fun buffer ->
      if Cstruct.length buffer > 0 then
        Eio.Flow.copy_string (Cstruct.to_string buffer) flow)
    buffers

type fixed_length_sink = {
  flow : Eio.Flow.sink_ty Eio.Resource.t;
  mutable remaining : int;
}

module Fixed_length_sink = struct
  type t = fixed_length_sink

  let single_write t buffers =
    let length = cstructs_length buffers in
    if length > t.remaining then raise Response_body_length_mismatch;
    write_cstructs t.flow buffers;
    t.remaining <- t.remaining - length;
    length

  let copy t ~src = Eio.Flow.Pi.simple_copy ~single_write t ~src
end

let fixed_length_sink flow content_length =
  let sink = { flow; remaining = content_length } in
  (sink, Eio.Resource.T (sink, Eio.Flow.Pi.sink (module Fixed_length_sink)))

module Chunked_sink = struct
  type t = Eio.Flow.sink_ty Eio.Resource.t

  let single_write flow buffers =
    let length = cstructs_length buffers in
    if length > 0 then (
      Eio.Flow.copy_string (Printf.sprintf "%x\r\n" length) flow;
      write_cstructs flow buffers;
      Eio.Flow.copy_string "\r\n" flow);
    length

  let copy t ~src = Eio.Flow.Pi.simple_copy ~single_write t ~src
end

let chunked_sink flow =
  Eio.Resource.T (flow, Eio.Flow.Pi.sink (module Chunked_sink))

let response_body_headers response body_view =
  let headers = Response.headers response |> response_framing_headers in
  if body_forbidden_status (Response.status response) then headers
  else
    match body_view with
    | Body.Internal.Buffered body ->
        Headers.set "content-length"
          (string_of_int (String.length body))
          headers
    | Body.Internal.Source { content_length = Some length; _ }
    | Body.Internal.Writer { content_length = Some length; _ } ->
        Headers.set "content-length" (string_of_int length) headers
    | Body.Internal.Source { content_length = None; _ }
    | Body.Internal.Writer { content_length = None; _ } ->
        Headers.set "transfer-encoding" "chunked" headers

let write_fixed_length_body flow content_length write =
  let raw_sink, sink = fixed_length_sink flow content_length in
  write sink;
  if raw_sink.remaining <> 0 then raise Response_body_length_mismatch

let write_chunked_body flow write =
  write (chunked_sink flow);
  Eio.Flow.copy_string "0\r\n\r\n" flow

let write_response_exn ~include_body ~connection flow response =
  let body_view = Body.Internal.view (Response.body response) in
  let headers = response_body_headers response body_view in
  Eio.Flow.copy_string
    (response_head_string ~connection (Response.status response) headers)
    flow;
  if include_body && not (body_forbidden_status (Response.status response)) then
    match body_view with
    | Body.Internal.Buffered body -> Eio.Flow.copy_string body flow
    | Body.Internal.Source { content_length = Some content_length; with_source }
      ->
        write_fixed_length_body flow content_length (fun sink ->
            with_source (fun source -> Eio.Flow.copy source sink))
    | Body.Internal.Writer { content_length = Some content_length; write } ->
        write_fixed_length_body flow content_length write
    | Body.Internal.Source { content_length = None; with_source } ->
        write_chunked_body flow (fun sink ->
            with_source (fun source -> Eio.Flow.copy source sink))
    | Body.Internal.Writer { content_length = None; write } ->
        write_chunked_body flow write

let write_response ~include_body ~connection flow response =
  try
    write_response_exn ~include_body ~connection flow response;
    Ok ()
  with
  | Eio.Cancel.Cancelled _ as exn -> raise exn
  | _ -> Error Response_body_write_failed

let plain_error status body =
  Response.text ~status body |> Response.with_header "connection" "close"

let response_for_error = function
  | Body_too_large -> plain_error Status.payload_too_large "Payload Too Large\n"
  | Request_head_too_large ->
      plain_error Status.request_header_fields_too_large
        "Request Header Fields Too Large\n"
  | Request_head_timeout ->
      plain_error Status.request_timeout "Request Timeout\n"
  | Invalid_request_line | Unsupported_http_version | Unsupported_request_target
  | Malformed_header | Invalid_content_length | Malformed_chunked_body
  | Unsupported_transfer_encoding ->
      plain_error Status.bad_request "Bad Request\n"
