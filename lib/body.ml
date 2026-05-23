type consumption_state = Fresh | Consuming | Consumed [@@warning "-37"]

type streaming = {
  source : Eio.Flow.source_ty Eio.Resource.t;
  content_length : int;
  mutable state : consumption_state;
}

type t = Buffered of string | Streaming of streaming [@@warning "-37"]
type error = Body_too_large | Unexpected_end_of_body

exception Unexpected_end_of_body_read

let empty = Buffered ""
let string s = Buffered s

let to_string = function
  | Buffered s -> s
  | Streaming _ ->
      invalid_arg "streaming body cannot be read with Body.to_string"

let with_streaming_source streaming fn =
  match streaming.state with
  | Fresh ->
      streaming.state <- Consuming;
      Fun.protect
        ~finally:(fun () -> streaming.state <- Consumed)
        (fun () -> fn streaming.source)
  | Consuming -> invalid_arg "streaming body is already being consumed"
  | Consumed -> invalid_arg "streaming body has already been consumed"

let to_string_limited_streaming ~max_size streaming =
  match streaming.content_length with
  | body_size when body_size > max_size -> Error Body_too_large
  | _ ->
      with_streaming_source streaming @@ fun source ->
      let buffer = Buffer.create (min max_size 4096) in
      let scratch = Cstruct.create 4096 in
      let rec read_loop total =
        if total = streaming.content_length then Ok (Buffer.contents buffer)
        else
          let remaining = streaming.content_length - total in
          let read_buffer =
            if remaining < Cstruct.length scratch then
              Cstruct.sub scratch 0 remaining
            else scratch
          in
          match Eio.Flow.single_read source read_buffer with
          | exception End_of_file -> Error Unexpected_end_of_body
          | exception Unexpected_end_of_body_read ->
              Error Unexpected_end_of_body
          | read ->
              Buffer.add_string buffer
                (Cstruct.to_string (Cstruct.sub read_buffer 0 read));
              read_loop (total + read)
      in
      read_loop 0

let to_string_limited ~max_size t =
  if max_size < 0 then invalid_arg "negative max_size";
  match t with
  | Buffered s ->
      if String.length s > max_size then Error Body_too_large else Ok s
  | Streaming streaming -> to_string_limited_streaming ~max_size streaming

let is_buffered = function Buffered _ -> true | Streaming _ -> false

let with_source t fn =
  match t with
  | Buffered s -> fn (Eio.Flow.string_source s)
  | Streaming streaming -> with_streaming_source streaming fn

let copy_to_sink t sink =
  with_source t (fun source -> Eio.Flow.copy source sink)

let save_to_path ?append ~create path t =
  match t with
  | Buffered s -> Eio.Path.save ?append ~create path s
  | Streaming _ ->
      Eio.Path.with_open_out ?append ~create path (fun sink ->
          copy_to_sink t sink)

let pp_error formatter = function
  | Body_too_large -> Format.pp_print_string formatter "body too large"
  | Unexpected_end_of_body ->
      Format.pp_print_string formatter "unexpected end of body"

module Internal = struct
  let streaming ~content_length source =
    if content_length < 0 then invalid_arg "negative content_length";
    Streaming { source; content_length; state = Fresh }
end
