open Alcotest

let test_handler_shape () =
  let handler : Choku.Handler.t = fun _ -> Choku.Response.text "ok" in
  let request =
    Choku.Request.make ~meth:Choku.Method.GET ~target:"/"
      ~headers:Choku.Headers.empty ~body:Choku.Body.empty
  in
  check string "body" "ok"
    (Choku.Body.to_string (Choku.Response.body (handler request)))

let () =
  run "handler"
    [ ("handler", [ test_case "handler shape" `Quick test_handler_shape ]) ]
