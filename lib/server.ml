[@@@alert "-internal"]

type request_body_mode = Request_body_mode.t = Buffered | Streaming

type t = {
  max_request_body_size : int;
  request_body_mode : Http1.request_head -> request_body_mode;
  handler : Handler.t;
}

let default_max_request_body_size = 1_048_576

let create ?(max_request_body_size = default_max_request_body_size)
    ?(request_body_mode = Buffered) ?(middlewares = []) ~handler () =
  if max_request_body_size < 0 then invalid_arg "max_request_body_size < 0";
  {
    max_request_body_size;
    request_body_mode = (fun _head -> request_body_mode);
    handler = Middleware.apply middlewares handler;
  }

let create_router ?(max_request_body_size = default_max_request_body_size)
    ?(middlewares = []) router =
  if max_request_body_size < 0 then invalid_arg "max_request_body_size < 0";
  let router_handler = Router.to_handler router in
  let request_body_mode head =
    match
      Router.Internal.match_route ~meth:head.Http1.meth ~target:head.target
        router
    with
    | None -> Buffered
    | Some route -> route.request_body_mode
  in
  {
    max_request_body_size;
    request_body_mode;
    handler = Middleware.apply middlewares router_handler;
  }

let max_request_body_size t = t.max_request_body_size
let handle t request = t.handler request

let default_internal_error =
  Response.text ~status:Status.internal_server_error "Internal Server Error\n"
  |> Response.with_header "connection" "close"

let find_header_end buffer =
  let raw = Buffer.contents buffer in
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

type request_head_read = { buffered_body : string; head : Http1.request_head }

type fixed_body_source = {
  prefix : string;
  mutable prefix_offset : int;
  live : Eio.Flow.source_ty Eio.Resource.t;
  mutable remaining : int;
}

module Fixed_body_source = struct
  type t = fixed_body_source

  let read_methods = []

  let single_read t buffer =
    if t.remaining = 0 then raise End_of_file;
    let capacity = Cstruct.length buffer in
    let read_limit = min capacity t.remaining in
    let prefix_available = String.length t.prefix - t.prefix_offset in
    if prefix_available > 0 then (
      let read = min read_limit prefix_available in
      Cstruct.blit_from_string t.prefix t.prefix_offset buffer 0 read;
      t.prefix_offset <- t.prefix_offset + read;
      t.remaining <- t.remaining - read;
      read)
    else
      let read_buffer =
        if read_limit < capacity then Cstruct.sub buffer 0 read_limit
        else buffer
      in
      let read =
        match Eio.Flow.single_read t.live read_buffer with
        | read -> read
        | exception End_of_file -> raise Body.Unexpected_end_of_body_read
      in
      t.remaining <- t.remaining - read;
      read
end

let fixed_body_source flow buffered_body content_length =
  let prefix =
    if String.length buffered_body > content_length then
      String.sub buffered_body 0 content_length
    else buffered_body
  in
  let remaining = content_length in
  Eio.Resource.T
    ( {
        prefix;
        prefix_offset = 0;
        live = (flow :> Eio.Flow.source_ty Eio.Resource.t);
        remaining;
      },
      Eio.Flow.Pi.source (module Fixed_body_source) )

let read_request_head flow =
  let buffer = Buffer.create 4096 in
  let scratch = Cstruct.create 4096 in
  let rec read_until_headers () =
    match find_header_end buffer with
    | Some header_end -> Ok header_end
    | None -> (
        match Eio.Flow.single_read flow scratch with
        | exception End_of_file -> Error Http1.Malformed_header
        | read ->
            Buffer.add_string buffer
              (Cstruct.to_string (Cstruct.sub scratch 0 read));
            read_until_headers ())
  in
  match read_until_headers () with
  | Error error -> Error error
  | Ok header_end -> (
      let raw = Buffer.contents buffer in
      let raw_head = String.sub raw 0 header_end in
      match Http1.parse_request_head_string raw_head with
      | Error error -> Error error
      | Ok head ->
          let body_start = header_end + 4 in
          let buffered_body =
            String.sub raw body_start (String.length raw - body_start)
          in
          Ok { buffered_body; head })

let read_fixed_body ~max_request_body_size flow head buffered_body =
  match Http1.content_length head.Http1.headers with
  | Error error -> Error error
  | Ok content_length -> (
      if content_length > max_request_body_size then Error Http1.Body_too_large
      else
        let already_read = String.length buffered_body in
        let remaining = content_length - already_read in
        if remaining <= 0 then Ok (String.sub buffered_body 0 content_length)
        else
          let exact = Cstruct.create remaining in
          match Eio.Flow.read_exact flow exact with
          | exception End_of_file -> Error Http1.Invalid_content_length
          | () -> Ok (buffered_body ^ Cstruct.to_string exact))

let request_of_head_body head body =
  try
    Request.make ~meth:head.Http1.meth ~target:head.target ~headers:head.headers
      ~body
    |> Result.ok
  with Invalid_argument _ -> Error Http1.Unsupported_request_target

let request_of_head head body = request_of_head_body head (Body.string body)

let streaming_request_of_head ~max_request_body_size flow head buffered_body =
  match Http1.content_length head.Http1.headers with
  | Error error -> Error error
  | Ok content_length ->
      if content_length > max_request_body_size then Error Http1.Body_too_large
      else
        let source = fixed_body_source flow buffered_body content_length in
        let body = Body.Internal.streaming ~content_length source in
        request_of_head_body head body

let read_request t flow =
  match read_request_head flow with
  | Error error -> Error error
  | Ok { buffered_body; head } -> (
      match t.request_body_mode head with
      | Buffered -> (
          match
            read_fixed_body ~max_request_body_size:t.max_request_body_size flow
              head buffered_body
          with
          | Error error -> Error error
          | Ok body -> request_of_head head body)
      | Streaming ->
          streaming_request_of_head
            ~max_request_body_size:t.max_request_body_size flow head
            buffered_body)

let write_response flow response =
  Eio.Flow.copy_string (Http1.serialize_response response) flow

let handle_connection t flow =
  let response =
    match read_request t flow with
    | Error error -> Http1.response_for_error error
    | Ok request -> (
        try t.handler request with
        | Eio.Cancel.Cancelled _ as exn -> raise exn
        | _ -> default_internal_error)
  in
  write_response flow response;
  Eio.Flow.shutdown flow `All

let run ~sw ~net ~addr t =
  let socket = Eio.Net.listen ~reuse_addr:true ~backlog:128 ~sw net addr in
  Eio.Net.run_server socket
    ~on_error:(function Eio.Cancel.Cancelled _ as exn -> raise exn | _ -> ())
    (fun flow _addr -> handle_connection t flow)
