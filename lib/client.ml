[@@@alert "-internal"]

module Error = struct
  type t =
    | Invalid_url of string
    | Unsupported_scheme of string
    | Connection_failed of exn
    | Malformed_response of string
    | Response_head_too_large
    | Invalid_content_length
    | Unsupported_transfer_encoding
    | Malformed_chunked_body
    | Response_body_too_large
    | Request_body_not_buffered
    | Unsupported_method of Method.t
    | Unsupported_upgrade

  let pp fmt = function
    | Invalid_url reason -> Format.fprintf fmt "invalid URL: %s" reason
    | Unsupported_scheme scheme ->
        Format.fprintf fmt "unsupported URL scheme: %s" scheme
    | Connection_failed exn ->
        Format.fprintf fmt "connection failed: %s" (Printexc.to_string exn)
    | Malformed_response reason ->
        Format.fprintf fmt "malformed response: %s" reason
    | Response_head_too_large ->
        Format.pp_print_string fmt "response head too large"
    | Invalid_content_length ->
        Format.pp_print_string fmt "invalid content-length"
    | Unsupported_transfer_encoding ->
        Format.pp_print_string fmt "unsupported transfer-encoding"
    | Malformed_chunked_body ->
        Format.pp_print_string fmt "malformed chunked body"
    | Response_body_too_large ->
        Format.pp_print_string fmt "response body too large"
    | Request_body_not_buffered ->
        Format.pp_print_string fmt "request body is not buffered"
    | Unsupported_method meth ->
        Format.fprintf fmt "unsupported method: %a" Method.pp meth
    | Unsupported_upgrade -> Format.pp_print_string fmt "unsupported upgrade"

  let equal a b =
    match (a, b) with
    | Invalid_url a, Invalid_url b -> String.equal a b
    | Unsupported_scheme a, Unsupported_scheme b -> String.equal a b
    | Connection_failed a, Connection_failed b ->
        String.equal (Printexc.to_string a) (Printexc.to_string b)
    | Malformed_response a, Malformed_response b -> String.equal a b
    | Response_head_too_large, Response_head_too_large -> true
    | Invalid_content_length, Invalid_content_length -> true
    | Unsupported_transfer_encoding, Unsupported_transfer_encoding -> true
    | Malformed_chunked_body, Malformed_chunked_body -> true
    | Response_body_too_large, Response_body_too_large -> true
    | Request_body_not_buffered, Request_body_not_buffered -> true
    | Unsupported_method a, Unsupported_method b -> Method.equal a b
    | Unsupported_upgrade, Unsupported_upgrade -> true
    | _ -> false
end

let is_digit = function '0' .. '9' -> true | _ -> false

let has_forbidden_url_byte s =
  String.exists
    (function '\000' .. '\031' | '\127' | ' ' -> true | _ -> false)
    s

let contains s char = String.contains s char

