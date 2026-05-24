[@@@alert "-internal"]

type request_body_mode = Request_body_mode.t = Buffered | Streaming

type request_body_mode_decision =
  | Body_mode of request_body_mode
  | Selector_failed

type t = {
  keep_alive : bool;
  max_request_body_size : int;
  max_request_head_size : int;
  request_head_timeout : float option;
  request_body_mode : Http1.request_head -> request_body_mode_decision;
  handler : Handler.t;
}

let default_max_request_body_size = 1_048_576
let default_max_request_head_size = 65_536

let validate_request_head_config ~max_request_head_size ~request_head_timeout =
  if max_request_head_size <= 0 then invalid_arg "max_request_head_size <= 0";
  match request_head_timeout with
  | Some timeout when timeout <= 0.0 ->
      invalid_arg "non-positive request_head_timeout"
  | Some _ | None -> ()

let create ?(keep_alive = true)
    ?(max_request_body_size = default_max_request_body_size)
    ?(max_request_head_size = default_max_request_head_size)
    ?(request_head_timeout = None) ?(request_body_mode = Buffered)
    ?(middlewares = []) ~handler () =
  if max_request_body_size < 0 then invalid_arg "max_request_body_size < 0";
  validate_request_head_config ~max_request_head_size ~request_head_timeout;
  {
    keep_alive;
    max_request_body_size;
    max_request_head_size;
    request_head_timeout;
    request_body_mode = (fun _head -> Body_mode request_body_mode);
    handler = Middleware.apply middlewares handler;
  }

let create_with_request_body_selector ?(keep_alive = true)
    ?(max_request_body_size = default_max_request_body_size)
    ?(max_request_head_size = default_max_request_head_size)
    ?(request_head_timeout = None) ~request_body_mode ?(middlewares = [])
    ~handler () =
  if max_request_body_size < 0 then invalid_arg "max_request_body_size < 0";
  validate_request_head_config ~max_request_head_size ~request_head_timeout;
  let request_body_mode head =
    try
      let selector_head =
        Request_head.make ~meth:head.Http1.meth ~target:head.target
          ~headers:head.headers
      in
      Body_mode (request_body_mode selector_head)
    with
    | Eio.Cancel.Cancelled _ as exn -> raise exn
    | _ -> Selector_failed
  in
  {
    keep_alive;
    max_request_body_size;
    max_request_head_size;
    request_head_timeout;
    request_body_mode;
    handler = Middleware.apply middlewares handler;
  }

let create_router ?(keep_alive = true)
    ?(max_request_body_size = default_max_request_body_size)
    ?(max_request_head_size = default_max_request_head_size)
    ?(request_head_timeout = None) ?(middlewares = []) router =
  if max_request_body_size < 0 then invalid_arg "max_request_body_size < 0";
  validate_request_head_config ~max_request_head_size ~request_head_timeout;
  let router_handler = Router.to_handler router in
  let request_body_mode head =
    match
      Router.Internal.match_route ~meth:head.Http1.meth ~target:head.target
        router
    with
    | None -> Body_mode Buffered
    | Some route -> Body_mode route.request_body_mode
  in
  {
    keep_alive;
    max_request_body_size;
    max_request_head_size;
    request_head_timeout;
    request_body_mode;
    handler = Middleware.apply middlewares router_handler;
  }

let max_request_body_size t = t.max_request_body_size
let handle t request = t.handler request

let default_internal_error =
  Response.text ~status:Status.internal_server_error "Internal Server Error\n"
  |> Response.with_header "connection" "close"

type connection_reader = {
  flow : Eio.Flow.source_ty Eio.Resource.t;
  mutable buffered : string;
}

let connection_reader flow =
  { flow :> Eio.Flow.source_ty Eio.Resource.t; buffered = "" }

let reader_single_read reader buffer =
  let buffered_length = String.length reader.buffered in
  if buffered_length > 0 then (
    let read = min buffered_length (Cstruct.length buffer) in
    Cstruct.blit_from_string reader.buffered 0 buffer 0 read;
    reader.buffered <- String.sub reader.buffered read (buffered_length - read);
    read)
  else Eio.Flow.single_read reader.flow buffer

let reader_read_exact reader buffer =
  let rec loop offset =
    if offset = Cstruct.length buffer then ()
    else
      let target = Cstruct.sub buffer offset (Cstruct.length buffer - offset) in
      match reader_single_read reader target with
      | exception End_of_file -> raise End_of_file
      | read -> loop (offset + read)
  in
  loop 0

module Connection_reader_source = struct
  type t = connection_reader

  let read_methods = []
  let single_read = reader_single_read
end

let reader_source reader =
  Eio.Resource.T (reader, Eio.Flow.Pi.source (module Connection_reader_source))

type fixed_body_source = { reader : connection_reader; mutable remaining : int }

