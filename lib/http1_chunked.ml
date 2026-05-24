type error = Malformed | Body_too_large

let default_metadata_limit = 65_536

let is_hex = function
  | '0' .. '9' | 'a' .. 'f' | 'A' .. 'F' -> true
  | _ -> false

let hex_value = function
  | '0' .. '9' as c -> Char.code c - Char.code '0'
  | 'a' .. 'f' as c -> 10 + Char.code c - Char.code 'a'
  | 'A' .. 'F' as c -> 10 + Char.code c - Char.code 'A'
  | _ -> invalid_arg "not hex"

let parse_size_limited ~max_size size =
  if String.length size = 0 || not (String.for_all is_hex size) then
    Error Malformed
  else
    let rec loop index acc =
      if index = String.length size then Ok acc
      else
        let digit = hex_value size.[index] in
        if
          acc > max_size / 16 || (acc = max_size / 16 && digit > max_size mod 16)
        then Error Body_too_large
        else loop (index + 1) ((acc * 16) + digit)
    in
    loop 0 0

let parse_chunk_size_line ~max_size line =
  let size =
    match String.index_opt line ';' with
    | None -> line
    | Some index -> String.sub line 0 index
  in
  parse_size_limited ~max_size size

let validate_trailer_line line =
  match String.index_opt line ':' with
  | None | Some 0 -> false
  | Some index ->
      let name = String.sub line 0 index in
      let value =
        String.sub line (index + 1) (String.length line - index - 1)
        |> String.trim
      in
      Headers.is_valid_name name && Headers.is_valid_value value

let find_crlf raw start =
  let rec loop index =
    if index + 1 >= String.length raw then None
    else if Char.equal raw.[index] '\r' && Char.equal raw.[index + 1] '\n' then
      Some index
    else loop (index + 1)
  in
  loop start

let add_metadata used bytes limit =
  let used = used + bytes in
  if used > limit then Error Malformed else Ok used

let decode_string ?(max_metadata_size = default_metadata_limit) ~max_body_size
    raw =
  let buffer = Buffer.create (min max_body_size 4096) in
  let rec read_chunk metadata_used decoded_total pos =
    match find_crlf raw pos with
    | None -> Error Malformed
    | Some line_end -> (
        let line = String.sub raw pos (line_end - pos) in
        match
          add_metadata metadata_used (String.length line + 2) max_metadata_size
        with
        | Error error -> Error error
        | Ok metadata_used -> (
            match
              parse_chunk_size_line
                ~max_size:(max_body_size - decoded_total)
                line
            with
            | Error error -> Error error
            | Ok 0 -> read_trailers metadata_used (line_end + 2)
            | Ok size ->
                let data_start = line_end + 2 in
                let data_end = data_start + size in
                if
                  data_end + 1 >= String.length raw
                  || not
                       (Char.equal raw.[data_end] '\r'
                       && Char.equal raw.[data_end + 1] '\n')
                then Error Malformed
                else (
                  Buffer.add_substring buffer raw data_start size;
                  read_chunk metadata_used (decoded_total + size) (data_end + 2))
            ))
  and read_trailers metadata_used pos =
    match find_crlf raw pos with
    | None -> Error Malformed
    | Some line_end -> (
        let line = String.sub raw pos (line_end - pos) in
        match
          add_metadata metadata_used (String.length line + 2) max_metadata_size
        with
        | Error error -> Error error
        | Ok metadata_used ->
            if String.equal line "" then Ok (Buffer.contents buffer)
            else if validate_trailer_line line then
              read_trailers metadata_used (line_end + 2)
            else Error Malformed)
  in
  read_chunk 0 0 0

type prefixed_reader = {
  prefix : string;
  mutable prefix_offset : int;
  live : Eio.Flow.source_ty Eio.Resource.t;
}

let prefixed_reader prefix live = { prefix; prefix_offset = 0; live }

