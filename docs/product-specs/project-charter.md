# Project Charter

## Status

Accepted

## Slogan

A pure Eio HTTP server for OCaml 5.

## Problem

OCaml 5 provides effects and Eio provides a direct model for structured
concurrency. Camelio exists to explore and deliver an HTTP server designed around
that model instead of adapting an existing HTTP stack or another concurrency
runtime.

## Goals

- Provide an HTTP server library for OCaml 5.4 users who want Eio-native IO.
- Make core HTTP behavior clear, documented, and tested.
- Keep dependency choices aligned with the pure Eio positioning.
- Support agentic development by keeping requirements and decisions in the
  repository.

## Non-Goals

- Depending on `cohttp`, `lwt`, or `async`.
- Building a full web framework before the HTTP server foundation is stable.
- Promising HTTP/2, HTTP/3, or TLS behavior before those specs are written.

## Initial User Story

As an OCaml 5.4 developer using Eio, I want to run a small HTTP server with a
plain OCaml request handler so that I can serve HTTP responses without adopting
`cohttp`, `lwt`, or `async`.

## Open Questions

- What should the first public handler signature be?
- What HTTP/1.1 features define the first usable release?
- What examples should be included in the first implementation milestone?
