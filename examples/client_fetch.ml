let fetch url =
  Eio_main.run @@ fun env ->
  Eio.Switch.run @@ fun sw ->
  let open Choku in
  let net = Eio.Stdenv.net env in
  let client = Client.create ~net () in
  Client.get ~sw client ~url ()

let print_headers headers =
  headers |> Choku.Headers.to_list
  |> List.iter (fun (name, value) -> Format.printf "%s: %s@." name value)

let () =
  let show_headers = ref false in
  let show_body = ref false in
  let url = ref None in
  let set_url value =
    match !url with
    | None -> url := Some value
    | Some _ -> raise (Arg.Bad "only one URL argument may be provided")
  in
  let usage =
    "Usage: client_fetch [--headers] [--body] [URL]\n\
     Fetch URL, defaulting to https://example.com/."
  in
  let specs =
    [
      ( "--headers",
        Arg.Set show_headers,
        " Print response headers after the summary" );
      ("--body", Arg.Set show_body, " Print the response body");
    ]
  in
  Arg.parse specs set_url usage;
  Mirage_crypto_rng_unix.use_default ();
  let url = Option.value !url ~default:"https://example.com/" in
  match fetch url with
  | Error error ->
      Format.eprintf "error: %a@." Choku.Client.Error.pp error;
      exit 1
  | Ok response ->
      let body = Choku.Body.to_string (Choku.Client.Response.body response) in
      Format.printf "status: %d, body bytes: %d@."
        (Choku.Status.code (Choku.Client.Response.status response))
        (String.length body);
      if !show_headers then (
        Format.printf "@[<v>headers:@,";
        print_headers (Choku.Client.Response.headers response);
        Format.printf "@]@.");
      if !show_body then Format.printf "@[<v>body:@,%s@]@." body
