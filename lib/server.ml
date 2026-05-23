type t = { max_request_body_size : int; handler : Handler.t }

let default_max_request_body_size = 1_048_576

let create ?(max_request_body_size = default_max_request_body_size)
    ?(middlewares = []) ~handler () =
  if max_request_body_size < 0 then invalid_arg "max_request_body_size < 0";
  { max_request_body_size; handler = Middleware.apply middlewares handler }

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

type request_head_read = {
  raw_head : string;
  buffered_body : string;
  head : Http1.request_head;
}

let read_request_head flow =
  let buffer = Buffer.create 4096 in
  let scratch = Cstruct.create 4096 in
  let rec read_until_headers () =
    match find_header_end buffer with
    | Some header_end -> Ok header_end
    | None ->
        let read = Eio.Flow.single_read flow scratch in
        Buffer.add_string buffer
          (Cstruct.to_string (Cstruct.sub scratch 0 read));
        read_until_headers ()
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
          Ok { raw_head; buffered_body; head })

let read_fixed_body ~max_request_body_size flow head buffered_body =
  match Http1.content_length head.Http1.headers with
  | Error error -> Error error
  | Ok content_length ->
      if content_length > max_request_body_size then Error Http1.Body_too_large
      else
        let already_read = String.length buffered_body in
        let remaining = content_length - already_read in
        if remaining <= 0 then Ok (String.sub buffered_body 0 content_length)
        else
          let exact = Cstruct.create remaining in
          Eio.Flow.read_exact flow exact;
          Ok (buffered_body ^ Cstruct.to_string exact)

let read_request_bytes max_request_body_size flow =
  match read_request_head flow with
  | Error error -> Error error
  | Ok { raw_head; buffered_body; head } -> (
      match read_fixed_body ~max_request_body_size flow head buffered_body with
      | Error error -> Error error
      | Ok body -> Ok (raw_head ^ "\r\n\r\n" ^ body))

let write_response flow response =
  Eio.Flow.copy_string (Http1.serialize_response response) flow

let handle_connection t flow =
  let response =
    match read_request_bytes t.max_request_body_size flow with
    | Error error -> Http1.response_for_error error
    | Ok raw -> (
        match
          Http1.parse_request_string
            ~max_request_body_size:t.max_request_body_size raw
        with
        | Error error -> Http1.response_for_error error
        | Ok request -> (
            try t.handler request with
            | Eio.Cancel.Cancelled _ as exn -> raise exn
            | _ -> default_internal_error))
  in
  write_response flow response;
  Eio.Flow.shutdown flow `All

let run ~sw ~net ~addr t =
  let socket = Eio.Net.listen ~reuse_addr:true ~backlog:128 ~sw net addr in
  Eio.Net.run_server socket
    ~on_error:(function Eio.Cancel.Cancelled _ as exn -> raise exn | _ -> ())
    (fun flow _addr -> handle_connection t flow)
