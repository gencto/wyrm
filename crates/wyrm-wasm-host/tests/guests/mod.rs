//! Test guests written in the component text format (no guest toolchain).
//! Shared with `crates/wyrm-flow/tests` through `#[path]`.
//!
//! Canonical ABI used here: every export returns through a return area
//! (`result<…>` flattens to more than one value), a bump `cabi_realloc`
//! hands out argument memory, the return area sits at address 0.

#![allow(dead_code)]

/// Bump allocator plus one page of memory; the heap starts at 1024.
const CORE_PRELUDE: &str = r#"
    (memory (export "memory") 1)
    (global $heap (mut i32) (i32.const 1024))
    (func $alloc (export "cabi_realloc")
      (param $old i32) (param $old_size i32) (param $align i32) (param $size i32) (result i32)
      (local $p i32) (local $need i32)
      (local.set $p
        (i32.and
          (i32.add (global.get $heap) (i32.sub (local.get $align) (i32.const 1)))
          (i32.sub (i32.const 0) (local.get $align))))
      (global.set $heap (i32.add (local.get $p) (local.get $size)))
      (local.set $need (i32.sub (global.get $heap) (i32.mul (memory.size) (i32.const 65536))))
      (if (i32.gt_s (local.get $need) (i32.const 0))
        (then
          (if (i32.eq
                (memory.grow (i32.add (i32.shr_u (local.get $need) (i32.const 16)) (i32.const 1)))
                (i32.const -1))
            (then unreachable))))
      (local.get $p))
    ;; init(config) -> ok
    (func (export "init") (param i32 i32) (result i32)
      (i32.store8 (i32.const 0) (i32.const 0))
      (i32.const 0))
"#;

const NODE_EXPORTS: &str = r#"
  (core instance $i (instantiate $m))
  (func (export "init") (param "config" (list u8)) (result (result (error string)))
    (canon lift (core func $i "init") (memory (core memory $i "memory")) (realloc (core func $i "cabi_realloc"))))
  (func (export "process")
    (param "port" string) (param "sample" (list u8)) (param "state" (list u8))
    (result (result (tuple (list u8) (list u8)) (error string)))
    (canon lift (core func $i "process") (memory (core memory $i "memory")) (realloc (core func $i "cabi_realloc"))))
"#;

fn node(process: &str) -> Vec<u8> {
    let text = format!("(component (core module $m {CORE_PRELUDE} {process}) {NODE_EXPORTS})");
    wat::parse_str(text).expect("guest WAT")
}

/// Flow node: emits on `out` the input sample with its value (a CBOR uint
/// below 24, one byte) increased by `add`; the state is one byte counting
/// calls.
pub fn add(add: u8) -> Vec<u8> {
    node(&format!(
        r#"
    (func (export "process")
      (param $port i32) (param $port_len i32) (param $s i32) (param $s_len i32)
      (param $st i32) (param $st_len i32) (result i32)
      (local $out i32) (local $new i32)
      ;; emits = [ ["out", sample] ]: 0x81 0x82 0x63 'o' 'u' 't' then the sample
      (local.set $out (call $alloc (i32.const 0) (i32.const 0) (i32.const 1)
        (i32.add (local.get $s_len) (i32.const 6))))
      (i32.store8 (local.get $out) (i32.const 0x81))
      (i32.store8 offset=1 (local.get $out) (i32.const 0x82))
      (i32.store8 offset=2 (local.get $out) (i32.const 0x63))
      (i32.store8 offset=3 (local.get $out) (i32.const 0x6f))
      (i32.store8 offset=4 (local.get $out) (i32.const 0x75))
      (i32.store8 offset=5 (local.get $out) (i32.const 0x74))
      (memory.copy (i32.add (local.get $out) (i32.const 6)) (local.get $s) (local.get $s_len))
      ;; sample = A3 00 <v> …: v is byte 2 of the sample
      (i32.store8 offset=8 (local.get $out)
        (i32.add (i32.load8_u offset=8 (local.get $out)) (i32.const {add})))
      ;; state: one byte, calls so far
      (local.set $new (call $alloc (i32.const 0) (i32.const 0) (i32.const 1) (i32.const 1)))
      (i32.store8 (local.get $new)
        (i32.add (i32.const 1)
          (if (result i32) (local.get $st_len)
            (then (i32.load8_u (local.get $st)))
            (else (i32.const 0)))))
      (i32.store8 (i32.const 0) (i32.const 0))
      (i32.store offset=4 (i32.const 0) (local.get $out))
      (i32.store offset=8 (i32.const 0) (i32.add (local.get $s_len) (i32.const 6)))
      (i32.store offset=12 (i32.const 0) (local.get $new))
      (i32.store offset=16 (i32.const 0) (i32.const 1))
      (i32.const 0))
"#
    ))
}

/// Flow node whose `process` never returns.
pub fn spin() -> Vec<u8> {
    node(
        r#"
    (func (export "process") (param i32 i32 i32 i32 i32 i32) (result i32)
      (loop $l (br $l))
      (i32.const 0))
"#,
    )
}

