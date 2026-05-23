type error =
  | Missing_content_type
  | Unsupported_content_type of string
  | Missing_boundary
  | Malformed_body
  | Body_too_large
  | Unexpected_end_of_body

module Part = struct
  type t = {
    headers : Headers.t;
    name : string option;
    filename : string option;
    content_type : string option;
    body : Body.t;
  }

  let headers t = t.headers
  let name t = t.name
  let filename t = t.filename
  let content_type t = t.content_type
  let body t = t.body
  let copy_to_sink t sink = Body.copy_to_sink t.body sink

  let save_to_path ?append ~create path t =
    Body.save_to_path ?append ~create path t.body
end

type t = Part.t list

let parts t = t

let get name t =
  List.find_opt
    (fun part -> Option.equal String.equal (Part.name part) (Some name))
    t

let get_all name t =
  List.filter
    (fun part -> Option.equal String.equal (Part.name part) (Some name))
    t

let malformed = Error Malformed_body

let starts_with ~prefix s =
  let prefix_length = String.length prefix in
  String.length s >= prefix_length
  && String.equal prefix (String.sub s 0 prefix_length)

let substring_from s index =
  if index > String.length s then ""
  else String.sub s index (String.length s - index)

let find_sub ~pattern s ~start =
  let pattern_length = String.length pattern in
  let limit = String.length s - pattern_length in
  let rec loop index =
    if index > limit then None
    else if String.equal pattern (String.sub s index pattern_length) then
      Some index
    else loop (index + 1)
  in
  if pattern_length = 0 then Some start else loop start

let trim_ascii s =
  let length = String.length s in
  let is_space = function ' ' | '\t' -> true | _ -> false in
  let rec first index =
    if index >= length then length
    else if is_space s.[index] then first (index + 1)
    else index
  in
  let rec last index =
    if index < 0 then -1
    else if is_space s.[index] then last (index - 1)
    else index
  in
  let first = first 0 in
  let last = last (length - 1) in
  if last < first then "" else String.sub s first (last - first + 1)

let split_parameter_sections value =
  let length = String.length value in
  let rec loop sections start index in_quote =
    if index >= length then
      List.rev (String.sub value start (length - start) :: sections)
    else
      match value.[index] with
      | '"' -> loop sections start (index + 1) (not in_quote)
      | ';' when not in_quote ->
          let section = String.sub value start (index - start) in
          loop (section :: sections) (index + 1) (index + 1) in_quote
      | _ -> loop sections start (index + 1) in_quote
  in
  loop [] 0 0 false

let split_parameters value =
  match split_parameter_sections value with
  | [] -> ("", [])
  | media_type :: parameters ->
      let parameters =
        List.filter_map
          (fun parameter ->
            match String.index_opt parameter '=' with
            | None -> None
            | Some index ->
                let name = String.sub parameter 0 index |> trim_ascii in
                let value =
                  String.sub parameter (index + 1)
                    (String.length parameter - index - 1)
                  |> trim_ascii
                in
                let value_length = String.length value in
                let value =
                  if
                    value_length >= 2
                    && Char.equal value.[0] '"'
                    && Char.equal value.[value_length - 1] '"'
                  then String.sub value 1 (value_length - 2)
                  else value
                in
                Some (String.lowercase_ascii name, value))
          parameters
      in
      (media_type |> trim_ascii |> String.lowercase_ascii, parameters)

let parameter name parameters =
  parameters
  |> List.find_opt (fun (candidate, _) -> String.equal name candidate)
  |> Option.map snd

let parse_content_type content_type = split_parameters content_type

let parse_content_disposition headers =
  match Headers.get "content-disposition" headers with
  | None -> (None, None)
  | Some content_disposition ->
      let disposition, parameters = split_parameters content_disposition in
      if String.equal disposition "form-data" then
        (parameter "name" parameters, parameter "filename" parameters)
      else (None, None)

let parse_header_line headers line =
  match String.index_opt line ':' with
  | None -> malformed
  | Some index -> (
      let name = String.sub line 0 index in
      let value =
        String.sub line (index + 1) (String.length line - index - 1)
        |> trim_ascii
      in
      try Ok (Headers.add name value headers)
      with Invalid_argument _ -> malformed)

