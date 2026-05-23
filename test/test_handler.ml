open Alcotest

let test_handler_shape () =
  let handler : Camelio.Handler.t = fun _ -> Camelio.Response.text "ok" in
  let request =
    Camelio.Request.make ~meth:Camelio.Method.GET ~target:"/"
      ~headers:Camelio.Headers.empty ~body:Camelio.Body.empty
  in
  check string "body" "ok"
    (Camelio.Body.to_string (Camelio.Response.body (handler request)))

let () =
  run "handler"
    [ ("handler", [ test_case "handler shape" `Quick test_handler_shape ]) ]