module Request = struct
  type t = {
    meth : Method.t;
    url : string;
    authority : string;
    host : string;
    port : int;
    target : string;
    headers : Headers.t;
    body : Body.t;
  }

  let method_is_connect meth = String.equal (Method.to_string meth) "CONNECT"

  let split_scheme url =
    match String.index_opt url ':' with
    | None -> Error (Error.Invalid_url "missing scheme")
    | Some index ->
        let scheme = String.sub url 0 index |> String.lowercase_ascii in
        if
          String.length url < index + 3
          || not
               (Char.equal url.[index + 1] '/' && Char.equal url.[index + 2] '/')
        then Error (Error.Invalid_url "missing authority")
        else
          let rest =
            String.sub url (index + 3) (String.length url - index - 3)
          in
          Ok (scheme, rest)

  let split_authority rest =
    let rec loop index =
      if index = String.length rest then (rest, "")
      else
        match rest.[index] with
        | '/' | '?' ->
            ( String.sub rest 0 index,
              String.sub rest index (String.length rest - index) )
        | _ -> loop (index + 1)
    in
    loop 0

  let parse_port value =
    if String.length value = 0 || not (String.for_all is_digit value) then
      Error (Error.Invalid_url "invalid port")
    else
      match int_of_string value with
      | port when port >= 0 && port <= 65535 -> Ok port
      | _ -> Error (Error.Invalid_url "invalid port")
      | exception Failure _ -> Error (Error.Invalid_url "invalid port")

  let parse_authority authority =
    if String.length authority = 0 then Error (Error.Invalid_url "missing host")
    else if contains authority '@' then
      Error (Error.Invalid_url "userinfo not allowed")
    else if contains authority '[' || contains authority ']' then
      Error (Error.Invalid_url "IPv6 literal not supported")
    else
      match String.split_on_char ':' authority with
      | [ host ] ->
          if String.length host = 0 then
            Error (Error.Invalid_url "missing host")
          else Ok (host, 80, host)
      | [ host; port ] -> (
          if String.length host = 0 then
            Error (Error.Invalid_url "missing host")
          else
            match parse_port port with
            | Error _ as error -> error
            | Ok port ->
                let authority = if port = 80 then host else authority in
                Ok (host, port, authority))
      | _ -> Error (Error.Invalid_url "invalid authority")

  let normalize_target rest =
    if String.equal rest "" then Ok "/"
    else if Char.equal rest.[0] '/' then Ok rest
    else if Char.equal rest.[0] '?' then Ok ("/" ^ rest)
    else Error (Error.Invalid_url "invalid target")

  let make ?(headers = Headers.empty) ?(body = Body.empty) ~meth ~url () =
    if method_is_connect meth then Error (Error.Unsupported_method meth)
    else if has_forbidden_url_byte url then
      Error (Error.Invalid_url "invalid byte")
    else if contains url '#' then
      Error (Error.Invalid_url "fragment not allowed")
    else
      match split_scheme url with
      | Error _ as error -> error
      | Ok (scheme, rest) -> (
          if not (String.equal scheme "http") then
            Error (Error.Unsupported_scheme scheme)
          else
            let authority, target_part = split_authority rest in
            match parse_authority authority with
            | Error _ as error -> error
            | Ok (host, port, authority) -> (
                match normalize_target target_part with
                | Error _ as error -> error
                | Ok target ->
                    Ok
                      {
                        meth;
                        url;
                        authority;
                        host;
                        port;
                        target;
                        headers;
                        body;
                      }))

  let meth t = t.meth
  let url t = t.url
  let authority t = t.authority
  let host t = t.host
  let port t = t.port
  let target t = t.target
  let headers t = t.headers
  let body t = t.body
  let with_headers headers t = { t with headers }

  let with_header name value t =
    { t with headers = Headers.set name value t.headers }

  let with_body body t = { t with body }
end

module Response = struct
  type t = { status : Status.t; headers : Headers.t; body : Body.t }

  let make ?(headers = Headers.empty) ?(body = Body.empty) status =
    { status; headers; body }

  let status t = t.status
  let headers t = t.headers
  let body t = t.body
end

module Handler = struct
  type t = Request.t -> (Response.t, Error.t) result
end

module Middleware = struct
  type t = Handler.t -> Handler.t

  let identity : t = fun handler -> handler
  let compose (a : t) (b : t) : t = fun handler -> a (b handler)

  let apply (middlewares : t list) (handler : Handler.t) : Handler.t =
    List.fold_right
      (fun middleware wrapped -> middleware wrapped)
      middlewares handler
end

type t = { call : sw:Eio.Switch.t -> Handler.t }

let default_max_response_head_size = 16_384
let default_max_response_body_size = 1_048_576

type reader = {
  flow : Eio.Flow.source_ty Eio.Resource.t;
  mutable buffered : string;
}

let reader flow = { flow :> Eio.Flow.source_ty Eio.Resource.t; buffered = "" }

