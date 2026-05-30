# Input Mapping Interoperability

## Status

Accepted

## Problem

Applications need to turn HTTP inputs into application-owned types, but Choku
should not become a validation framework. Route parameters, query parameters,
and URL-encoded form fields are untrusted string inputs with source-specific
parsing rules. Applications should be able to adapt those inputs to
third-party validators, typed decoders, or application-owned conversion code
without Choku choosing a validation model.

## Goals

- Keep input parsing and typed validation separate.
- Preserve source-specific input collections for route parameters, query
  parameters, and URL-encoded form fields.
- Provide small, stable accessor surfaces that external decoders can adapt.
- Preserve repeated values and ordering where HTTP input sources allow them.
- Make absence, malformed source parsing, and typed conversion errors easy for
  applications to model in their own error types.
- Keep Choku independent of validation, schema, and typed-decoder packages.

## Non-Goals

- A `Choku.Validator`, `Choku.Decode`, or `Choku.Input` framework.
- Built-in typed converters such as int, UUID, enum, date, or email decoders.
- A unified request input map that merges path, query, form, cookie, or header
  values.
- Source precedence rules between route parameters, query parameters, form
  fields, cookies, and headers.
- Typed route parameters, regex routes, or route matching based on converted
  values.
- UTF-8 validation, Unicode normalization, HTML escaping, SQL escaping, or
  application-specific sanitization.
- Dependencies on third-party validation libraries.

## Requirements

- Choku input collections remain source-specific:
  - `Router.Params.t` for route captures;
  - `Query.t` for decoded query parameters;
  - `Form.t` for decoded URL-encoded form fields.
- `Query.t` and `Form.t` remain immutable ordered multimaps with `get`,
  `get_or`, `get_all`, and `to_list`.
- `Router.Params.t` remains an immutable ordered collection of route captures.
  Route compilation continues to reject duplicate parameter names in one route
  pattern, but the adapter surface should still mirror the multimap modules
  where practical.
- A small follow-up API should add `Router.Params.get_all : string -> t ->
  string list`, returning either a singleton list or an empty list under the
  current duplicate-name rejection rule. That follow-up must also document
  duplicate parameter-name rejection in `Router`'s public interface and cover it
  with regression tests.
- `to_list` remains the stable bulk-export surface for third-party decoders
  that prefer a list of name/value pairs.
- `get_all` remains the stable per-field surface for third-party decoders that
  need repeated-value semantics.
- `get` and `get_or` remain convenience accessors for application-owned
  conversion code.
- Adapters must not silently collapse repeated query or form values for
  security-sensitive singleton fields. Applications should reject duplicates or
  pass repeated values to a decoder that models them.
- `get_or` is only appropriate for non-security defaults. Identity,
  authorization, CSRF, tenant, account, redirect, and permission-bearing inputs
  should model absence explicitly and fail closed.
- Choku does not merge input sources automatically. Applications that combine
  path, query, and body inputs must choose explicit precedence and error
  reporting.
- Choku parse errors remain source-specific `result` errors, for example
  `Query.error` and `Form.error`. Applications map them into their own error
  types before or during typed validation.
- Request and body availability errors are separate from validation errors.
  For example, `Form.of_request` may raise for a streaming body under its
  existing contract; adapters should avoid that case by selecting buffered body
  mode, checking `Body.is_buffered`, or preserving `Form.of_request`'s
  content-type acceptance rule before using body APIs that surface errors as
  results and then calling `Form.decode`.
- Query and form names and values are URL-decoded OCaml strings containing
  bytes. Route captures are raw path segment strings: the router does not
  percent-decode path segments and does not normalize dot segments or repeated
  slashes. Applications must not compare raw route captures with decoded query
  or form values unless they deliberately canonicalize both sides first. Choku
  does not validate character encoding or strip control bytes during input
  mapping.
- Documentation and examples should show adapters that hand Choku's
  source-specific collections to application-owned or third-party validation
  code, rather than adding validation policy to Choku itself.

## Public Contracts

The existing adapter-friendly contracts are:

```ocaml
module Query : sig
  type t

  val get : string -> t -> string option
  val get_or : default:string -> string -> t -> string
  val get_all : string -> t -> string list
  val to_list : t -> (string * string) list
end

module Form : sig
  type t

  val get : string -> t -> string option
  val get_or : default:string -> string -> t -> string
  val get_all : string -> t -> string list
  val to_list : t -> (string * string) list
end

module Router.Params : sig
  type t

  val get : string -> t -> string option
  val get_or : default:string -> string -> t -> string
  val to_list : t -> (string * string) list
end
```

A small compatibility follow-up should extend `Router.Params`:

```ocaml
module Router.Params : sig
  val get_all : string -> t -> string list
end
```

## Examples

Application-owned error composition should stay outside Choku:

