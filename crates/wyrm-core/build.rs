//! The Rust target triple this crate is built for, as `WYRM_BUILD_TARGET`
//! ([`BUILD_TARGET`](crate::BUILD_TARGET)): `std::env::consts::ARCH` is `arm`
//! for ARMv6 and ARMv7 alike, so it cannot name a release target or a
//! package host.

fn main() {
    println!("cargo:rerun-if-changed=build.rs");
    let target = std::env::var("TARGET").unwrap_or_default();
    println!("cargo:rustc-env=WYRM_BUILD_TARGET={target}");
}
