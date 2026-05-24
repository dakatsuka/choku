let response_for_multipart_error error =
  Choku.Response.text ~status:Choku.Status.bad_request
    (Format.asprintf "%a\n" Choku.Multipart.pp_error error)

let basename path =
  match Eio.Path.split path with None -> "" | Some (_, basename) -> basename

let drain source =
  let scratch = Cstruct.create 8192 in
  let rec loop () =
    match Eio.Flow.single_read source scratch with
    | exception End_of_file -> ()
    | _ -> loop ()
  in
  loop ()

let upload ~upload_dir ~random request =
  let files = ref [] in
  match
    Choku.Multipart.Streaming.iter_request request ~on_part:(fun part source ->
        match Choku.Multipart.Streaming.filename part with
        | None -> drain source
        | Some filename ->
            let saved =
              Choku.Multipart.Tempfile.save_source ~dir:upload_dir ~random
                ~original_filename:filename source
            in
            let filename =
              Choku.Multipart.Tempfile.display_filename saved
              |> Option.value ~default:"upload"
            in
            files :=
              ( filename,
                Choku.Multipart.Tempfile.size saved,
                basename (Choku.Multipart.Tempfile.path saved) )
              :: !files)
  with
  | Error error -> response_for_multipart_error error
  | Ok () ->
      let lines =
        !files |> List.rev
        |> List.map (fun (filename, bytes, storage_name) ->
            Printf.sprintf "%s %d bytes stored as %s\n" filename bytes
              storage_name)
        |> String.concat ""
      in
      Choku.Response.text lines

let handler ~upload_dir ~random request =
  match Choku.Request.(meth request, path request) with
  | Choku.Method.POST, "/upload" -> upload ~upload_dir ~random request
  | Choku.Method.GET, "/health" -> Choku.Response.text "ok\n"
  | _ -> Choku.Response.text ~status:Choku.Status.not_found "not found\n"

let () =
  Eio_main.run @@ fun env ->
  Eio.Switch.run @@ fun sw ->
  let net = Eio.Stdenv.net env in
  let upload_dir = Eio.Path.(Eio.Stdenv.cwd env / "_choku_uploads") in
  Eio.Path.mkdirs ~exists_ok:true ~perm:0o700 upload_dir;
  let random = Eio.Stdenv.secure_random env in
  let addr = `Tcp (Eio.Net.Ipaddr.V4.loopback, 8080) in
  let server =
    Choku.Server.create ~request_body_mode:Choku.Server.Streaming
      ~handler:(handler ~upload_dir ~random)
      ()
  in
  Choku.Server.run ~sw ~net ~addr server
