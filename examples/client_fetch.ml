let fetch url =
  Eio_main.run @@ fun env ->
  Eio.Switch.run @@ fun sw ->
  let open Choku in
  let net = Eio.Stdenv.net env in
  let client = Client.create ~net () in
  match Client.Request.make ~meth:Method.GET ~url () with
  | Error error -> Error error
  | Ok request -> Client.request ~sw client request

let () =
  Mirage_crypto_rng_unix.use_default ();
  let url =
    if Array.length Sys.argv > 1 then Sys.argv.(1) else "https://example.com/"
  in
  match fetch url with
  | Error error ->
      Format.eprintf "error: %a@." Choku.Client.Error.pp error;
      exit 1
  | Ok response ->
      Format.printf "status: %d, body bytes: %d@."
        (Choku.Status.code (Choku.Client.Response.status response))
        (String.length
           (Choku.Body.to_string (Choku.Client.Response.body response)))