module Fixed_body_source = struct
  type t = fixed_body_source

  let read_methods = []

  let single_read t buffer =
    if t.remaining = 0 then raise End_of_file;
    let capacity = Cstruct.length buffer in
    let read_limit = min capacity t.remaining in
    let read_buffer =
      if read_limit < capacity then Cstruct.sub buffer 0 read_limit else buffer
    in
    let read =
      match reader_single_read t.reader read_buffer with
      | read -> read
      | exception End_of_file -> raise Body.Unexpected_end_of_body_read
    in
    t.remaining <- t.remaining - read;
    read
end

let fixed_body_source reader content_length =
  let remaining = content_length in
  Eio.Resource.T
    ({ reader; remaining }, Eio.Flow.Pi.source (module Fixed_body_source))

type request_head_read =
  | Request_head of Http1.request_head
  | End_of_connection
  | Request_head_error of Http1.error

type header_end_read =
  | Header_end of int
  | Header_end_of_connection
  | Header_end_error of Http1.error

let read_request_head ~max_request_head_size reader =
  let buffer = Buffer.create 4096 in
  Buffer.add_string buffer reader.buffered;
  reader.buffered <- "";
  let scratch = Cstruct.create 4096 in
  let rec read_until_headers () =
    match Http1_wire.find_header_end (Buffer.contents buffer) with
    | Some header_end ->
        if header_end + 4 > max_request_head_size then
          Header_end_error Http1.Request_head_too_large
        else Header_end header_end
    | None -> (
        if Buffer.length buffer > max_request_head_size then
          Header_end_error Http1.Request_head_too_large
        else
          match reader_single_read reader scratch with
          | exception End_of_file ->
              if Buffer.length buffer = 0 then Header_end_of_connection
              else Header_end_error Http1.Malformed_header
          | read ->
              Buffer.add_string buffer
                (Cstruct.to_string (Cstruct.sub scratch 0 read));
              read_until_headers ())
  in
  match read_until_headers () with
  | Header_end_of_connection -> End_of_connection
  | Header_end_error error -> Request_head_error error
  | Header_end header_end -> (
      let raw = Buffer.contents buffer in
      let raw_head = String.sub raw 0 header_end in
      match Http1.parse_request_head_string raw_head with
      | Error error -> Request_head_error error
      | Ok head ->
          let body_start = header_end + 4 in
          reader.buffered <-
            String.sub raw body_start (String.length raw - body_start);
          Request_head head)

let read_fixed_body ~max_request_body_size ~max_chunk_metadata_size reader head
    =
  match Http1.request_body_framing head.Http1.headers with
  | Error error -> Error error
  | Ok (Http1.Fixed content_length) -> (
      if content_length > max_request_body_size then Error Http1.Body_too_large
      else
        let exact = Cstruct.create content_length in
        match reader_read_exact reader exact with
        | exception End_of_file -> Error Http1.Invalid_content_length
        | () -> Ok (Cstruct.to_string exact))
  | Ok Http1.Chunked -> (
      let source_reader = reader_source reader in
      let source =
        Http1_chunked.source ~max_body_size:max_request_body_size
          ~max_metadata_size:max_chunk_metadata_size source_reader ""
      in
      match Eio.Flow.read_all source with
      | body -> Ok body
      | exception Body.Body_too_large_read -> Error Http1.Body_too_large
      | exception Body.Malformed_body_read -> Error Http1.Malformed_chunked_body
      )

let request_of_head_body head body =
  try
    Request.make ~meth:head.Http1.meth ~target:head.target ~headers:head.headers
      ~body
    |> Result.ok
  with Invalid_argument _ -> Error Http1.Unsupported_request_target

let request_of_head head body = request_of_head_body head (Body.string body)

let streaming_request_of_head ~max_request_body_size ~max_chunk_metadata_size
    reader head =
  match Http1.request_body_framing head.Http1.headers with
  | Error error -> Error error
  | Ok (Http1.Fixed content_length) ->
      if content_length > max_request_body_size then Error Http1.Body_too_large
      else
        let source = fixed_body_source reader content_length in
        let body = Body.Internal.streaming ~content_length source in
        request_of_head_body head body
  | Ok Http1.Chunked ->
      let source_reader = reader_source reader in
      let source =
        Http1_chunked.source ~max_body_size:max_request_body_size
          ~max_metadata_size:max_chunk_metadata_size source_reader ""
      in
      let body = Body.Internal.streaming source in
      request_of_head_body head body

type request_after_head =
  | Request_after_head of Request.t * request_body_mode
  | Request_after_head_error of Http1.error
  | Request_body_selector_failed

