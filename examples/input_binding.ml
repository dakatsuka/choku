module Result_syntax = struct
  let ( let* ) = Result.bind
  let ( let+ ) value f = Result.map f value
end

type search_request = {
  user_id : string;
  page : string;
  query : string;
  csrf : string;
}

type input_error =
  | Query_error of Choku.Query.error
  | Form_error of Choku.Form.error
  | Missing of string

let require name = function
  | Some value -> Ok value
  | None -> Error (Missing name)

let required_values (ctx : Choku.Router.Context.t) =
  let open Result_syntax in
  let* query_params =
    Choku.Query.of_request ctx.request
    |> Result.map_error (fun error -> Query_error error)
  in
  let* form =
    Choku.Form.of_request ctx.request
    |> Result.map_error (fun error -> Form_error error)
  in
  let* user_id = Choku.Router.Params.get "id" ctx.params |> require "id" in
  let* page = Choku.Query.get "page" query_params |> require "page" in
  let* query = Choku.Query.get "q" query_params |> require "q" in
  let+ csrf = Choku.Form.get "csrf" form |> require "csrf" in
  { user_id; page; query; csrf }

let pp_input_error formatter = function
  | Query_error error -> Choku.Query.pp_error formatter error
  | Form_error error -> Choku.Form.pp_error formatter error
  | Missing name -> Format.fprintf formatter "missing required input: %s" name

let bad_request body = Choku.Response.text ~status:Choku.Status.bad_request body

let search ctx =
  match required_values ctx with
  | Error error -> bad_request (Format.asprintf "%a\n" pp_input_error error)
  | Ok values ->
      Choku.Response.text
        (Printf.sprintf "user=%s page=%s q=%s csrf=%s\n" values.user_id
           values.page values.query values.csrf)

let router =
  Choku.Router.empty
  |> Choku.Router.get "/" (fun _ctx ->
      Choku.Response.text
        "curl -X POST 'http://127.0.0.1:8080/users/42/search?page=1&q=ocaml' \
         -H 'Content-Type: application/x-www-form-urlencoded' --data \
         'csrf=token'\n")
  |> Choku.Router.post "/users/:id/search" search

let () =
  Eio_main.run @@ fun env ->
  Eio.Switch.run @@ fun sw ->
  let net = Eio.Stdenv.net env in
  let addr = `Tcp (Eio.Net.Ipaddr.V4.loopback, 8080) in
  let server = Choku.Server.create_router router in
  Choku.Server.run ~sw ~net ~addr server
