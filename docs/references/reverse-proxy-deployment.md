# Reverse Proxy Deployment References

## Status

Accepted

## Purpose

This note records external reference points used by Choku's reverse proxy
deployment guide. It is not a full vendor configuration manual.

## AWS Elastic Load Balancing

AWS documents that Classic Load Balancers and Application Load Balancers use
connection multiplexing for HTTP connections, that backend keep-alive can be
disabled by sending `Connection: close`, and that Application Load Balancers use
HTTP/1.1 on backend connections to registered targets by default. AWS also
documents that ALB and Classic Load Balancer add `X-Forwarded-For`,
`X-Forwarded-Proto`, and `X-Forwarded-Port` headers.

Source:

- <https://docs.aws.amazon.com/elasticloadbalancing/latest/userguide/how-elastic-load-balancing-works.html>
- Accessed: 2026-05-24

AWS documents ALB load balancer attributes including connection idle timeout and
HTTP client keepalive duration. The ALB connection idle timeout applies to
client and target connections, and AWS recommends configuring the application's
idle timeout to be larger than the load balancer idle timeout to avoid possible
502 responses. The ALB HTTP client keepalive duration applies to client-side
persistent connections to the load balancer, not directly to Choku backend
server settings.

Source:

- <https://docs.aws.amazon.com/elasticloadbalancing/latest/application/edit-load-balancer-attributes.html>
- Accessed: 2026-05-24

## nginx

The nginx reverse proxy documentation describes `proxy_pass`, proxy buffering,
and common reverse-proxy/load-balancing use. The Choku deployment guide keeps
nginx configuration minimal and avoids relying on nginx-specific behavior beyond
standard HTTP reverse proxying.

Source:

- <https://docs.nginx.com/nginx/admin-guide/web-server/reverse-proxy>
- Accessed: 2026-05-24

The nginx upstream module documents backend keep-alive connection caching,
HTTP/1.1 upstream proxying requirements for older nginx versions, and the
`keepalive_timeout` directive for idle upstream keep-alive connections. As of
nginx 1.29.7, upstream keep-alive is enabled by default with a default limit of
32 connections per worker; `keepalive_timeout` defaults to 60 seconds.

Source:

- <https://nginx.org/en/docs/http/ngx_http_upstream_module.html>
- Accessed: 2026-05-24

The nginx project announced that upstream keep-alive defaults changed in nginx
1.29.7, released in March 2026. The guide still shows explicit HTTP/1.1 upstream
proxy settings so deployments remain clear and compatible with older nginx
versions.

Source:

- <https://blog.nginx.org/blog/keep-alive-to-upstreams-is-now-default-in-nginx-1-29-7>
- Accessed: 2026-05-24