let reader_single_read reader buffer =
  let buffered_length = String.length reader.buffered in
  if buffered_length > 0 then (
    let read = min buffered_length (Cstruct.length buffer) in
    Cstruct.blit_from_string reader.buffered 0 buffer 0 read;
    reader.buffered <- String.sub reader.buffered read (buffered_length - read);
    read)
  else Eio.Flow.single_read reader.flow buffer

module Reader_source = struct
  type t = reader

  let read_methods = []
  let single_read = reader_single_read
end

let reader_source reader =
  Eio.Resource.T (reader, Eio.Flow.Pi.source (module Reader_source))

let split_lines headers =
  headers |> String.split_on_char '\n'
  |> List.map (fun line ->
      if String.length line > 0 && Char.equal line.[String.length line - 1] '\r'
      then String.sub line 0 (String.length line - 1)
      else line)

let parse_header line =
  match String.index_opt line ':' with
  | None -> Error (Error.Malformed_response "malformed header")
  | Some 0 -> Error (Error.Malformed_response "malformed header")
  | Some index ->
      let name = String.sub line 0 index in
      let value =
        String.sub line (index + 1) (String.length line - index - 1)
        |> String.trim
      in
      if
        (not (Headers.is_valid_name name)) || not (Headers.is_valid_value value)
      then Error (Error.Malformed_response "malformed header")
      else Ok (name, value)

let parse_headers lines =
  let rec loop headers = function
    | [] -> Ok headers
    | "" :: rest -> loop headers rest
    | line :: rest -> (
        match parse_header line with
        | Error _ as error -> error
        | Ok (name, value) -> loop (Headers.add name value headers) rest)
  in
  loop Headers.empty lines

let parse_status_line line =
  let prefix = "HTTP/1.1 " in
  if not (String.starts_with ~prefix line) then
    Error (Error.Malformed_response "unsupported HTTP version")
  else if String.length line < String.length prefix + 3 then
    Error (Error.Malformed_response "invalid status line")
  else
    let code_text = String.sub line (String.length prefix) 3 in
    let after_code = String.length prefix + 3 in
    if not (String.for_all is_digit code_text) then
      Error (Error.Malformed_response "invalid status code")
    else if
      String.length line > after_code && not (Char.equal line.[after_code] ' ')
    then Error (Error.Malformed_response "invalid status line")
    else
      match int_of_string code_text with
      | code -> (
          match Status.of_code code with
          | status -> Ok status
          | exception Invalid_argument _ ->
              Error (Error.Malformed_response "invalid status code"))
      | exception Failure _ ->
          Error (Error.Malformed_response "invalid status code")

let parse_response_head_string raw =
  match split_lines raw with
  | [] -> Error (Error.Malformed_response "empty response head")
  | status_line :: header_lines -> (
      match parse_status_line status_line with
      | Error _ as error -> error
      | Ok status -> (
          match parse_headers header_lines with
          | Error _ as error -> error
          | Ok headers -> Ok (status, headers)))

let read_response_head ~max_response_head_size reader =
  let scratch = Cstruct.create 4096 in
  let rec loop () =
    match Http1_wire.find_header_end reader.buffered with
    | Some header_end ->
        if header_end + 4 > max_response_head_size then
          Error Error.Response_head_too_large
        else
          let raw = String.sub reader.buffered 0 header_end in
          reader.buffered <-
            String.sub reader.buffered (header_end + 4)
              (String.length reader.buffered - header_end - 4);
          parse_response_head_string raw
    | None -> (
        if String.length reader.buffered > max_response_head_size then
          Error Error.Response_head_too_large
        else
          match reader_single_read reader scratch with
          | exception End_of_file ->
              Error (Error.Malformed_response "unexpected end of response head")
          | read ->
              reader.buffered <-
                reader.buffered ^ Cstruct.to_string (Cstruct.sub scratch 0 read);
              loop ())
  in
  loop ()

