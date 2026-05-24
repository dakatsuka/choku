open Alcotest

let request =
  Choku.Request.make ~meth:Choku.Method.GET ~target:"/"
    ~headers:Choku.Headers.empty ~body:Choku.Body.empty

let test_apply_order () =
  let events = ref [] in
  let record name next req =
    events := !events @ [ name ^ ":request" ];
    let response = next req in
    events := !events @ [ name ^ ":response" ];
    response
  in
  let handler _ = Choku.Response.text "ok" in
  let wrapped = Choku.Middleware.apply [ record "a"; record "b" ] handler in
  ignore (wrapped request : Choku.Response.t);
  check (list string) "order"
    [ "a:request"; "b:request"; "b:response"; "a:response" ]
    !events

let () =
  run "middleware"
    [ ("middleware", [ test_case "apply order" `Quick test_apply_order ]) ]
