type error = Malformed_percent_encoding

let hex_value = function
  | '0' .. '9' as c -> Some (Char.code c - Char.code '0')
  | 'A' .. 'F' as c -> Some (Char.code c - Char.code 'A' + 10)
  | 'a' .. 'f' as c -> Some (Char.code c - Char.code 'a' + 10)
  | _ -> None

let decode_component component =
  let length = String.length component in
  let buffer = Buffer.create length in
  let rec loop index =
    if index >= length then Ok (Buffer.contents buffer)
    else
      match component.[index] with
      | '+' ->
          Buffer.add_char buffer ' ';
          loop (index + 1)
      | '%' -> (
          if index + 2 >= length then Error Malformed_percent_encoding
          else
            match
              (hex_value component.[index + 1], hex_value component.[index + 2])
            with
            | Some high, Some low ->
                Buffer.add_char buffer (Char.chr ((high * 16) + low));
                loop (index + 3)
            | _ -> Error Malformed_percent_encoding)
      | c ->
          Buffer.add_char buffer c;
          loop (index + 1)
  in
  loop 0

let split_field field =
  match String.index_opt field '=' with
  | None -> (field, "")
  | Some index ->
      let name = String.sub field 0 index in
      let value =
        String.sub field (index + 1) (String.length field - index - 1)
      in
      (name, value)

let decode_field field =
  let name, value = split_field field in
  match decode_component name with
  | Error error -> Error error
  | Ok name -> (
      match decode_component value with
      | Error error -> Error error
      | Ok value -> Ok (name, value))

let decode text =
  if String.equal text "" then Ok []
  else
    text |> String.split_on_char '&'
    |> List.fold_left
         (fun result field ->
           match result with
           | Error _ as error -> error
           | Ok fields -> (
               match decode_field field with
               | Ok field -> Ok (field :: fields)
               | Error _ as error -> error))
         (Ok [])
    |> Result.map List.rev
