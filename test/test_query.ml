open Alcotest

let request target =
  Choku.Request.make ~meth:Choku.Method.GET ~target ~headers:Choku.Headers.empty
    ~body:Choku.Body.empty

let query_of_string raw_query =
  match Choku.Query.decode raw_query with
  | Ok query -> query
  | Error error ->
      fail
        (Format.asprintf "unexpected query error: %a" Choku.Query.pp_error error)

let check_query raw_query expected =
  check
    (list (pair string string))
    ("query " ^ raw_query) expected
    (Choku.Query.to_list (query_of_string raw_query))

let test_decode_fields () =
  check_query "page=2&filter=open" [ ("page", "2"); ("filter", "open") ]

let test_accessors_preserve_repeated_fields () =
  let query = query_of_string "tag=ocaml&tag=eio&empty=" in
  check (option string) "first tag" (Some "ocaml") (Choku.Query.get "tag" query);
  check (list string) "all tags" [ "ocaml"; "eio" ]
    (Choku.Query.get_all "tag" query);
  check (option string) "missing" None (Choku.Query.get "missing" query);
  check
    (list (pair string string))
    "to_list"
    [ ("tag", "ocaml"); ("tag", "eio"); ("empty", "") ]
    (Choku.Query.to_list query)

let test_empty_query () =
  check
    (list (pair string string))
    "empty" []
    (Choku.Query.to_list Choku.Query.empty);
  check_query "" []

let test_empty_entries_are_preserved () =
  check_query "&" [ ("", ""); ("", "") ];
  check_query "&&" [ ("", ""); ("", ""); ("", "") ];
  check_query "a&" [ ("a", ""); ("", "") ];
  check_query "a&&b" [ ("a", ""); ("", ""); ("b", "") ]

let test_empty_names_values_and_missing_equals () =
  check_query "=value&name=&flag" [ ("", "value"); ("name", ""); ("flag", "") ]

let test_decoding () =
  check_query "q=hello+world&path=%2Fusers%2F42"
    [ ("q", "hello world"); ("path", "/users/42") ]

let test_decoded_controls_are_preserved () =
  check_query "nul=%00&lf=%0A&space=%20"
    [ ("nul", "\x00"); ("lf", "\n"); ("space", " ") ]

let test_leading_question_mark_is_literal () =
  check_query "?page=1" [ ("?page", "1") ]

let test_malformed_percent_encoding () =
  List.iter
    (fun raw_query ->
      check (result reject pass) ("malformed " ^ raw_query)
        (Error Choku.Query.Malformed_percent_encoding)
        (Choku.Query.decode raw_query))
    [ "%"; "%1"; "%zz"; "a=%"; "%zz=bad"; "a=b%zz" ]

let test_of_request () =
  let query = Choku.Query.of_request (request "/items?page=2&tag=ocaml") in
  check
    (result (list (pair string string)) reject)
    "request query"
    (Ok [ ("page", "2"); ("tag", "ocaml") ])
    (Result.map Choku.Query.to_list query)

let test_of_request_without_query () =
  let query = Choku.Query.of_request (request "/items") in
  check
    (result (list (pair string string)) reject)
    "no query" (Ok [])
    (Result.map Choku.Query.to_list query)

let test_of_request_empty_query () =
  let query = Choku.Query.of_request (request "/items?") in
  check
    (result (list (pair string string)) reject)
    "empty query" (Ok [])
    (Result.map Choku.Query.to_list query)

let test_of_request_malformed_query () =
  check (result reject pass) "malformed query"
    (Error Choku.Query.Malformed_percent_encoding)
    (Choku.Query.of_request (request "/items?bad=%zz"))

let test_pp_error () =
  check string "malformed" "malformed percent encoding"
    (Format.asprintf "%a" Choku.Query.pp_error
       Choku.Query.Malformed_percent_encoding)

let () =
  run "query"
    [
      ( "query",
        [
          test_case "decode fields" `Quick test_decode_fields;
          test_case "accessors preserve repeated fields" `Quick
            test_accessors_preserve_repeated_fields;
          test_case "empty query" `Quick test_empty_query;
          test_case "empty entries are preserved" `Quick
            test_empty_entries_are_preserved;
          test_case "empty names values and missing equals" `Quick
            test_empty_names_values_and_missing_equals;
          test_case "decoding" `Quick test_decoding;
          test_case "decoded controls are preserved" `Quick
            test_decoded_controls_are_preserved;
          test_case "leading question mark is literal" `Quick
            test_leading_question_mark_is_literal;
          test_case "malformed percent encoding" `Quick
            test_malformed_percent_encoding;
          test_case "of_request" `Quick test_of_request;
          test_case "of_request without query" `Quick
            test_of_request_without_query;
          test_case "of_request empty query" `Quick test_of_request_empty_query;
          test_case "of_request malformed query" `Quick
            test_of_request_malformed_query;
          test_case "pp_error" `Quick test_pp_error;
        ] );
    ]
