# Input Mapping Interoperability

## Status

Accepted

## Context

`Router.Params`, `Query`, and `Form` expose small string-based views over HTTP
input sources. Query strings and URL-encoded forms are ordered multimaps.
Route parameters are ordered captures from a route pattern, and duplicate names
are rejected when the route is registered.

Choku already keeps typed conversion out of `Query`, `Form`, and `Router`.
Applications still need a smooth path from these collections to their own
types, third-party validators, or typed decoder libraries.

## Goals

- Confirm that Choku's current input collection design is compatible with
  application-owned and third-party validation.
- Define the stable adapter surfaces that external decoders should rely on.
- Keep source boundaries explicit so applications own precedence and error
  reporting.
- Identify minimal API symmetry improvements that help interop without making
  Choku own validation policy.

## Non-Goals

- Adding a Choku validation framework or typed decoder.
- Choosing or wrapping a third-party validation package.
- Adding typed route parameters or route matching by converted values.
- Merging route, query, form, cookie, or header values into one request input
  map.
- Changing URL decoding, character encoding, or request target parsing
  semantics.

## Proposed Design

Keep `Router.Params`, `Query`, and `Form` as separate source-specific
collections. This avoids implicit precedence between path, query, and body
inputs and prevents source confusion in authorization or validation code.

Use the existing accessor families as the interop surface:

- `to_list` for bulk adapters that feed a third-party decoder from an ordered
  list of name/value pairs;
- `get_all` for decoders that model repeated values explicitly;
- `get` for first-value application code;
- `get_or` for small defaults where absence is not an error.

Adapters must not silently collapse repeated query or form values for
security-sensitive singleton fields. If a third-party decoder internally uses a
single-value map, application glue code should reject duplicates first or choose
a decoder mode that preserves repeated values. This matters for identifiers,
roles, redirect targets, CSRF tokens, tenant IDs, and authorization scopes.

`get_or` should be reserved for non-security defaults. Security-sensitive fields
should model absence explicitly and fail closed rather than substituting a
default value.

Do not add a common `Choku.Input.t` in the first interoperability milestone.
Although `Query.t` and `Form.t` share an internal representation today, a shared
public type would make Choku own cross-source input semantics and would make it
harder for each source to evolve independently. Source-specific modules with a
common accessor shape are enough for external adapters.

Do not add built-in typed converters. Choku cannot choose error accumulation
versus fail-fast behavior, localization, normalization, strictness, or target
types without becoming a validation framework. Applications should map Choku's
source parse errors into application-owned error variants and then call their
own conversion or validation layer.

Keep request and body availability failures distinct from validation failures.
For example, `Form.of_request` returns `Form.error` for form parsing and content
type failures, but it may raise `Invalid_argument` when called on an accepted
content type with a streaming body. That is not a validation result. Adapters
that need total result-returning behavior should select buffered route body mode,
check `Body.is_buffered` before `Form.of_request`, or preserve `Form.of_request`'s
content-type acceptance rule before reading the body through a result-returning
body API and then calling `Form.decode`. Manual streaming form adapters must map
body-read errors separately from `Form.error` and should keep an explicit
`max_size` policy when using `Body.to_string_limited`.

The one small API gap is `Router.Params.get_all`. `Query` and `Form` expose it
because repeated values are part of their data model. `Router.Params` rejects
duplicate names, so `get_all` is not needed for route semantics. It is still
worth adding as a compatibility helper because it lets generic field adapters
use the same lookup shape across route, query, and form sources. Under the
current router contract, `Router.Params.get_all name params` returns `[value]`
when the route captured `name` and `[]` otherwise.

The `Router.Params.get_all` follow-up must also tighten the public router
documentation and tests around duplicate parameter-name rejection. The new
helper relies on route params remaining at-most-one per name, so the public
interface should state that duplicate capture names in one pattern are invalid.

Examples should show source-specific adapters rather than a merged map:

```ocaml
type http_inputs = {
  route : (string * string) list;
  query : (string * string) list;
  form : (string * string) list option;
}
```

Applications or third-party adapters can then decide how to handle repeated
values, missing values, and precedence.

After the `Router.Params.get_all` follow-up, per-field adapters can also use a
common lookup signature without introducing a common Choku input type:

```ocaml
module type Field_lookup = sig
  type t

  val get_all : string -> t -> string list
end
```

## Contracts

Existing public contracts that external adapters may rely on:

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

Small follow-up contract:

