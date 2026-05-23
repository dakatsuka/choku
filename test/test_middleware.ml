open Alcotest

let request =
  Camelio.Request.make ~meth:Camelio.Method.GET ~target:"/"
    ~headers:Camelio.Headers.empty ~body:Camelio.Body.empty

let test_apply_order () =
  let events = ref [] in
  let record name next req =
    events := !events @ [ name ^ ":request" ];
    let response = next req in
    events := !events @ [ name ^ ":response" ];
    response
  in
  let handler _ = Camelio.Response.text "ok" in
  let wrapped = Camelio.Middleware.apply [ record "a"; record "b" ] handler in
  ignore (wrapped request : Camelio.Response.t);
  check (list string) "order"
    [ "a:request"; "b:request"; "b:response"; "a:response" ]
    !events

let () =
  run "middleware"
    [ ("middleware", [ test_case "apply order" `Quick test_apply_order ]) ]
