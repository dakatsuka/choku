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

let serialize_response ?(include_body = true) response =
  let body = Response.body response |> Body.to_string in
  let headers =
    Response.headers response
    |> Headers.set "content-length" (string_of_int (String.length body))
    |> Headers.set "connection" "close"
  in
  let status = Response.status response in
  let status_line =
    Printf.sprintf "HTTP/1.1 %d %s\r\n" (Status.code status)
      (Status.reason status)
  in
  let header_lines =
    headers |> Headers.to_list
    |> List.map (fun (name, value) -> name ^ ": " ^ value ^ "\r\n")
    |> String.concat ""
  in
  status_line ^ header_lines ^ "\r\n" ^ if include_body then body else ""

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
