# HTTP Server Baseline And Client Readiness

## Status

Accepted

## Context

Choku has reached a practical application-server baseline for HTTP/1.1:
request parsing is strict enough for reverse-proxy deployment, request and
response streaming are available, router behavior covers basic method semantics,
and keep-alive is implemented conservatively.

Before starting HTTP Client work, the remaining server topics should be
classified so client design does not accidentally inherit server-only details or
force avoidable churn in shared HTTP values.

## Goals

- Identify the server behavior that is already sufficient for the current
  application-server milestone.
- Identify small server polish tasks worth doing before HTTP Client work.
- Identify server features that should wait until client abstractions exist.
- Identify features that should remain application code or optional helpers.
- Protect shared HTTP types from server-only assumptions.

## Non-Goals

- Implementing any behavior in this inventory pass.
- Designing the HTTP Client API in detail.
- Promising nginx-like edge-server completeness.
- Adding TLS, HTTP/2, HTTP/3, compression, WebSocket, CONNECT, or proxy support.

## Current Baseline

The following areas are good enough for the minimal application-server target:

- HTTP/1.1 request-head parsing with strict request-line, header, and `Host`
  validation.
- Origin-form server request targets for application handlers.
- Fixed-length and chunked request bodies.
- Buffered and streaming request body delivery.
- Route-level and generic pre-body request body-mode selection.
- Bounded request bodies, request heads, chunk metadata, and request-head
  timeout.
- Persistent connections with conservative close behavior.
- Router `HEAD` fallback and `405 Method Not Allowed`.
- Buffered and streaming responses, including chunked unknown-length responses.
- `HEAD`, `204`, `304`, and informational no-body response handling.
- Reverse-proxy deployment guidance for nginx, ALB, and ELB style topologies.

This is enough to use Choku as an application server behind a reverse proxy.

## Recommended Pre-Client Work

Only a small amount of server work should happen before starting HTTP Client.

### 1. Update Milestone Specs To Accepted Current State

`minimal-http1-server.md` and `minimal-server-api.md` are still marked `Draft`
and describe an earlier milestone. They should be updated to the current server
baseline and marked `Accepted`.

This is documentation work, but it matters before HTTP Client design because
the client should reference stable shared contracts rather than stale milestone
text.

The refresh should explicitly document current limitations that are deferred,
especially automatic `Date` headers and `Expect: 100-continue`, so users can
distinguish deliberate minimal scope from accidental omissions.

### 2. Split Server-Only And Shared HTTP Target Concepts

The current `Request.t` target contract is server-oriented: it accepts only the
origin-form subset used by handlers. HTTP Client will need to represent at
least origin-form request targets for outbound origin servers, and it may later
need absolute-form for proxies.

Before implementing the client, design should explicitly decide:

- whether `Request.t` remains a server/application request value;
- whether HTTP Client gets a separate outbound request type;
- which target constructors or validation helpers are shared;
- how client URI authority, scheme, path, and query are represented without
  weakening server request validation.

This should be a client design input, not a server behavior change.

### 3. Introduce Shared Response Writing/Reading Boundaries Deliberately

Response streaming introduced an HTTP/1.1 response writer for the server.
HTTP Client will need response parsing and body streaming in the opposite
direction.

Client design should reuse low-level framing helpers where they are genuinely
protocol-generic, but it should avoid exposing server write-policy details such
as:

- automatic `Connection` response header ownership;
- `HEAD` response-body suppression rules;
- body-forbidden status handling as a server writer decision.

Those policies are useful references for a client, but client response parsing
has different ownership and lifecycle constraints.

## Defer Until After Initial HTTP Client

The following features are useful but should not block HTTP Client work.

### Date And Server Headers

HTTP servers commonly add `Date` and sometimes `Server`. Choku can defer this
because reverse proxies commonly add or normalize them, and applications can
set their own headers today.

If implemented later, prefer opt-in or narrowly configurable behavior. Avoid
forcing a `Server` product token into core responses.

### `Expect: 100-continue`

This matters for large uploads from some clients, but implementing it well
requires pre-body handler or policy decisions. Current application-server use
behind reverse proxies can defer it.

HTTP Client work may need to decide whether outbound requests can send
`Expect: 100-continue`. That decision should be made with the client API,
because client and server behavior are independent.

### Graceful Shutdown And Connection Draining

The current `Server.run` switch ownership model is clear, but there is no
high-level graceful drain API. This is operationally useful, but not required
before HTTP Client.

Defer until there is more experience with real server deployment and client
connection lifecycles.

### Observability Hooks

Request logging, metrics, and trace hooks are valuable. Middleware can handle
application-level logging today, while protocol-level byte counters and timing
hooks need a separate design.

HTTP Client should later consider the same observability shape so both client
and server can share hook concepts without coupling their internals.

### Absolute-Form Server Requests

Origin servers normally receive origin-form request targets. Absolute-form is
important for proxies. Since Choku is not currently a proxy server, server-side
absolute-form support should wait.

HTTP Client design should still model absolute URIs internally because outbound
requests need scheme, authority, path, and query.

## Keep Out Of Core For Now

The following remain outside the minimal core server:

- file response helpers;
- SSE helpers;
- upload storage policy;
- static file serving;
- compression;
- range requests;
- sendfile or zero-copy transfer;
- WebSocket or protocol upgrade;
- reverse proxy behavior;
- TLS termination policy.

These are either application-level concerns, optional helper-library concerns,
or edge-server concerns.

## HTTP Client Readiness Notes

The initial HTTP Client should likely start from a separate design milestone
rather than by extending `Server` modules.

Important inputs:

- Reuse shared `Method.t`, `Status.t`, `Headers.t`, `Body.t`, and likely
  `Response.t` where their contracts fit.
- Be careful with `Request.t`: current validation is server/application
  oriented.
- Preserve Eio direct-style ownership: request and response streaming should
  have explicit lifetimes.
- Keep TLS as a separate transport design unless the first client milestone
  explicitly includes it.
- Keep redirects, cookies, decompression, connection pooling, proxy support,
  and retries out of the first client milestone.

The first client milestone should probably target one plain HTTP/1.1 request
over an Eio flow/network connection, with explicit body delivery and no pool.

## Suggested Next Work

1. Update stale minimal server specs to match the current accepted baseline.
   Include explicit limitations for automatic `Date` and `Expect:
   100-continue`.
2. Design the first HTTP Client milestone, including request-target and URI
   representation.
3. Implement the minimal HTTP Client only after the shared/server-only type
   boundary is clear.

## Open Questions

- Should outbound client requests reuse `Request.t`, or should Choku introduce
  a separate `Client.Request.t`?
- Which URI package or small internal URI representation should be used for the
  first client milestone?
- Should the first client support only buffered responses, or should streaming
  response bodies be part of the initial client baseline?