let read_request_after_head t reader head =
  match t.request_body_mode head with
  | Selector_failed -> Request_body_selector_failed
  | Body_mode Buffered -> (
      match
        read_fixed_body ~max_request_body_size:t.max_request_body_size reader
          head ~max_chunk_metadata_size:t.max_request_head_size
      with
      | Error error -> Request_after_head_error error
      | Ok body -> (
          match request_of_head head body with
          | Ok request -> Request_after_head (request, Buffered)
          | Error error -> Request_after_head_error error))
  | Body_mode Streaming -> (
      match
        streaming_request_of_head ~max_request_body_size:t.max_request_body_size
          ~max_chunk_metadata_size:t.max_request_head_size reader head
      with
      | Ok request -> Request_after_head (request, Streaming)
      | Error error -> Request_after_head_error error)

let read_request_head_with_timeout ?mono_clock t reader =
  match (t.request_head_timeout, mono_clock) with
  | None, _ ->
      read_request_head ~max_request_head_size:t.max_request_head_size reader
  | Some _, None -> Request_head_error Http1.Request_head_timeout
  | Some timeout, Some mono_clock -> (
      let timeout = Eio.Time.Timeout.seconds mono_clock timeout in
      match
        Eio.Time.Timeout.run_exn timeout (fun () ->
            read_request_head ~max_request_head_size:t.max_request_head_size
              reader)
      with
      | request_head -> request_head
      | exception Eio.Time.Timeout ->
          Request_head_error Http1.Request_head_timeout)

type request_read =
  | Read_request of Request.t * request_body_mode
  | Read_end_of_connection
  | Read_error of Http1.error
  | Read_selector_failed of Method.t

let read_request ?mono_clock t reader =
  match read_request_head_with_timeout ?mono_clock t reader with
  | End_of_connection -> Read_end_of_connection
  | Request_head_error error -> Read_error error
  | Request_head head -> (
      match read_request_after_head t reader head with
      | Request_after_head (request, request_body_mode) ->
          Read_request (request, request_body_mode)
      | Request_after_head_error error -> Read_error error
      | Request_body_selector_failed -> Read_selector_failed head.meth)

type connection_decision = Keep_open | Close

let connection_header_value = function
  | Keep_open -> "keep-alive"
  | Close -> "close"

let header_has_connection_token token headers =
  headers
  |> Headers.get_all "connection"
  |> List.exists (fun value ->
      value |> String.split_on_char ','
      |> List.exists (fun candidate ->
          String.equal
            (candidate |> String.trim |> String.lowercase_ascii)
            token))

let requests_close request =
  header_has_connection_token "close" (Request.headers request)

let response_requests_close response =
  header_has_connection_token "close" (Response.headers response)

let write_response ?(include_body = true) ?(connection = Close) flow response =
  Eio.Flow.copy_string
    (Http1.serialize_response ~include_body
       ~connection:(connection_header_value connection)
       response)
    flow

let decide_connection t request request_body_mode response handler_failed =
  if
    (not t.keep_alive) || handler_failed || requests_close request
    || response_requests_close response
    || match request_body_mode with Streaming -> true | Buffered -> false
  then Close
  else Keep_open

let handle_connection ?mono_clock t flow =
  let reader = connection_reader flow in
  let rec loop () =
    match read_request ?mono_clock t reader with
    | Read_end_of_connection -> ()
    | Read_error error ->
        write_response ~connection:Close flow (Http1.response_for_error error)
    | Read_selector_failed meth ->
        let include_body = not (Method.equal meth Method.HEAD) in
        write_response ~include_body ~connection:Close flow
          default_internal_error
    | Read_request (request, request_body_mode) ->
        let handler_failed = ref false in
        let response =
          try t.handler request with
          | Eio.Cancel.Cancelled _ as exn -> raise exn
          | Body.Body_too_large_read ->
              handler_failed := true;
              Http1.response_for_error Http1.Body_too_large
          | Body.Malformed_body_read | Body.Unexpected_end_of_body_read ->
              handler_failed := true;
              Http1.response_for_error Http1.Malformed_chunked_body
          | _ ->
              handler_failed := true;
              default_internal_error
        in
        let include_body =
          not (Method.equal (Request.meth request) Method.HEAD)
        in
        let connection =
          decide_connection t request request_body_mode response !handler_failed
        in
        write_response ~include_body ~connection flow response;
        if connection = Keep_open then loop ()
  in
  loop ();
  Eio.Flow.shutdown flow `All

let run ~sw ~net ?mono_clock ~addr t =
  if Option.is_some t.request_head_timeout && Option.is_none mono_clock then
    invalid_arg "request_head_timeout requires Server.run ~mono_clock";
  let socket = Eio.Net.listen ~reuse_addr:true ~backlog:128 ~sw net addr in
  Eio.Net.run_server socket
    ~on_error:(function Eio.Cancel.Cancelled _ as exn -> raise exn | _ -> ())
    (fun flow _addr -> handle_connection ?mono_clock t flow)
