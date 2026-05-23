type t = { status : Status.t; headers : Headers.t; body : Body.t }

let make ?(headers = Headers.empty) ?(body = Body.empty) status =
  { status; headers; body }

let text ?(status = Status.ok) body =
  make status ~body:(Body.string body)
    ~headers:
      (Headers.set "content-type" "text/plain; charset=utf-8" Headers.empty)

let status t = t.status
let headers t = t.headers
let body t = t.body

let with_header name value t =
  { t with headers = Headers.set name value t.headers }