let response_body_forbidden request status =
  Method.equal (Request.meth request) Method.HEAD
  ||
  match Status.class_ status with
  | Informational -> true
  | Successful | Redirection | Client_error | Server_error ->
      let code = Status.code status in
      code = 204 || code = 304

let parse_content_length headers =
  match Headers.get_all "content-length" headers with
  | [] -> Ok None
  | [ value ] -> (
      let value = String.trim value in
      if String.length value = 0 || not (String.for_all is_digit value) then
        Error Error.Invalid_content_length
      else
        match int_of_string value with
        | length -> Ok (Some length)
        | exception Failure _ -> Error Error.Invalid_content_length)
  | _ -> Error Error.Invalid_content_length

let parse_transfer_encoding headers =
  match Headers.get_all "transfer-encoding" headers with
  | [] -> Ok false
  | [ value ]
    when String.equal (String.trim value |> String.lowercase_ascii) "chunked" ->
      Ok true
  | _ -> Error Error.Unsupported_transfer_encoding

let take_from_reader reader length =
  if length = 0 then Ok ""
  else if String.length reader.buffered >= length then (
    let taken = String.sub reader.buffered 0 length in
    reader.buffered <-
      String.sub reader.buffered length (String.length reader.buffered - length);
    Ok taken)
  else
    let prefix = reader.buffered in
    reader.buffered <- "";
    let remaining = length - String.length prefix in
    let exact = Cstruct.create remaining in
    try
      Eio.Flow.read_exact reader.flow exact;
      Ok (prefix ^ Cstruct.to_string exact)
    with End_of_file ->
      Error (Error.Malformed_response "unexpected end of response body")

let read_until_close_limited ~max_response_body_size reader =
  let buffer = Buffer.create (min max_response_body_size 4096) in
  let total = ref 0 in
  let add bytes =
    total := !total + String.length bytes;
    if !total > max_response_body_size then Error Error.Response_body_too_large
    else (
      Buffer.add_string buffer bytes;
      Ok ())
  in
  match add reader.buffered with
  | Error _ as error -> error
  | Ok () ->
      reader.buffered <- "";
      let scratch = Cstruct.create 4096 in
      let rec loop () =
        match reader_single_read reader scratch with
        | exception End_of_file -> Ok (Buffer.contents buffer)
        | read -> (
            let bytes = Cstruct.to_string (Cstruct.sub scratch 0 read) in
            match add bytes with Error _ as error -> error | Ok () -> loop ())
      in
      loop ()

let read_chunked_body ~max_response_head_size ~max_response_body_size reader =
  let prefix = reader.buffered in
  reader.buffered <- "";
  let source =
    Http1_chunked.source ~max_body_size:max_response_body_size
      ~max_metadata_size:max_response_head_size (reader_source reader) prefix
  in
  try Ok (Eio.Flow.read_all source) with
  | Body.Body_too_large_read -> Error Error.Response_body_too_large
  | Body.Malformed_body_read -> Error Error.Malformed_chunked_body

let read_body ~max_response_head_size ~max_response_body_size request reader
    status headers =
  if response_body_forbidden request status then Ok Body.empty
  else
    let has_content_length = Headers.get_all "content-length" headers <> [] in
    let has_transfer_encoding =
      Headers.get_all "transfer-encoding" headers <> []
    in
    if has_content_length && has_transfer_encoding then
      Error Error.Unsupported_transfer_encoding
    else
      match parse_transfer_encoding headers with
      | Error _ as error -> error
      | Ok true -> (
          match
            read_chunked_body ~max_response_head_size ~max_response_body_size
              reader
          with
          | Error _ as error -> error
          | Ok body -> Ok (Body.string body))
      | Ok false -> (
          match parse_content_length headers with
          | Error _ as error -> error
          | Ok (Some length) -> (
              if length > max_response_body_size then
                Error Error.Response_body_too_large
              else
                match take_from_reader reader length with
                | Error _ as error -> error
                | Ok body -> Ok (Body.string body))
          | Ok None -> (
              match read_until_close_limited ~max_response_body_size reader with
              | Error _ as error -> error
              | Ok body -> Ok (Body.string body)))