```ocaml
module Router.Params : sig
  val get_all : string -> t -> string list
end
```

`Router.Params.get_all` must be documented as returning at most one value under
the current route-pattern contract. It must not relax duplicate parameter-name
rejection. The implementation milestone must update `Router` interface
documentation to make duplicate capture-name rejection explicit.

## Security Considerations

HTTP inputs are attacker-controlled. Choku's interop surface must not imply that
decoded strings are safe, normalized, authenticated, or authorized.

Decoded query and form names and values may contain arbitrary percent-decoded
bytes, including controls and NUL. Adapters must not assume field names are
valid identifiers, UTF-8, normalized Unicode, or safe for logs or UI. Route
parameter values follow Choku's existing raw path handling: the router matches
`Request.path`, does not percent-decode path segments, and does not normalize
dot segments or repeated slashes. Applications and third-party validators own
character-set validation, normalization, escaping, authorization checks, and
storage-specific sanitization. Applications must not compare raw route captures
with decoded query or form values unless they deliberately canonicalize both
sides first.

Choku should not merge route, query, and form values automatically. Automatic
merging can create source-confusion bugs, especially for identifiers,
authorization scopes, CSRF tokens, and redirect targets. Examples should keep
the source label visible until application code deliberately chooses a
precedence rule.

`get` and `get_or` expose first-value behavior. Documentation should guide
security-sensitive repeated inputs toward `get_all` or `to_list` so applications
can reject duplicates when that matters. Security-sensitive inputs should avoid
`get_or` defaults unless the default is explicitly part of the application's
authorization and validation policy.

Examples should avoid carrying raw attacker-controlled values in validation
errors. Application error values intended for logs or responses should use
symbolic reasons or redacted, escaped, and bounded values.

## Alternatives Considered

- Add `Choku.Input` as a shared ordered multimap: rejected because it would make
  Choku own cross-source semantics and invite automatic source merging.
- Add typed converters directly to `Query`, `Form`, or `Router.Params`:
  rejected because conversion policy belongs to applications or third-party
  validators.
- Add typed path converters to the router: rejected for this milestone because
  it changes routing semantics and should remain a separate router design.
- Expose third-party validator integrations: rejected because Choku should not
  depend on or privilege one validation ecosystem.
- Leave the design undocumented: rejected because future helpers could
  accidentally turn into a validation framework without an explicit boundary.

## Third-Party Review

Initial context-free design review found four issues:

- `Form.of_request` can raise for streaming bodies, so adapter docs should not
  imply all source acquisition failures are source-specific `result` errors;
- product requirements blurred URL-decoded query/form strings with raw route
  capture strings;
- `Router.Params.get_all` relies on duplicate-name rejection being public
  contract;
- examples justified `to_list` adapters but did not show the uniform
  `get_all` adapter shape.

The design now separates parse errors from request/body availability failures,
mirrors route/query/form decoding differences in the product spec, requires the
`Router.Params.get_all` implementation milestone to document and test duplicate
capture-name rejection, and adds a minimal common `get_all` adapter signature.
Re-review found no remaining design-boundary issues.

## Security Review

Initial context-free security review found issues around:

- manual streaming form guidance could bypass `Form.of_request` content-type
  semantics before calling `Form.decode`;
- the product example used first-value lookup without duplicate rejection
  guidance;
- the example error type carried raw attacker-controlled values;
- product route-capture wording was less explicit than the design doc about raw
  path semantics;
- third-party decoders may collapse duplicate fields;
- `get_or` defaults can be unsafe for security-sensitive inputs;
- decoded field names are also arbitrary attacker-controlled byte strings.

The design now requires manual form adapters to preserve content-type checks,
use explicit body-size policy, and map body-read errors separately. The product
example uses `get_all` with duplicate rejection, carries symbolic validation
reasons instead of raw invalid values, spells out raw route capture semantics,
requires duplicate-aware adapter behavior for sensitive singleton fields, limits
`get_or` guidance to non-security defaults, and documents decoded names and
values as untrusted byte strings. Security review found no remaining boundary
blockers.

## Validation

This is a design milestone. Validation should include:

- context-free design review of the Choku-owned boundary versus
  third-party-owned validation;
- context-free security review focused on untrusted input, duplicate values,
  source confusion, and unsafe normalization assumptions;
- documentation checks with `dune build @fmt`;
- when `Router.Params.get_all` is implemented later, focused tests proving
  singleton, missing, ordering, and unchanged duplicate-name rejection behavior.

## Open Questions

None.