let parse_headers block =
  if String.equal block "" then Ok Headers.empty
  else
    block |> String.split_on_char '\n'
    |> List.fold_left
         (fun result line ->
           match result with
           | Error _ as error -> error
           | Ok headers ->
               let line =
                 if
                   String.length line > 0
                   && Char.equal line.[String.length line - 1] '\r'
                 then String.sub line 0 (String.length line - 1)
                 else line
               in
               if String.equal line "" then Ok headers
               else parse_header_line headers line)
         (Ok Headers.empty)

let parse_part raw_part =
  match find_sub ~pattern:"\r\n\r\n" raw_part ~start:0 with
  | None -> malformed
  | Some separator -> (
      let header_block = String.sub raw_part 0 separator in
      let body =
        String.sub raw_part (separator + 4)
          (String.length raw_part - separator - 4)
      in
      match parse_headers header_block with
      | Error _ as error -> error
      | Ok headers ->
          let name, filename = parse_content_disposition headers in
          let content_type = Headers.get "content-type" headers in
          Ok
            {
              Part.headers;
              name;
              filename;
              content_type;
              body = Body.string body;
            })

let parse_after_boundary body index =
  if starts_with ~prefix:"--" (substring_from body index) then
    let after_close = index + 2 in
    if String.length body = after_close then Ok (`Close after_close)
    else if starts_with ~prefix:"\r\n" (substring_from body after_close) then
      Ok (`Close (after_close + 2))
    else malformed
  else if starts_with ~prefix:"\r\n" (substring_from body index) then
    Ok (`Part_start (index + 2))
  else malformed

let decode ~boundary body =
  if String.equal boundary "" then Error Missing_boundary
  else
    let delimiter = "--" ^ boundary in
    if not (starts_with ~prefix:delimiter body) then malformed
    else
      match parse_after_boundary body (String.length delimiter) with
      | Error _ as error -> error
      | Ok (`Close _) -> Ok []
      | Ok (`Part_start first_part_start) ->
          let part_delimiter = "\r\n" ^ delimiter in
          let rec loop parts start =
            match find_sub ~pattern:part_delimiter body ~start with
            | None -> malformed
            | Some delimiter_index -> (
                let raw_part =
                  String.sub body start (delimiter_index - start)
                in
                match parse_part raw_part with
                | Error _ as error -> error
                | Ok part -> (
                    let after_delimiter =
                      delimiter_index + String.length part_delimiter
                    in
                    match parse_after_boundary body after_delimiter with
                    | Error _ as error -> error
                    | Ok (`Close close_index) ->
                        if close_index = String.length body then
                          Ok (List.rev (part :: parts))
                        else malformed
                    | Ok (`Part_start next_start) ->
                        loop (part :: parts) next_start))
          in
          loop [] first_part_start

let boundary_of_request request =
  match Headers.get "content-type" (Request.headers request) with
  | None -> Error Missing_content_type
  | Some content_type -> (
      let media_type, parameters = parse_content_type content_type in
      if not (String.equal media_type "multipart/form-data") then
        Error (Unsupported_content_type content_type)
      else
        match parameter "boundary" parameters with
        | None | Some "" -> Error Missing_boundary
        | Some boundary -> Ok boundary)

let of_request request =
  match boundary_of_request request with
  | Error _ as error -> error
  | Ok boundary -> decode ~boundary (Body.to_string (Request.body request))

let of_request_limited ~max_size request =
  if max_size < 0 then invalid_arg "negative max_size";
  match boundary_of_request request with
  | Error _ as error -> error
  | Ok boundary -> (
      match Body.to_string_limited ~max_size (Request.body request) with
      | Ok body -> decode ~boundary body
      | Error Body.Body_too_large -> Error Body_too_large
      | Error Body.Unexpected_end_of_body -> Error Unexpected_end_of_body)

let pp_error formatter = function
  | Missing_content_type ->
      Format.pp_print_string formatter "missing content-type"
  | Unsupported_content_type content_type ->
      Format.fprintf formatter "unsupported content-type: %s" content_type
  | Missing_boundary ->
      Format.pp_print_string formatter "missing multipart boundary"
  | Malformed_body ->
      Format.pp_print_string formatter "malformed multipart body"
  | Body_too_large ->
      Format.pp_print_string formatter "multipart body too large"
  | Unexpected_end_of_body ->
      Format.pp_print_string formatter "unexpected end of multipart body"