let rec read_final_response ~max_response_head_size ~max_response_body_size
    request reader =
  match read_response_head ~max_response_head_size reader with
  | Error _ as error -> error
  | Ok (status, headers) -> (
      if Status.code status = 101 then Error Error.Unsupported_upgrade
      else
        match Status.class_ status with
        | Informational ->
            read_final_response ~max_response_head_size ~max_response_body_size
              request reader
        | Successful | Redirection | Client_error | Server_error -> (
            match
              read_body ~max_response_head_size ~max_response_body_size request
                reader status headers
            with
            | Error _ as error -> error
            | Ok body -> Ok (Response.make ~headers ~body status)))

let request_wire request body =
  let headers =
    Request.headers request |> Headers.remove "host"
    |> Headers.remove "connection"
    |> Headers.remove "content-length"
    |> Headers.remove "transfer-encoding"
    |> Headers.set "host" (Request.authority request)
    |> Headers.set "connection" "close"
    |> Headers.set "content-length" (string_of_int (String.length body))
  in
  let header_lines =
    headers |> Headers.to_list
    |> List.map (fun (name, value) -> name ^ ": " ^ value ^ "\r\n")
    |> String.concat ""
  in
  Printf.sprintf "%s %s HTTP/1.1\r\n%s\r\n%s"
    (Method.to_string (Request.meth request))
    (Request.target request) header_lines body

let connect_first ~sw net host port =
  let service = string_of_int port in
  match Eio.Net.getaddrinfo_stream ~service net host with
  | exception (Eio.Cancel.Cancelled _ as exn) -> raise exn
  | exception exn -> Error (Error.Connection_failed exn)
  | addrs ->
      let rec loop last_error = function
        | [] ->
            let exn =
              match last_error with
              | Some exn -> exn
              | None -> Failure "no stream addresses"
            in
            Error (Error.Connection_failed exn)
        | addr :: rest -> (
            match Eio.Net.connect ~sw net addr with
            | flow -> Ok flow
            | exception (Eio.Cancel.Cancelled _ as exn) -> raise exn
            | exception exn -> loop (Some exn) rest)
      in
      loop None addrs

let transport ~sw ~net ~max_response_head_size ~max_response_body_size request =
  if not (Body.is_buffered (Request.body request)) then
    Error Error.Request_body_not_buffered
  else
    match
      connect_first ~sw net (Request.host request) (Request.port request)
    with
    | Error _ as error -> error
    | Ok flow ->
        Fun.protect
          ~finally:(fun () ->
            (try Eio.Flow.shutdown flow `All with _ -> ());
            try Eio.Flow.close flow with _ -> ())
          (fun () ->
            try
              let body = Body.to_string (Request.body request) in
              Eio.Flow.copy_string (request_wire request body) flow;
              let reader = reader flow in
              read_final_response ~max_response_head_size
                ~max_response_body_size request reader
            with
            | Eio.Cancel.Cancelled _ as exn -> raise exn
            | exn -> Error (Error.Connection_failed exn))

let create ?(max_response_head_size = default_max_response_head_size)
    ?(max_response_body_size = default_max_response_body_size)
    ?(middlewares = []) ~net () =
  if max_response_head_size <= 0 then invalid_arg "max_response_head_size <= 0";
  if max_response_body_size < 0 then invalid_arg "max_response_body_size < 0";
  let middleware = Middleware.apply middlewares in
  {
    call =
      (fun ~sw ->
        middleware
          (transport ~sw ~net ~max_response_head_size ~max_response_body_size));
  }

let request ~sw t request = t.call ~sw request
