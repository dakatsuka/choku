let is_valid_origin_form target =
  String.length target > 0
  && Char.equal target.[0] '/'
  && not
       (String.exists
          (function '\x00' .. '\x20' | '\x7f' | '#' -> true | _ -> false)
          target)
