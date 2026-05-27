# Server Cookie Support

## Status

Accepted

## Problem

Handlers commonly need to read request cookies and emit one or more
`Set-Cookie` response headers. Choku already exposes raw headers, but direct
header handling makes cookie parsing repetitive and `Response.with_header`
cannot safely emit multiple `Set-Cookie` fields because it replaces existing
fields through `Headers.set`.

## Goals

- Provide a small server-side `Choku.Cookie` module for request cookie lookup
  and response cookie writing.
- Preserve Choku's explicit handler and middleware model.
- Support multiple `Set-Cookie` response fields.
- Keep cookie parsing and formatting deterministic and testable.
- Avoid global state, sessions, signing, encryption, or a browser-like cookie
  store.

## Non-Goals

- Client-side cookie jars.
- Session storage.
- Signed or encrypted cookies.
- CSRF protection.
- Browser-compatible cookie storage policy.
- Public suffix list handling.
- Automatic domain, path, `Secure`, `HttpOnly`, or `SameSite` defaults.
- Middleware that rewrites application cookies.
- Full RFC 6265 validation beyond the narrow contracts required for safe
  header generation.

## Requirements

- Add `Response.add_header name value response`.
- `Response.add_header` appends a response header using `Headers.add`; unlike
  `Response.with_header`, it does not remove existing fields with the same
  name.
- `Response.add_header` raises `Invalid_argument` under the same header name
  and value validation rules as `Headers.add`.
- `Cookie.get name request` returns the first cookie value named `name` from
  the request's `Cookie` headers.
- `Cookie.get_all name request` returns all cookie values named `name` in
  request header order and cookie-pair order.
- `Cookie.get_unique name request` returns a value only when exactly one cookie
  named `name` is present.
- Security-sensitive cookies such as authentication or session cookies should
  use `Cookie.get_unique` or explicit `Cookie.get_all` duplicate handling,
  because duplicate names can appear in cookie tossing and session fixation
  scenarios.
- Cookie lookup is case-sensitive.
- Request cookie parsing reads all `Cookie` headers from `Request.headers`.
- Request cookie parsing splits header values on `;`, trims optional spaces and
  tabs around each cookie pair, and ignores empty pairs.
- A cookie pair without `=` is ignored.
- A cookie pair with an empty name is ignored.
- A cookie pair whose name is not a valid HTTP token is ignored.
- A cookie pair with an empty value is preserved.
- Cookie values are returned as header bytes after trimming outer optional
  whitespace. Choku does not percent-decode, UTF-8 validate, unquote, or
  otherwise transform cookie values.
- Malformed request cookie pairs are ignored rather than raising.
- `Cookie.set` appends one `Set-Cookie` header to a response.
- `Cookie.set` validates the cookie name as an HTTP token.
- `Cookie.set` rejects cookie values and attributes that cannot be safely
  serialized as a `Set-Cookie` header value.
- `Cookie.set` supports `Path`, `Domain`, `Max-Age`, `Secure`, `HttpOnly`, and
  `SameSite`.
- `SameSite` values are `Strict`, `Lax`, and `No_restriction`, where
  `No_restriction` serializes as `SameSite=None`.
- `Cookie.set ~same_site:No_restriction` requires `~secure:true` and raises
  `Invalid_argument` otherwise.
- `Path` and `Domain` validation only prevents unsafe header serialization. It
  does not guarantee that a user agent will store or send the cookie.
- `Cookie.delete` appends an expired `Set-Cookie` header for a cookie name,
  preserving optional `Path` and `Domain` so applications can target the cookie
  they originally set.
- `Cookie.delete` emits both `Max-Age=0` and
  `Expires=Thu, 01 Jan 1970 00:00:00 GMT` for compatibility.
- `Cookie.set` and `Cookie.delete` use `Response.add_header`, not
  `Response.with_header`, so repeated calls preserve multiple `Set-Cookie`
  fields.

## Public Contracts

Initial contracts:

```ocaml
module Response : sig
  val add_header : string -> string -> t -> t
end

module Cookie : sig
  type same_site = Strict | Lax | No_restriction

  val get : string -> Request.t -> string option
  val get_all : string -> Request.t -> string list
  val get_unique : string -> Request.t -> string option

  val set :
    ?path:string ->
    ?domain:string ->
    ?max_age:int ->
    ?secure:bool ->
    ?http_only:bool ->
    ?same_site:same_site ->
    string ->
    string ->
    Response.t ->
    Response.t

  val delete :
    ?path:string ->
    ?domain:string ->
    string ->
    Response.t ->
    Response.t
end
```

Public `.mli` files must document these contracts with block comments.

## Examples

```ocaml
let handler request =
  match Choku.Cookie.get_unique "user_id" request with
  | None ->
      Choku.Response.text ~status:Choku.Status.unauthorized
        "missing or ambiguous cookie\n"
  | Some user_id ->
      Choku.Response.text ("hello " ^ user_id ^ "\n")
      |> Choku.Cookie.set ~path:"/" ~secure:true ~http_only:true
           ~same_site:Choku.Cookie.Lax "seen" "1"
```

Set multiple cookies:

```ocaml
Choku.Response.text "ok\n"
|> Choku.Cookie.set "a" "1"
|> Choku.Cookie.set "b" "2"
```

Delete a cookie:

```ocaml
Choku.Response.text "signed out\n"
|> Choku.Cookie.delete ~path:"/" "session"
```

## Open Questions

- Should Choku support quoted cookie values in a later milestone, or keep values
  as an opaque safe header-value subset?
