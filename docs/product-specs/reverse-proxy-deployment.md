# Reverse Proxy Deployment

## Status

Accepted

## Problem

Choku is intended to be useful as a small HTTP/1.1 application server behind a
reverse proxy or load balancer such as nginx, AWS Application Load Balancer, or
Classic Load Balancer HTTP(S). Users need a compact deployment guide that
explains which Choku settings matter in that topology and which edge-server
concerns belong outside Choku for now.

## Goals

- Document the recommended first deployment shape: reverse proxy or load
  balancer in front of Choku.
- Explain how keep-alive behaves between the proxy and Choku.
- Recommend Choku timeout and size-limit settings for backend deployments.
- Show a minimal health-check route.
- Clarify upload and streaming route guidance.
- State what Choku does not yet handle as an edge server.

## Non-Goals

- Vendor-specific exhaustive configuration manuals.
- TLS certificate management.
- HTTP/2, HTTP/3, WebSocket, compression, caching, static-file serving, or WAF
  guidance.
- Kubernetes, systemd, container image, or process manager documentation.
- Automatic trusted-proxy parsing of `X-Forwarded-*` headers.

## Recommended Topology

Run Choku as a private backend application server:

```text
client -> nginx / ALB / Classic Load Balancer HTTP(S) -> Choku HTTP/1.1 backend
```

The outer proxy or load balancer should own public internet exposure, TLS,
HTTP/2 or HTTP/3 frontend support, compression, WAF/rate-limiting policy,
static assets, and access logging. Choku should receive ordinary HTTP/1.1
requests on a private network interface or loopback address.

## Choku Server Settings

Use explicit request-head timeout settings for deployed servers:

```ocaml
let server =
  Choku.Server.create_router
    ~request_head_timeout:(Some 75.0)
    ~max_request_head_size:65_536
    ~max_request_body_size:1_048_576
    router

let () =
  Eio_main.run @@ fun env ->
  Eio.Switch.run @@ fun sw ->
  Choku.Server.run ~sw
    ~net:(Eio.Stdenv.net env)
    ~mono_clock:(Eio.Stdenv.mono_clock env)
    ~addr:(`Tcp (Eio.Net.Ipaddr.V4.loopback, 8080))
    server
```

Guidance:

- Keep `keep_alive` enabled unless the fronting proxy requires one backend
  request per connection.
- Set `request_head_timeout` for long-running deployments. It also bounds idle
  time between keep-alive requests. When backend keep-alive is enabled, set this
  timeout higher than the proxy or load balancer's backend idle timeout, or
  configure the proxy to close idle backend connections before Choku does.
- Keep `max_request_head_size` at the default unless the application needs
  unusually large headers.
- Set `max_request_body_size` to the maximum accepted decoded request body size
  for ordinary buffered routes.
- Prefer `Server.create_router` when only selected routes need streaming request
  bodies.
- `request_head_timeout` does not cover request body reads. Slow upload
  protection belongs in the fronting proxy, load balancer, or application-level
  cancellation policy.

## Keep-Alive

Choku enables HTTP/1.1 keep-alive by default. Buffered requests can reuse the
same backend connection sequentially, and Choku writes `Connection: keep-alive`
only when it will wait for another request.

Reverse proxies and load balancers commonly reuse backend connections. This is
the expected deployment shape for Choku.

Because `request_head_timeout` also acts as Choku's idle timeout between
keep-alive requests, the fronting proxy should stop reusing an idle backend
connection before Choku closes it. Otherwise the proxy can try to send a request
on a backend connection that Choku has already closed. Two simple approaches are:

- set Choku `request_head_timeout` higher than the proxy or load balancer's
  backend idle timeout;
- disable backend reuse during troubleshooting with `~keep_alive:false`.

If backend reuse needs to be disabled for troubleshooting or compatibility,
create the server with:

```ocaml
Choku.Server.create_router ~keep_alive:false router
```

## nginx Example

A minimal nginx reverse proxy can forward HTTP/1.1 requests to Choku:

```nginx
upstream choku_backend {
    server 127.0.0.1:8080;
    keepalive 32;
    keepalive_timeout 60s;
}

server {
    listen 80;

    location / {
        proxy_http_version 1.1;
        proxy_set_header Connection "";
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 60s;
        proxy_send_timeout 60s;
        proxy_pass http://choku_backend;
    }
}
```

This example is intentionally small. Production nginx deployments should add
TLS, access logs, request-size policy, compression, static assets, and security
controls at the nginx layer as needed.

Applications should not trust `X-Forwarded-*` values merely because they are
present. The edge proxy should sanitize or overwrite incoming forwarded headers,
and the application should only interpret them when the request came from a
trusted proxy. Choku does not currently provide automatic trusted-proxy parsing.

## AWS ALB And ELB Notes

AWS Application Load Balancer and Classic Load Balancer HTTP(S) use HTTP/1.1 on
backend connections to registered targets by default, and backend keep-alive is
supported by default. This matches Choku's default backend behavior. These notes
do not describe Network Load Balancer or Gateway Load Balancer behavior.

Operational notes:

- Configure target group health checks to hit a cheap route such as `/health`.
- Keep the load balancer target-connection idle timeout lower than Choku's
  `request_head_timeout`, or disable backend reuse with `~keep_alive:false`.
- Choku does not currently use `X-Forwarded-For`, `X-Forwarded-Proto`, or
  `X-Forwarded-Port` automatically. Treat these as application-level headers
  until trusted-proxy support is explicitly designed.
- If the load balancer reports backend 400, 408, 413, or 431 responses, inspect
  Choku's request-head and body limits before increasing load balancer limits.

## Health Checks

Use a cheap buffered route:

```ocaml
let router =
  Choku.Router.empty
  |> Choku.Router.get "/health" (fun _ _ -> Choku.Response.text "ok\n")
```

`HEAD /health` is also handled automatically through the router's `GET`
fallback unless an explicit `HEAD` route is registered.

## Upload Routes

Keep most routes buffered. Use route-level streaming only for upload endpoints
that consume their request body during the handler:

```ocaml
let router =
  Choku.Router.empty
  |> Choku.Router.post
       ~request_body_mode:Choku.Request_body_mode.Streaming
       "/upload"
       upload
```

Coordinate upload limits in all layers:

- reverse proxy or load balancer maximum body size;
- Choku `max_request_body_size`;
- application-level file type, count, and storage policy.

Choku's `request_head_timeout` does not limit the time spent reading request
body bytes. Configure slow upload protection at the edge proxy or load balancer,
and use application-level cancellation if a route needs a stricter upload
deadline.

Streaming request-body responses close the backend connection in the current
Choku milestone. Buffered routes remain eligible for keep-alive reuse.

## Direct Exposure

Direct public exposure is not the recommended first deployment shape. Choku does
not yet provide TLS, HTTP/2, HTTP/3, compression, static files, trusted-proxy
handling, or built-in observability. If Choku is exposed directly in a private
or test environment, set a finite `request_head_timeout` and bind only to the
intended interface. Direct deployments still need a separate policy for slow
request bodies and large uploads.

## References

- [Reverse Proxy Deployment References](../references/reverse-proxy-deployment.md)

## Open Questions

None.
