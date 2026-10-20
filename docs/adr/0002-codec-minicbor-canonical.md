# ADR 0002 — One wire codec: canonical CBOR via minicbor

**Status:** accepted · 2026-10-20

## Decision
All wire payloads (`~meta`, `~val`, attachment, `~def`) are CBOR with integer keys, canonical encoding (RFC 8949 §4.2.1; text keys ordered length-first then bytewise; floats in shortest lossless form). `minicbor` in Rust; `serde`/`json5` only for `wyrmd.json5`.

## Why
One codec = one fixture set for Rust, Dart and C (zenoh-pico). `minicbor` is `no_std`, zero-copy for strings/bytes, and gives us control over key order. Equivalent in size to msgpack.
