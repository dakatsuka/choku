open Alcotest

let request ?(headers = Choku.Headers.empty) () =
  Choku.Request.make ~meth:Choku.Method.GET ~target:"/" ~headers
    ~body:Choku.Body.empty

let cookie_headers values =
  List.fold_left
    (fun headers value -> Choku.Headers.add "cookie" value headers)
    Choku.Headers.empty values

let response_cookies response =
  Choku.Headers.get_all "set-cookie" (Choku.Response.headers response)

let test_get_and_get_all () =
  let request =
    request
      ~headers:
        (cookie_headers [ "theme=light; session=one"; "session=two; empty=" ])
      ()
  in
  check (option string) "first session" (Some "one")
    (Choku.Cookie.get "session" request);
  check (list string) "all sessions" [ "one"; "two" ]
    (Choku.Cookie.get_all "session" request);
  check (option string) "empty value" (Some "")
    (Choku.Cookie.get "empty" request)

let test_ignores_malformed_pairs () =
  let request =
    request
      ~headers:
        (cookie_headers
           [
             "valid=ok; missing_equals; =empty-name";
             "bad name=value; other=two";
           ])
      ()
  in
  check (option string) "valid" (Some "ok") (Choku.Cookie.get "valid" request);
  check (option string) "other" (Some "two") (Choku.Cookie.get "other" request);
  check (option string) "bad name" None (Choku.Cookie.get "bad name" request);
  check (option string) "empty name" None (Choku.Cookie.get "" request)

let test_lookup_is_case_sensitive () =
  let request =
    request ~headers:(cookie_headers [ "Session=one; session=two" ]) ()
  in
  check (option string) "uppercase" (Some "one")
    (Choku.Cookie.get "Session" request);
  check (option string) "lowercase" (Some "two")
    (Choku.Cookie.get "session" request)

let test_set_cookie_formats_attributes () =
  let response =
    Choku.Response.text "ok"
    |> Choku.Cookie.set ~path:"/" ~domain:"example.test" ~max_age:3600
         ~secure:true ~http_only:true ~same_site:Choku.Cookie.Lax "session"
         "abc"
  in
  check (list string) "set-cookie"
    [
      "session=abc; Path=/; Domain=example.test; Max-Age=3600; Secure; \
       HttpOnly; SameSite=Lax";
    ]
    (response_cookies response)

let test_set_cookie_preserves_multiple_headers () =
  let response =
    Choku.Response.text "ok" |> Choku.Cookie.set "a" "1"
    |> Choku.Cookie.set "b" "2"
  in
  check (list string) "set-cookie" [ "a=1"; "b=2" ] (response_cookies response)

let test_delete_cookie_expires () =
  let response =
    Choku.Response.text "ok" |> Choku.Cookie.delete ~path:"/" "session"
  in
  check (list string) "delete"
    [ "session=; Path=/; Max-Age=0; Expires=Thu, 01 Jan 1970 00:00:00 GMT" ]
    (response_cookies response)

let test_rejects_unsafe_output () =
  check_raises "bad name" (Invalid_argument "invalid cookie name") (fun () ->
      ignore
        (Choku.Response.text "ok" |> Choku.Cookie.set "bad name" "value"
          : Choku.Response.t));
  check_raises "bad value" (Invalid_argument "invalid cookie value") (fun () ->
      ignore
        (Choku.Response.text "ok" |> Choku.Cookie.set "name" "bad;value"
          : Choku.Response.t));
  check_raises "bad path" (Invalid_argument "invalid cookie path") (fun () ->
      ignore
        (Choku.Response.text "ok"
         |> Choku.Cookie.set ~path:"/bad path" "name" "value"
          : Choku.Response.t));
  check_raises "samesite none requires secure"
    (Invalid_argument "SameSite=None requires Secure") (fun () ->
      ignore
        (Choku.Response.text "ok"
         |> Choku.Cookie.set ~same_site:Choku.Cookie.No_restriction "name"
              "value"
          : Choku.Response.t))

let test_top_level_export () =
  let request = request ~headers:(cookie_headers [ "name=value" ]) () in
  check (option string) "export" (Some "value")
    (Choku.Cookie.get "name" request)

let () =
  run "cookie"
    [
      ( "cookie",
        [
          test_case "get and get_all" `Quick test_get_and_get_all;
          test_case "ignores malformed pairs" `Quick
            test_ignores_malformed_pairs;
          test_case "lookup is case-sensitive" `Quick
            test_lookup_is_case_sensitive;
          test_case "set formats attributes" `Quick
            test_set_cookie_formats_attributes;
          test_case "set preserves multiple headers" `Quick
            test_set_cookie_preserves_multiple_headers;
          test_case "delete expires" `Quick test_delete_cookie_expires;
          test_case "rejects unsafe output" `Quick test_rejects_unsafe_output;
          test_case "top-level export" `Quick test_top_level_export;
        ] );
    ]
