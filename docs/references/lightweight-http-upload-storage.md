# Lightweight HTTP Upload Storage

## Source

- Go `net/http` package documentation:
  https://pkg.go.dev/net/http
- Express Multer middleware documentation:
  https://expressjs.com/fr/resources/middleware/multer/
- Axum multipart extractor documentation:
  https://docs.rs/axum/latest/axum/extract/multipart/struct.Multipart.html
- Accessed: 2026-05-24

## Summary

Lightweight HTTP server stacks generally keep upload persistence policy outside
the core server boundary.

Go exposes two levels: `Request.MultipartReader()` for streaming multipart
processing, and `Request.ParseMultipartForm(maxMemory)` for parsing the whole
multipart body while keeping up to `maxMemory` bytes of file parts in memory and
storing the remainder in temporary files. Go also exposes `MaxBytesReader` for
bounding request bodies before parsing.

Express itself does not provide upload storage as core HTTP behavior. The common
approach is route-local middleware such as Multer. Multer offers a simple `dest`
option, explicit storage engines such as disk and memory storage, upload limits,
and warnings against installing upload middleware globally on all routes.

Axum exposes multipart as an extractor. The extractor consumes the request body,
must be ordered accordingly with other extractors, and has a default body-size
limit for security. The example processes each field from the multipart stream;
storage policy remains application code or an additional crate.

## Implications

Choku should continue to keep its core HTTP server focused on request parsing,
body delivery, limits, and routing policy. The current `Multipart.Streaming`,
`Multipart.Filename.sanitize`, and `Multipart.Tempfile.save_*` helpers fit the
lightweight-server pattern.

A future higher-level upload storage policy should be treated as optional helper
API, not as default server behavior. If added, it should be route-local, bounded
by explicit limits, cleanup-aware, and configurable enough for application-owned
storage decisions.
