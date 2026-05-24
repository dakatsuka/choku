open Alcotest

let request ?content_type body =
  let headers =
    match content_type with
    | None -> Choku.Headers.empty
    | Some value -> Choku.Headers.add "content-type" value Choku.Headers.empty
  in
  Choku.Request.make ~meth:Choku.Method.POST ~target:"/submit" ~headers
    ~body:(Choku.Body.string body)

let form_fields = list (pair string string)
let form_result = result form_fields reject

let decode_to_list body =
  Choku.Form.decode body |> Result.map Choku.Form.to_list

let of_request_to_list request =
  Choku.Form.of_request request |> Result.map Choku.Form.to_list

let test_decode_fields () =
  check form_result "fields"
    (Ok [ ("name", "Ada Lovelace"); ("city", "Tokyo") ])
    (decode_to_list "name=Ada+Lovelace&city=Tokyo")

let test_percent_decoding () =
  check form_result "fields"
    (Ok [ ("symbol", "+&="); ("space", " ") ])
    (decode_to_list "symbol=%2B%26%3D&space=+")

let test_repeated_fields_preserve_order () =
  let form =
    match Choku.Form.decode "tag=ocaml&tag=eio&single=one" with
    | Ok form -> form
    | Error _ -> fail "expected form"
  in
  check (option string) "first tag" (Some "ocaml") (Choku.Form.get "tag" form);
  check (list string) "all tags" [ "ocaml"; "eio" ]
    (Choku.Form.get_all "tag" form);
  check form_fields "ordered fields"
    [ ("tag", "ocaml"); ("tag", "eio"); ("single", "one") ]
    (Choku.Form.to_list form)

let test_empty_names_values_and_missing_equals () =
  check form_result "fields"
    (Ok [ ("", "empty-name"); ("flag", ""); ("empty", "") ])
    (decode_to_list "=empty-name&flag&empty=")

let test_empty_body () = check form_result "fields" (Ok []) (decode_to_list "")

let test_malformed_percent_encoding () =
  List.iter
    (fun body ->
      check
        (result form_fields (of_pp Choku.Form.pp_error))
        ("malformed " ^ body) (Error Choku.Form.Malformed_percent_encoding)
        (decode_to_list body))
    [ "name=%"; "name=%2"; "name=%GG" ]

let test_of_request_accepts_urlencoded_content_type () =
  let request =
    request ~content_type:"Application/X-Www-Form-Urlencoded; charset=utf-8"
      "name=Ada"
  in
  check form_result "fields"
    (Ok [ ("name", "Ada") ])
    (of_request_to_list request)

let test_of_request_rejects_missing_content_type () =
  check
    (result form_fields (of_pp Choku.Form.pp_error))
    "missing content type" (Error Choku.Form.Missing_content_type)
    (of_request_to_list (request "name=Ada"))

let test_of_request_rejects_unsupported_content_type () =
  check
    (result form_fields (of_pp Choku.Form.pp_error))
    "unsupported content type"
    (Error (Choku.Form.Unsupported_content_type "application/json"))
    (of_request_to_list
       (request ~content_type:"application/json" "{\"name\":\"Ada\"}"))

let test_pp_error () =
  check string "missing" "missing content-type"
    (Format.asprintf "%a" Choku.Form.pp_error Choku.Form.Missing_content_type);
  check string "unsupported" "unsupported content-type: text/plain"
    (Format.asprintf "%a" Choku.Form.pp_error
       (Choku.Form.Unsupported_content_type "text/plain"));
  check string "malformed" "malformed percent encoding"
    (Format.asprintf "%a" Choku.Form.pp_error
       Choku.Form.Malformed_percent_encoding)

let () =
  run "form"
    [
      ( "form",
        [
          test_case "decode fields" `Quick test_decode_fields;
          test_case "percent decoding" `Quick test_percent_decoding;
          test_case "repeated fields preserve order" `Quick
            test_repeated_fields_preserve_order;
          test_case "empty names values and missing equals" `Quick
            test_empty_names_values_and_missing_equals;
          test_case "empty body" `Quick test_empty_body;
          test_case "malformed percent encoding" `Quick
            test_malformed_percent_encoding;
          test_case "of_request accepts urlencoded content-type" `Quick
            test_of_request_accepts_urlencoded_content_type;
          test_case "of_request rejects missing content-type" `Quick
            test_of_request_rejects_missing_content_type;
          test_case "of_request rejects unsupported content-type" `Quick
            test_of_request_rejects_unsupported_content_type;
          test_case "pp_error" `Quick test_pp_error;
        ] );
    ]