let read_from_prefixed t buffer =
  let prefix_available = String.length t.prefix - t.prefix_offset in
  if prefix_available > 0 then (
    let read = min (Cstruct.length buffer) prefix_available in
    Cstruct.blit_from_string t.prefix t.prefix_offset buffer 0 read;
    t.prefix_offset <- t.prefix_offset + read;
    read)
  else Eio.Flow.single_read t.live buffer

let read_exact_string t length =
  let output = Bytes.create length in
  let rec loop offset =
    if offset = length then Bytes.unsafe_to_string output
    else
      let buffer = Cstruct.create (length - offset) in
      match read_from_prefixed t buffer with
      | exception End_of_file -> raise Body.Malformed_body_read
      | read ->
          Bytes.blit_string
            (Cstruct.to_string (Cstruct.sub buffer 0 read))
            0 output offset read;
          loop (offset + read)
  in
  loop 0

let read_line t ~max_bytes =
  let buffer = Buffer.create 64 in
  let rec loop previous_was_cr =
    match read_exact_string t 1 with
    | "\n" when previous_was_cr ->
        let contents = Buffer.contents buffer in
        String.sub contents 0 (String.length contents - 1)
    | char ->
        Buffer.add_string buffer char;
        if Buffer.length buffer > max_bytes then raise Body.Malformed_body_read;
        loop (String.equal char "\r")
  in
  loop false

type chunked_source = {
  reader : prefixed_reader;
  max_body_size : int;
  max_metadata_size : int;
  mutable metadata_used : int;
  mutable decoded_total : int;
  mutable remaining_chunk : int;
  mutable finished : bool;
}

module Chunked_source = struct
  type t = chunked_source

  let read_methods = []

  let add_metadata_or_raise t line =
    match
      add_metadata t.metadata_used (String.length line + 2) t.max_metadata_size
    with
    | Ok used -> t.metadata_used <- used
    | Error Body_too_large -> assert false
    | Error Malformed -> raise Body.Malformed_body_read

  let read_next_chunk_header t =
    let line =
      read_line t.reader ~max_bytes:(t.max_metadata_size - t.metadata_used)
    in
    add_metadata_or_raise t line;
    match
      parse_chunk_size_line ~max_size:(t.max_body_size - t.decoded_total) line
    with
    | Error Body_too_large -> raise Body.Body_too_large_read
    | Error Malformed -> raise Body.Malformed_body_read
    | Ok 0 ->
        let rec read_trailers () =
          let line =
            read_line t.reader ~max_bytes:(t.max_metadata_size - t.metadata_used)
          in
          add_metadata_or_raise t line;
          if String.equal line "" then ()
          else if validate_trailer_line line then read_trailers ()
          else raise Body.Malformed_body_read
        in
        read_trailers ();
        t.finished <- true
    | Ok size -> t.remaining_chunk <- size

  let consume_chunk_crlf t =
    match read_exact_string t.reader 2 with
    | "\r\n" -> ()
    | _ -> raise Body.Malformed_body_read

  let single_read t buffer =
    if Cstruct.length buffer = 0 then 0
    else if t.finished then raise End_of_file
    else (
      if t.remaining_chunk = 0 then read_next_chunk_header t;
      if t.finished then raise End_of_file;
      let read_limit = min (Cstruct.length buffer) t.remaining_chunk in
      let read_buffer =
        if read_limit < Cstruct.length buffer then
          Cstruct.sub buffer 0 read_limit
        else buffer
      in
      let read =
        match read_from_prefixed t.reader read_buffer with
        | exception End_of_file -> raise Body.Malformed_body_read
        | read -> read
      in
      t.remaining_chunk <- t.remaining_chunk - read;
      t.decoded_total <- t.decoded_total + read;
      if t.remaining_chunk = 0 then consume_chunk_crlf t;
      read)
end

let source ~max_body_size ~max_metadata_size flow prefix =
  Eio.Resource.T
    ( {
        reader =
          prefixed_reader prefix (flow :> Eio.Flow.source_ty Eio.Resource.t);
        max_body_size;
        max_metadata_size;
        metadata_used = 0;
        decoded_total = 0;
        remaining_chunk = 0;
        finished = false;
      },
      Eio.Flow.Pi.source (module Chunked_source) )
