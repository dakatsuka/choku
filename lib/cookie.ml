type same_site = Strict | Lax | No_restriction

let trim_optional_whitespace value =
  let length = String.length value in
  let is_ows = function ' ' | '\t' -> true | _ -> false in
  let rec first index =
    if index >= length then length
    else if is_ows value.[index] then first (index + 1)
    else index
  in
  let rec last index =
    if index < 0 then -1
    else if is_ows value.[index] then last (index - 1)
    else index
  in
  let first = first 0 in
  let last = last (length - 1) in
  if last < first then "" else String.sub value first (last - first + 1)

let parse_pair pair =
  let pair = trim_optional_whitespace pair in
  match String.index_opt pair '=' with
  | None -> None
  | Some index ->
      let name = String.sub pair 0 index |> trim_optional_whitespace in
      let value =
        String.sub pair (index + 1) (String.length pair - index - 1)
        |> trim_optional_whitespace
      in
      if Headers.is_valid_name name then Some (name, value) else None

let request_cookies request =
  Request.headers request |> Headers.get_all "cookie"
  |> List.concat_map (fun header ->
      header |> String.split_on_char ';' |> List.filter_map parse_pair)

let get_all name request =
  request_cookies request
  |> List.filter_map (fun (cookie_name, value) ->
      if String.equal name cookie_name then Some value else None)

let get name request =
  match get_all name request with [] -> None | v :: _ -> Some v

let valid_cookie_value value =
  String.length value = 0
  || String.for_all
       (function
         | '\000' .. '\031' | '\127' | ';' | ',' | '"' | '\\' | ' ' -> false
         | _ -> true)
       value

let valid_attribute_value value =
  String.length value > 0
  && String.for_all
       (function
         | '\000' .. '\031' | '\127' | ';' | ',' | ' ' -> false | _ -> true)
       value

let validate_name name =
  if not (Headers.is_valid_name name) then invalid_arg "invalid cookie name"

let validate_value value =
  if not (valid_cookie_value value) then invalid_arg "invalid cookie value"

let validate_path = function
  | None -> ()
  | Some path ->
      if not (valid_attribute_value path) then invalid_arg "invalid cookie path"

let validate_domain = function
  | None -> ()
  | Some domain ->
      if not (valid_attribute_value domain) then
        invalid_arg "invalid cookie domain"

let same_site_value = function
  | Strict -> "Strict"
  | Lax -> "Lax"
  | No_restriction -> "None"

let add_attribute name value attributes =
  match value with
  | None -> attributes
  | Some value -> attributes @ [ name ^ "=" ^ value ]

let cookie_header ?path ?domain ?max_age ?(expires = None) ?(secure = false)
    ?(http_only = false) ?same_site name value =
  validate_name name;
  validate_value value;
  validate_path path;
  validate_domain domain;
  (match same_site with
  | Some No_restriction when not secure ->
      invalid_arg "SameSite=None requires Secure"
  | Some _ | None -> ());
  let attributes =
    [] |> add_attribute "Path" path
    |> add_attribute "Domain" domain
    |> add_attribute "Max-Age" (Option.map string_of_int max_age)
    |> add_attribute "Expires" expires
  in
  let attributes = if secure then attributes @ [ "Secure" ] else attributes in
  let attributes =
    if http_only then attributes @ [ "HttpOnly" ] else attributes
  in
  let attributes =
    match same_site with
    | None -> attributes
    | Some same_site -> attributes @ [ "SameSite=" ^ same_site_value same_site ]
  in
  String.concat "; " ((name ^ "=" ^ value) :: attributes)

let set ?path ?domain ?max_age ?(secure = false) ?(http_only = false) ?same_site
    name value response =
  let header =
    cookie_header ?path ?domain ?max_age ~secure ~http_only ?same_site name
      value
  in
  Response.add_header "set-cookie" header response

let expired = "Thu, 01 Jan 1970 00:00:00 GMT"

let delete ?path ?domain name response =
  let header =
    cookie_header ?path ?domain ~max_age:0 ~expires:(Some expired) name ""
  in
  Response.add_header "set-cookie" header response
