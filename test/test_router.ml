open Alcotest

let request ?(meth = Camelio.Method.GET) target =
  Camelio.Request.make ~meth ~target ~headers:Camelio.Headers.empty
    ~body:Camelio.Body.empty

let response_body response =
  Camelio.Body.to_string (Camelio.Response.body response)

let response_code response =
  Camelio.Status.code (Camelio.Response.status response)

let call router ?meth target =
  Camelio.Router.to_handler router (request ?meth target)

let text body _params _request = Camelio.Response.text body

let test_static_route_matches () =
  let router =
    Camelio.Router.empty |> Camelio.Router.get "/health" (text "ok")
  in
  check string "body" "ok" (response_body (call router "/health"))

let test_method_must_match () =
  let router =
    Camelio.Router.empty |> Camelio.Router.post "/submit" (text "ok")
  in
  let response = call router "/submit" in
  check int "status" 404 (response_code response);
  check string "body" "Not Found\n" (response_body response)

let test_first_registered_route_wins () =
  let router =
    Camelio.Router.empty
    |> Camelio.Router.get "/users/:id" (fun _params _request ->
        Camelio.Response.text "param")
    |> Camelio.Router.get "/users/me" (text "static")
  in
  check string "body" "param" (response_body (call router "/users/me"))

let test_parameter_capture () =
  let router =
    Camelio.Router.empty
    |> Camelio.Router.get "/users/:id/posts/:post-id" (fun params _request ->
        let id =
          Option.value ~default:"missing"
            (Camelio.Router.Params.get "id" params)
        in
        let post_id =
          Option.value ~default:"missing"
            (Camelio.Router.Params.get "post-id" params)
        in
        Camelio.Response.text (id ^ ":" ^ post_id))
  in
  check string "body" "42:abc"
    (response_body (call router "/users/42/posts/abc"))

let test_params_to_list_preserves_pattern_order () =
  let router =
    Camelio.Router.empty
    |> Camelio.Router.get "/:first/:second" (fun params _request ->
        check
          (list (pair string string))
          "params"
          [ ("first", "one"); ("second", "two") ]
          (Camelio.Router.Params.to_list params);
        Camelio.Response.text "ok")
  in
  check string "body" "ok" (response_body (call router "/one/two"))

let test_query_string_is_ignored () =
  let router =
    Camelio.Router.empty |> Camelio.Router.get "/search" (text "ok")
  in
  check string "body" "ok" (response_body (call router "/search?q=camelio"))

let test_custom_not_found () =
  let router =
    Camelio.Router.empty
    |> Camelio.Router.not_found (fun _request ->
        Camelio.Response.text ~status:Camelio.Status.bad_request "missing")
  in
  let response = call router "/missing" in
  check int "status" 400 (response_code response);
  check string "body" "missing" (response_body response)

let test_root_route_matches_only_root () =
  let router = Camelio.Router.empty |> Camelio.Router.get "/" (text "root") in
  check string "root body" "root" (response_body (call router "/"));
  check int "non-root status" 404 (response_code (call router "/other"))

let test_convenience_methods () =
  let router =
    Camelio.Router.empty
    |> Camelio.Router.get "/get" (text "get")
    |> Camelio.Router.put "/put" (text "put")
    |> Camelio.Router.patch "/patch" (text "patch")
    |> Camelio.Router.delete "/delete" (text "delete")
    |> Camelio.Router.options "/options" (text "options")
  in
  check string "get" "get" (response_body (call router "/get"));
  check string "put" "put"
    (response_body (call router ~meth:Camelio.Method.PUT "/put"));
  check string "patch" "patch"
    (response_body (call router ~meth:Camelio.Method.PATCH "/patch"));
  check string "delete" "delete"
    (response_body (call router ~meth:Camelio.Method.DELETE "/delete"));
  check string "options" "options"
    (response_body (call router ~meth:Camelio.Method.OPTIONS "/options"))

let test_generic_route_supports_custom_method () =
  let meth = Camelio.Method.Other "PROPFIND" in
  let router =
    Camelio.Router.empty
    |> Camelio.Router.route meth "/collection" (text "custom")
  in
  check string "body" "custom" (response_body (call router ~meth "/collection"))

let check_invalid_pattern pattern =
  check_raises ("invalid " ^ pattern) (Invalid_argument "invalid route pattern")
    (fun () ->
      ignore
        (Camelio.Router.empty |> Camelio.Router.get pattern (text "unreachable")
          : Camelio.Router.t))

let test_invalid_patterns () =
  List.iter check_invalid_pattern
    [ ""; "users"; "/users/"; "/users//posts"; "/:"; "/:1"; "/:-bad"; "/:a/:a" ]

let () =
  run "router"
    [
      ( "router",
        [
          test_case "static route matches" `Quick test_static_route_matches;
          test_case "method must match" `Quick test_method_must_match;
          test_case "first registered route wins" `Quick
            test_first_registered_route_wins;
          test_case "parameter capture" `Quick test_parameter_capture;
          test_case "params to_list preserves order" `Quick
            test_params_to_list_preserves_pattern_order;
          test_case "query string is ignored" `Quick
            test_query_string_is_ignored;
          test_case "custom not found" `Quick test_custom_not_found;
          test_case "root route matches only root" `Quick
            test_root_route_matches_only_root;
          test_case "convenience methods" `Quick test_convenience_methods;
          test_case "generic route supports custom method" `Quick
            test_generic_route_supports_custom_method;
          test_case "invalid patterns" `Quick test_invalid_patterns;
        ] );
    ]
