//! Builds the fixture app for `wasm32-unknown-unknown` and checks that the core module carries the
//! component type of world `wyrm:app/app@0.2.0`, which `wit-component` needs to make it a component.

use std::path::{Path, PathBuf};
use std::process::Command;

/// wit-bindgen names the section `component-type:wit-bindgen:<version>:<package>:<world>:<kind>`.
const SECTION_PREFIX: &str = "component-type:wit-bindgen:";
const WORLD: &str = ":wyrm:app@0.2.0:app:";

fn wasm32_installed() -> bool {
    Command::new("rustc")
        .args([
            "--print",
            "target-libdir",
            "--target",
            "wasm32-unknown-unknown",
        ])
        .output()
        .ok()
        .filter(|o| o.status.success())
        .map(|o| PathBuf::from(String::from_utf8_lossy(&o.stdout).trim()))
        .is_some_and(|dir| dir.exists())
}

/// The world's exports, written by the generated glue that `export!` expands in the app crate.
const EXPORTS: [&str; 9] = [
    "start",
    "on-set",
    "on-invoke",
    "on-timer",
    "on-value",
    "on-reply",
    "on-list",
    "stop",
    "cabi_realloc",
];

/// Custom section names and export names of a core module.
fn sections_and_exports(wasm: &[u8]) -> (Vec<String>, Vec<String>) {
    let (mut sections, mut exports) = (Vec::new(), Vec::new());
    for payload in wasmparser::Parser::new(0).parse_all(wasm) {
        match payload.expect("valid wasm") {
            wasmparser::Payload::CustomSection(s) => sections.push(s.name().to_owned()),
            wasmparser::Payload::ExportSection(r) => {
                for e in r {
                    exports.push(e.expect("valid export").name.to_owned());
                }
            }
            _ => {}
        }
    }
    (sections, exports)
}

#[test]
fn guest_fixture_builds_with_component_type() {
    if !wasm32_installed() {
        eprintln!(
            "SKIP guest_fixture_builds_with_component_type: target wasm32-unknown-unknown is not \
             installed (rustup target add wasm32-unknown-unknown)"
        );
        return;
    }
    let crate_dir = Path::new(env!("CARGO_MANIFEST_DIR"));
    let fixture = crate_dir.join("tests/fixture");
    // The fixture is its own workspace; seed its lock file from the main one so it builds with the
    // same dependency versions (cargo drops the entries it does not need).
    let lock = crate_dir.join("../../Cargo.lock");
    std::fs::copy(&lock, fixture.join("Cargo.lock")).expect("copy Cargo.lock");
    let target = Path::new(env!("CARGO_TARGET_TMPDIR")).join("guest-fixture");
    let out = Command::new(env!("CARGO"))
        .args([
            "build",
            "--release",
            "--target",
            "wasm32-unknown-unknown",
            "--manifest-path",
        ])
        .arg(fixture.join("Cargo.toml"))
        .arg("--target-dir")
        .arg(&target)
        .env_remove("RUSTFLAGS")
        .env_remove("CARGO_ENCODED_RUSTFLAGS")
        .output()
        .expect("run cargo");
    assert!(
        out.status.success(),
        "fixture build failed:\n{}",
        String::from_utf8_lossy(&out.stderr)
    );
    let wasm =
        std::fs::read(target.join("wasm32-unknown-unknown/release/wyrm_link_guest_fixture.wasm"))
            .expect("fixture wasm");
    let (names, exports) = sections_and_exports(&wasm);
    let section = names
        .iter()
        .find(|n| n.starts_with(SECTION_PREFIX) && n.contains(WORLD))
        .unwrap_or_else(|| panic!("no component-type section for wyrm:app/app in {names:?}"));
    eprintln!("component type section: {section}");
    for name in EXPORTS {
        assert!(
            exports.iter().any(|e| e == name),
            "export {name} missing in {exports:?}"
        );
    }
}
