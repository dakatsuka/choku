let response_for_multipart_error error =
  Camelio.Response.text ~status:Camelio.Status.bad_request
    (Format.asprintf "%a\n" Camelio.Multipart.pp_error error)

let count_source source =
  let scratch = Cstruct.create 8192 in
  let rec loop total =
    match Eio.Flow.single_read source scratch with
    | exception End_of_file -> total
    | read -> loop (total + read)
  in
  loop 0

let upload request =
  let files = ref [] in
  match
    Camelio.Multipart.Streaming.iter_request request
      ~on_part:(fun part source ->
        match Camelio.Multipart.Streaming.filename part with
        | None -> Eio.Flow.copy source (Eio.Flow.buffer_sink (Buffer.create 0))
        | Some filename ->
            let bytes = count_source source in
            files := (filename, bytes) :: !files)
  with
  | Error error -> response_for_multipart_error error
  | Ok () ->
      let lines =
        !files |> List.rev
        |> List.map (fun (filename, bytes) ->
            Printf.sprintf "%s %d bytes\n" filename bytes)
        |> String.concat ""
      in
      Camelio.Response.text lines

let handler request =
  match Camelio.Request.(meth request, path request) with
  | Camelio.Method.POST, "/upload" -> upload request
  | Camelio.Method.GET, "/health" -> Camelio.Response.text "ok\n"
  | _ -> Camelio.Response.text ~status:Camelio.Status.not_found "not found\n"

let () =
  Eio_main.run @@ fun env ->
  Eio.Switch.run @@ fun sw ->
  let net = Eio.Stdenv.net env in
  let addr = `Tcp (Eio.Net.Ipaddr.V4.loopback, 8080) in
  let server =
    Camelio.Server.create ~request_body_mode:Camelio.Server.Streaming ~handler
      ()
  in
  Camelio.Server.run ~sw ~net ~addr server
