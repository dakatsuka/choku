let handler request =
  match Camelio.Request.(meth request, path request) with
  | Camelio.Method.GET, "/" -> Camelio.Response.text "hello from camelio\n"
  | Camelio.Method.GET, "/health" -> Camelio.Response.text "ok\n"
  | _ -> Camelio.Response.text ~status:Camelio.Status.not_found "not found\n"

let () =
  Eio_main.run @@ fun env ->
  Eio.Switch.run @@ fun sw ->
  let net = Eio.Stdenv.net env in
  let addr = `Tcp (Eio.Net.Ipaddr.V4.loopback, 8080) in
  let server = Camelio.Server.create ~handler () in
  Camelio.Server.run ~sw ~net ~addr server