```ocaml
module Result_syntax = struct
  let ( let* ) = Result.bind
end

type input_error =
  | Query_error of Choku.Query.error
  | Missing of string
  | Duplicate of string
  | Invalid of string * validation_reason

and validation_reason = Not_positive_integer

let require_single name = function
  | [] -> Error (Missing name)
  | [ value ] -> Ok value
  | _ :: _ :: _ -> Error (Duplicate name)

let parse_positive_int name value =
  match int_of_string_opt value with
  | Some n when n > 0 -> Ok n
  | _ -> Error (Invalid (name, Not_positive_integer))

let decode_search (ctx : Choku.Router.Context.t) =
  let open Result_syntax in
  let* query =
    Choku.Query.of_request ctx.request
    |> Result.map_error (fun error -> Query_error error)
  in
  let* page_value = Choku.Query.get_all "page" query |> require_single "page" in
  let* page = parse_positive_int "page" page_value in
  Ok page
```

An application can map an actual form into an application-owned record without
Choku owning the validator:

```ocaml
type signup_form = {
  email : string;
  age : int option;
  marketing_opt_in : bool;
}

type signup_error =
  | Form_error of Choku.Form.error
  | Streaming_form_body
  | Missing of string
  | Duplicate of string
  | Invalid of string * signup_reason

and signup_reason =
  | Not_positive_integer
  | Invalid_boolean

let optional_single name = function
  | [] -> Ok None
  | [ value ] -> Ok (Some value)
  | _ :: _ :: _ -> Error (Duplicate name)

let parse_bool name = function
  | "true" | "on" | "1" -> Ok true
  | "false" | "off" | "0" -> Ok false
  | _ -> Error (Invalid (name, Invalid_boolean))

let parse_positive_signup_int name value =
  match int_of_string_opt value with
  | Some n when n > 0 -> Ok n
  | _ -> Error (Invalid (name, Not_positive_integer))

let decode_signup request =
  let open Result_syntax in
  if not (Choku.Body.is_buffered (Choku.Request.body request)) then
    Error Streaming_form_body
  else
    let* form =
      Choku.Form.of_request request
      |> Result.map_error (fun error -> Form_error error)
    in
    let* email = Choku.Form.get_all "email" form |> require_single "email" in
    let* age_value = Choku.Form.get_all "age" form |> optional_single "age" in
    let* age =
      match age_value with
      | None -> Ok None
      | Some value ->
          parse_positive_signup_int "age" value |> Result.map Option.some
    in
    let* marketing_opt_in =
      match Choku.Form.get_all "marketing_opt_in" form with
      | [] -> Ok false
      | values ->
          let* value = require_single "marketing_opt_in" values in
          parse_bool "marketing_opt_in" value
    in
    Ok { email; age; marketing_opt_in }
```

Applications that already use a JSON decoder can adapt Choku inputs to Yojson
without adding a Choku dependency on Yojson. Repeated values should remain
visible, for example as arrays:

```ocaml
let rec add_value name value = function
  | [] -> [ (name, [ value ]) ]
  | (existing, values) :: rest when String.equal existing name ->
      (existing, value :: values) :: rest
  | field :: rest -> field :: add_value name value rest

let fields_to_yojson fields =
  let grouped =
    List.fold_left
      (fun grouped (name, value) -> add_value name value grouped)
      [] fields
  in
  `Assoc
    (List.map
       (fun (name, values) ->
         (name, `List (List.rev_map (fun value -> `String value) values)))
       grouped)

let query_json request =
  Choku.Query.of_request request
  |> Result.map (fun query -> fields_to_yojson (Choku.Query.to_list query))

let yojson_singleton_string name json =
  match Yojson.Safe.Util.member name json with
  | `List [ `String value ] -> Ok value
  | `List [] | `Null -> Error (`Missing name)
  | `List _ -> Error (`Duplicate name)
  | _ -> Error (`Invalid (name, `Expected_string_list))
```

Third-party adapters should use explicit source boundaries:

```ocaml
let query_fields request =
  Choku.Query.of_request request |> Result.map Choku.Query.to_list

type form_fields_error =
  | Missing_form_content_type
  | Unsupported_form_content_type
  | Malformed_form_encoding
  | Streaming_form_body

let map_form_error = function
  | Choku.Form.Missing_content_type -> Missing_form_content_type
  | Choku.Form.Unsupported_content_type _ -> Unsupported_form_content_type
  | Choku.Form.Malformed_percent_encoding -> Malformed_form_encoding

let form_fields request =
  if Choku.Body.is_buffered (Choku.Request.body request) then
    Choku.Form.of_request request
    |> Result.map_error map_form_error
    |> Result.map Choku.Form.to_list
  else Error Streaming_form_body

let route_fields (ctx : Choku.Router.Context.t) =
  Choku.Router.Params.to_list ctx.params
```

After the `Router.Params.get_all` follow-up, adapters that prefer per-field
lookup can use the same shape for each source:

```ocaml
module type Field_lookup = sig
  type t

  val get_all : string -> t -> string list
end
```

## Open Questions

None.

## Resolved Decisions

- Choku will not provide validation, typed decoders, source merging, or
  third-party validator integrations.
- `Router.Params`, `Query`, and `Form` remain separate source-specific
  collections with similar accessor shapes.
- `Router.Params.get_all` is worth adding as a small symmetry helper. It must
  not change route matching or relax duplicate parameter-name rejection.
