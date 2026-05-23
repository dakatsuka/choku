type error =
  | Invalid_request_line
  | Unsupported_http_version
  | Unsupported_request_target
  | Malformed_header
  | Invalid_content_length
  | Body_too_large
  | Unsupported_transfer_encoding

let error_to_string = function
  | Invalid_request_line -> "invalid request line"
  | Unsupported_http_version -> "unsupported HTTP version"
  | Unsupported_request_target -> "unsupported request target"
  | Malformed_header -> "malformed header"
  | Invalid_content_length -> "invalid content-length"
  | Body_too_large -> "body too large"
  | Unsupported_transfer_encoding -> "unsupported transfer-encoding"

module Error = struct
  type nonrec t = error

  let equal = ( = )
  let pp fmt t = Format.pp_print_string fmt (error_to_string t)
end

type request_head = { meth : Method.t; target : string; headers : Headers.t }

let default_max_request_body_size = 1_048_576

let find_header_end raw =
  let len = String.length raw in
  let rec loop index =
    if index + 3 >= len then None
    else if
      Char.equal raw.[index] '\r'
      && Char.equal raw.[index + 1] '\n'
      && Char.equal raw.[index + 2] '\r'
      && Char.equal raw.[index + 3] '\n'
    then Some index
    else loop (index + 1)
  in
  loop 0

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
          if String.length target = 0 || not (Char.equal target.[0] '/') then
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
              match Headers.get "transfer-encoding" headers with
              | Some _ -> Error Unsupported_transfer_encoding
              | None -> Ok { meth; target; headers })))

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

let parse_request_string
    ?(max_request_body_size = default_max_request_body_size) raw =
  match find_header_end raw with
  | None -> Error Malformed_header
  | Some header_end -> (
      let header_block = String.sub raw 0 header_end in
      match parse_request_head_string header_block with
      | Error error -> Error error
      | Ok { meth; target; headers } -> (
          let body_start = header_end + 4 in
          let available_body = String.length raw - body_start |> max 0 in
          match content_length headers with
          | Error error -> Error error
          | Ok body_length -> (
              if body_length > max_request_body_size then Error Body_too_large
              else if available_body < body_length then
                Error Invalid_content_length
              else
                let body =
                  String.sub raw body_start body_length |> Body.string
                in
                Request.make ~meth ~target ~headers ~body |> Result.ok
                |> function
                | Ok request -> Ok request
                | Error _ -> Error Unsupported_request_target)))

let serialize_response response =
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
  status_line ^ header_lines ^ "\r\n" ^ body

let plain_error status body =
  Response.text ~status body |> Response.with_header "connection" "close"

let response_for_error = function
  | Body_too_large -> plain_error Status.payload_too_large "Payload Too Large\n"
  | Invalid_request_line | Unsupported_http_version | Unsupported_request_target
  | Malformed_header | Invalid_content_length | Unsupported_transfer_encoding ->
      plain_error Status.bad_request "Bad Request\n"