/// Flow node whose `process` grows memory by `pages` 64 KiB pages and
/// then answers `err("grown")`.
pub fn grow(pages: u32) -> Vec<u8> {
    node(&format!(
        r#"
    (func (export "process") (param i32 i32 i32 i32 i32 i32) (result i32)
      (drop (memory.grow (i32.const {pages})))
      ;; err("grown"): the string lives at 64
      (i32.store8 (i32.const 64) (i32.const 0x67))
      (i32.store8 (i32.const 65) (i32.const 0x72))
      (i32.store8 (i32.const 66) (i32.const 0x6f))
      (i32.store8 (i32.const 67) (i32.const 0x77))
      (i32.store8 (i32.const 68) (i32.const 0x6e))
      (i32.store8 (i32.const 0) (i32.const 1))
      (i32.store offset=4 (i32.const 0) (i32.const 64))
      (i32.store offset=8 (i32.const 0) (i32.const 5))
      (i32.const 0))
"#
    ))
}

/// A flow node component that imports `import` (an empty instance), e.g.
/// `wasi:filesystem/types@0.2.0`.
pub fn importing(import: &str) -> Vec<u8> {
    let text = format!(
        "(component (import \"{import}\" (instance)) (core module $m {CORE_PRELUDE} {}) {NODE_EXPORTS})",
        r#"
    (func (export "process") (param i32 i32 i32 i32 i32 i32) (result i32)
      (i32.store8 (i32.const 0) (i32.const 1))
      (i32.store offset=4 (i32.const 0) (i32.const 0))
      (i32.store offset=8 (i32.const 0) (i32.const 0))
      (i32.const 0))
"#
    );
    wat::parse_str(text).expect("guest WAT")
}

/// Point driver: one register, initially 7. `read` → `{0: reg, 1: 0, 2: 0}`;
/// `write(point, v)` stores a CBOR uint below 24, else `err`.
pub fn register() -> Vec<u8> {
    let text = format!(
        r#"(component
  (core module $m {CORE_PRELUDE}
    (global $reg (mut i32) (i32.const 7))
    (func (export "read") (param i32 i32) (result i32)
      (local $out i32)
      (local.set $out (call $alloc (i32.const 0) (i32.const 0) (i32.const 1) (i32.const 8)))
      ;; A3 00 <reg> 01 00 02 00
      (i32.store8 (local.get $out) (i32.const 0xa3))
      (i32.store8 offset=1 (local.get $out) (i32.const 0x00))
      (i32.store8 offset=2 (local.get $out) (global.get $reg))
      (i32.store8 offset=3 (local.get $out) (i32.const 0x01))
      (i32.store8 offset=4 (local.get $out) (i32.const 0x00))
      (i32.store8 offset=5 (local.get $out) (i32.const 0x02))
      (i32.store8 offset=6 (local.get $out) (i32.const 0x00))
      (i32.store8 (i32.const 0) (i32.const 0))
      (i32.store offset=4 (i32.const 0) (local.get $out))
      (i32.store offset=8 (i32.const 0) (i32.const 7))
      (i32.const 0))
    (func (export "write") (param $p i32) (param $pl i32) (param $v i32) (param $vl i32) (result i32)
      (if (i32.and (i32.eq (local.get $vl) (i32.const 1))
                   (i32.lt_u (i32.load8_u (local.get $v)) (i32.const 24)))
        (then
          (global.set $reg (i32.load8_u (local.get $v)))
          (i32.store8 (i32.const 0) (i32.const 0))
          (return (i32.const 0))))
      ;; err("range")
      (i32.store8 (i32.const 64) (i32.const 0x72))
      (i32.store8 (i32.const 65) (i32.const 0x61))
      (i32.store8 (i32.const 66) (i32.const 0x6e))
      (i32.store8 (i32.const 67) (i32.const 0x67))
      (i32.store8 (i32.const 68) (i32.const 0x65))
      (i32.store8 (i32.const 0) (i32.const 1))
      (i32.store offset=4 (i32.const 0) (i32.const 64))
      (i32.store offset=8 (i32.const 0) (i32.const 5))
      (i32.const 0)))
  (core instance $i (instantiate $m))
  (func (export "init") (param "config" (list u8)) (result (result (error string)))
    (canon lift (core func $i "init") (memory (core memory $i "memory")) (realloc (core func $i "cabi_realloc"))))
  (func (export "read") (param "point" (list u8)) (result (result (list u8) (error string)))
    (canon lift (core func $i "read") (memory (core memory $i "memory")) (realloc (core func $i "cabi_realloc"))))
  (func (export "write") (param "point" (list u8)) (param "value" (list u8)) (result (result (error string)))
    (canon lift (core func $i "write") (memory (core memory $i "memory")) (realloc (core func $i "cabi_realloc")))))"#
    );
    wat::parse_str(text).expect("guest WAT")
}
