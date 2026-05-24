type consumption_state = Fresh | Consuming | Consumed [@@warning "-37"]

type streaming = {
  source : Eio.Flow.source_ty Eio.Resource.t;
  content_length : int option;
  mutable state : consumption_state;
}

type writer = {
  write : Eio.Flow.sink_ty Eio.Resource.t -> unit;
  content_length : int option;
  mutable state : consumption_state;
}

type t = Buffered of string | Streaming of streaming | Writer of writer
[@@warning "-37"]

type error = Body_too_large | Unexpected_end_of_body | Malformed_body

exception Unexpected_end_of_body_read
exception Body_too_large_read
exception Malformed_body_read

let empty = Buffered ""
let string s = Buffered s

let to_string = function
  | Buffered s -> s
  | Streaming _ | Writer _ ->
      invalid_arg "streaming body cannot be read with Body.to_string"

let with_streaming_source (streaming : streaming) fn =
  match streaming.state with
  | Fresh ->
      streaming.state <- Consuming;
      Fun.protect
        ~finally:(fun () -> streaming.state <- Consumed)
        (fun () -> fn streaming.source)
  | Consuming -> invalid_arg "streaming body is already being consumed"
  | Consumed -> invalid_arg "streaming body has already been consumed"

let to_string_limited_streaming ~max_size (streaming : streaming) =
  let expected_too_large =
    match streaming.content_length with
    | Some body_size when body_size > max_size -> true
    | Some _ | None -> false
  in
  if expected_too_large then Error Body_too_large
  else
    with_streaming_source streaming @@ fun source ->
    let buffer = Buffer.create (min max_size 4096) in
    let scratch = Cstruct.create 4096 in
    let rec read_loop total =
      match streaming.content_length with
      | Some content_length when total = content_length ->
          Ok (Buffer.contents buffer)
      | _ -> (
          let remaining_limit = max_size - total in
          if remaining_limit = 0 then
            match Eio.Flow.single_read source (Cstruct.create 1) with
            | exception End_of_file -> Ok (Buffer.contents buffer)
            | exception Body_too_large_read -> Error Body_too_large
            | exception Malformed_body_read -> Error Malformed_body
            | exception Unexpected_end_of_body_read ->
                Error Unexpected_end_of_body
            | _ -> Error Body_too_large
          else
            let read_limit =
              match streaming.content_length with
              | Some content_length ->
                  min remaining_limit (content_length - total)
              | None -> remaining_limit
            in
            let read_buffer =
              if read_limit < Cstruct.length scratch then
                Cstruct.sub scratch 0 read_limit
              else scratch
            in
            match Eio.Flow.single_read source read_buffer with
            | exception End_of_file -> (
                match streaming.content_length with
                | Some _ -> Error Unexpected_end_of_body
                | None -> Ok (Buffer.contents buffer))
            | exception Unexpected_end_of_body_read ->
                Error Unexpected_end_of_body
            | exception Body_too_large_read -> Error Body_too_large
            | exception Malformed_body_read -> Error Malformed_body
            | read ->
                Buffer.add_string buffer
                  (Cstruct.to_string (Cstruct.sub read_buffer 0 read));
                read_loop (total + read))
    in
    read_loop 0

let to_string_limited ~max_size t =
  if max_size < 0 then invalid_arg "negative max_size";
  match t with
  | Buffered s ->
      if String.length s > max_size then Error Body_too_large else Ok s
  | Streaming streaming -> to_string_limited_streaming ~max_size streaming
  | Writer _ ->
      invalid_arg "streaming body cannot be read with Body.to_string_limited"

let is_buffered = function
  | Buffered _ -> true
  | Streaming _ | Writer _ -> false

let with_streaming_writer writer sink =
  match writer.state with
  | Fresh ->
      writer.state <- Consuming;
      Fun.protect
        ~finally:(fun () -> writer.state <- Consumed)
        (fun () -> writer.write sink)
  | Consuming -> invalid_arg "streaming body is already being consumed"
  | Consumed -> invalid_arg "streaming body has already been consumed"

let with_source t fn =
  match t with
  | Buffered s -> fn (Eio.Flow.string_source s)
  | Streaming streaming -> with_streaming_source streaming fn
  | Writer _ -> invalid_arg "streaming writer body has no source"

let copy_to_sink t (sink : [> Eio.Flow.sink_ty ] Eio.Resource.t) =
  let sink = (sink :> Eio.Flow.sink_ty Eio.Resource.t) in
  match t with
  | Writer writer -> with_streaming_writer writer sink
  | Buffered _ | Streaming _ ->
      with_source t (fun source -> Eio.Flow.copy source sink)

let save_to_path ?append ~create path t =
  match t with
  | Buffered s -> Eio.Path.save ?append ~create path s
  | Streaming _ | Writer _ ->
      Eio.Path.with_open_out ?append ~create path (fun sink ->
          copy_to_sink t (sink :> Eio.Flow.sink_ty Eio.Resource.t))

let pp_error formatter = function
  | Body_too_large -> Format.pp_print_string formatter "body too large"
  | Unexpected_end_of_body ->
      Format.pp_print_string formatter "unexpected end of body"
  | Malformed_body -> Format.pp_print_string formatter "malformed body"

module Internal = struct
  type view =
    | Buffered of string
    | Source of {
        content_length : int option;
        with_source : 'a. (Eio.Flow.source_ty Eio.Resource.t -> 'a) -> 'a;
      }
    | Writer of {
        content_length : int option;
        write : Eio.Flow.sink_ty Eio.Resource.t -> unit;
      }

  let view (body : t) =
    match body with
    | Buffered s -> Buffered s
    | Streaming streaming ->
        Source
          {
            content_length = streaming.content_length;
            with_source = (fun fn -> with_streaming_source streaming fn);
          }
    | Writer writer ->
        Writer
          {
            content_length = writer.content_length;
            write = with_streaming_writer writer;
          }

  let streaming ?content_length source =
    (match content_length with
    | Some content_length when content_length < 0 ->
        invalid_arg "negative content_length"
    | Some _ | None -> ());
    Streaming { source; content_length; state = Fresh }

  let writer ?content_length write : t =
    (match content_length with
    | Some content_length when content_length < 0 ->
        invalid_arg "negative content_length"
    | Some _ | None -> ());
    Writer { write; content_length; state = Fresh }
end
