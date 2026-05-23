# Camelio

Camelio is an OCaml 5.4 HTTP server project built around Eio-native direct-style
IO.

> A pure Eio HTTP server for OCaml 5.

## Status

Camelio is in early design and implementation. The first implementation
milestone is a minimal HTTP/1.1 server over plain TCP with:

- `Connection: close` behavior;
- buffered and replayable request bodies;
- a low-level `Handler.t = Request.t -> Response.t` contract;
- middleware as `Handler.t -> Handler.t`;
- no Router, HTTP Client, TLS, HTTP/2, or HTTP/3 public APIs yet.

## Development

Expected local checks:

```sh
dune build @all
dune runtest
dune fmt
```

The project uses:

- dune for build orchestration;
- Alcotest for unit tests;
- ocamlformat for formatting;
- Eio for effects-based IO and structured concurrency.

## Documentation

Start with [AGENTS.md](AGENTS.md) for agent-facing workflow guidance.

Key design documents:

- [Project Charter](docs/product-specs/project-charter.md)
- [Minimal Server API](docs/product-specs/minimal-server-api.md)
- [Minimal HTTP/1.1 Server Milestone](docs/product-specs/minimal-http1-server.md)
- [Minimal Server, Handler, and Middleware API](docs/design-docs/minimal-server-handler-middleware-api.md)
- [Project Layout and Tooling](docs/design-docs/project-layout-and-tooling.md)
