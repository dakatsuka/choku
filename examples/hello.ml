let handler request =
  match Choku.Request.(meth request, path request) with
  | Choku.Method.GET, "/" -> Choku.Response.text "hello from choku\n"
  | Choku.Method.GET, "/health" -> Choku.Response.text "ok\n"
  | _ -> Choku.Response.text ~status:Choku.Status.not_found "not found\n"

let () =
  Eio_main.run @@ fun env ->
  Eio.Switch.run @@ fun sw ->
  let net = Eio.Stdenv.net env in
  let addr = `Tcp (Eio.Net.Ipaddr.V4.loopback, 8080) in
  let server = Choku.Server.create ~handler () in
  Choku.Server.run ~sw ~net ~addr server
