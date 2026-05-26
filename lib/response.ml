[@@@alert "-internal"]

type t = { status : Status.t; headers : Headers.t; body : Body.t }

let make ?(headers = Headers.empty) ?(body = Body.empty) status =
  { status; headers; body }

let text ?(status = Status.ok) body =
  make status ~body:(Body.string body)
    ~headers:
      (Headers.set "content-type" "text/plain; charset=utf-8" Headers.empty)

let stream ?(status = Status.ok) ?(headers = Headers.empty) ?content_length
    write =
  (match content_length with
  | Some content_length when content_length < 0 ->
      invalid_arg "negative content_length"
  | Some _ | None -> ());
  make status ~headers ~body:(Body.Internal.writer ?content_length write)

let status t = t.status
let headers t = t.headers
let body t = t.body

let with_header name value t =
  { t with headers = Headers.set name value t.headers }

let add_header name value t =
  { t with headers = Headers.add name value t.headers }
