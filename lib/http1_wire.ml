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
