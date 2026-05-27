# Server Cookie Support

## Status

Accepted

## Context

Choku server handlers can already inspect raw request headers and set response
headers. The current response helper `Response.with_header` uses `Headers.set`,
which is correct for singleton-like headers but not for `Set-Cookie`, where
applications often need multiple fields with the same name.

Cookie support should therefore start as small value-level helpers rather than
middleware. Choku does not currently have a request attribute context where
middleware could attach parsed cookies for downstream handlers, and a middleware
that rewrites `Set-Cookie` headers would create surprising policy ownership.

Relevant local documents:

- [Server Cookie Support Product Spec](../product-specs/server-cookie-support.md)
- [Minimal Server API](../product-specs/minimal-server-api.md)
- [Minimal Server, Handler, and Middleware API](minimal-server-handler-middleware-api.md)

## Goals

- Add `Response.add_header` as the general append counterpart to
  `Response.with_header`.
- Add a `Choku.Cookie` module for server-side request cookie lookup and
  response cookie writing.
- Keep cookie helpers deterministic, explicit, and test-covered.
- Avoid sessions, signing, encryption, global state, or automatic defaults.

## Non-Goals

- Client cookie jars.
- Middleware-managed cookie policy.
- Session management.
- Signed or encrypted cookies.
- CSRF protection.
- Public suffix handling or browser storage policy.
- Full RFC 6265 compliance in the first helper.

## Proposed Design

Add `Response.add_header`:

```ocaml
val add_header : string -> string -> Response.t -> Response.t
```

`add_header name value response` returns `response` with `(name, value)`
appended using `Headers.add`. It raises `Invalid_argument` when `Headers.add`
would reject the name or value. `Response.with_header` keeps its existing
replacement semantics through `Headers.set`.

Add a new top-level `Choku.Cookie` module:

```ocaml
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

## Request Cookie Parsing

`Cookie.get_all name request` reads `Headers.get_all "cookie"` from the
request. It processes header values in insertion order. Each header value is
split on `;`; each pair is trimmed for ASCII space and tab on both sides.

`Cookie.get name request` returns the first matching value. This is a
convenience for non-sensitive cookies where first-value semantics are
acceptable. Security-sensitive cookies such as authentication or session
cookies should use `Cookie.get_unique` or explicit `Cookie.get_all` duplicate
handling so duplicate names are rejected instead of silently choosing one.

Parsing rules:

- empty pairs are ignored;
- pairs without `=` are ignored;
- pairs with an empty name are ignored;
- pairs whose names are not valid HTTP tokens according to
  `Headers.is_valid_name` are ignored;
- names are not percent-decoded, lowercased, or otherwise normalized;
- lookup is case-sensitive;
- the value is the text after the first `=`, trimmed for outer ASCII space and
  tab;
- empty values are present values;
- malformed pairs are ignored and do not reject the request.

This keeps request cookie lookup usable for ordinary handlers without making
cookie parsing a request validation step.

## Set-Cookie Formatting

`Cookie.set` formats one `Set-Cookie` header and appends it with
`Response.add_header`.

Cookie name validation should use `Headers.is_valid_name`, because cookie names
use the HTTP token shape. Cookie values should be restricted to a safe unquoted
subset for the first helper: reject control bytes, semicolon, comma, double
quote, backslash, and ASCII whitespace. Attribute values for `Path` and
`Domain` should reject control bytes, semicolon, comma, and whitespace that
would make the serialized header ambiguous.

`Domain` and `Path` validation is only a header-serialization safety check. It
does not implement browser storage policy and does not guarantee that any user
agent will store or return the cookie.

The serialized attribute order is stable:

1. `Path`
2. `Domain`
3. `Max-Age`
4. `Expires`
5. `Secure`
6. `HttpOnly`
7. `SameSite`

`Max-Age` accepts any `int` and serializes with `string_of_int`. Applications
can pass `0` or a negative value when intentionally expiring a cookie, but
`Cookie.delete` is the preferred clearer helper for deletion.

`SameSite` serializes as `Strict`, `Lax`, or `None`. The OCaml constructor for
`SameSite=None` is `No_restriction` to avoid shadowing option `None` in opened
modules. Modern browsers reject `SameSite=None` cookies without `Secure`, so
`Cookie.set ~same_site:No_restriction` requires `~secure:true` and raises
`Invalid_argument` otherwise.

`Cookie.delete ?path ?domain name response` appends a `Set-Cookie` header with
an empty value, `Max-Age=0`, and
`Expires=Thu, 01 Jan 1970 00:00:00 GMT`. The helper includes `Path` and
`Domain` only when provided.

## Contracts

- `Response.add_header` appends; `Response.with_header` replaces.
- `Cookie.get` is `List.hd`-like over `Cookie.get_all` but returns `None` when
  no matching cookie exists.
- `Cookie.get_unique` returns `Some value` only when exactly one matching cookie
  exists.
- `Cookie.get_all` never raises for malformed request cookie syntax.
- `Cookie.set` and `Cookie.delete` may raise `Invalid_argument` for invalid
  names or unsafe response cookie values/attributes.
- `Cookie.set` and `Cookie.delete` never remove existing `Set-Cookie` fields.

## Alternatives Considered

- Built-in cookie middleware: deferred because there is no request context for
  attaching parsed cookies, and response-cookie policy should stay explicit.
- Use `Response.with_header "set-cookie"` for cookies: rejected because it
  would replace earlier cookies and lose valid repeated fields.
- Add signed or encrypted cookies now: rejected because key management and
  cryptographic policy belong in a separate design.
- Fully validate request cookies and reject malformed input: rejected because
  cookies are often user-agent-owned ambient input and handlers should decide
  whether malformed or missing cookies matter.

## Third-Party Review

Initial context-free review found six issues:

- `SameSite=None` without `Secure` creates cookies modern browsers reject;
- deletion behavior needed a concrete `Expires` decision;
- malformed request-cookie name handling was underspecified;
- the original `None` constructor for `SameSite=None` could confuse users who
  open the module;
- `Domain` and `Path` validation needed to state that it only protects header
  serialization;
- validation should cover top-level `Choku.Cookie` export wiring.

The design now uses `No_restriction` for `SameSite=None`, requires
`~secure:true` with that value, emits both `Max-Age=0` and fixed past
`Expires` on deletion, ignores request cookie pairs whose names are not valid
HTTP tokens, documents `Domain` and `Path` validation scope, and includes export
coverage in validation. Re-review passed.

Follow-up security review found two issues:

- `Cookie.get` first-value semantics are risky for authentication or session
  cookies when duplicate cookie names appear;
- examples and public documentation should more strongly guide sensitive
  cookies toward `Secure`, `HttpOnly`, and explicit `SameSite`.

The follow-up adds `Cookie.get_unique`, documents duplicate-cookie risk, and
updates examples and interface guidance to prefer secure attributes for
authentication and session cookies.

## Validation

Implementation should add:

- `test/test_response.ml` coverage for `Response.add_header`;
- one unit test file for `Cookie`, covering request parsing, repeated cookies,
  malformed ignored pairs, `Set-Cookie` formatting, multiple `Set-Cookie`
  preservation, deletion, and invalid output values;
- coverage that `Choku.Cookie` is exported from the top-level `Choku` module;
- formatter and static checks.

## Open Questions

- Should quoted cookie values be supported later?
