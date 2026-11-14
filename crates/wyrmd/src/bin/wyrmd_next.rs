//! A second `wyrmd` binary for the tests of the broker's own update (ADR
//! 0048 §2, `tests/update.rs`): the same broker, built as another
//! executable, that says it is a later version. It is built only with the
//! feature `test-next`, which the crate's tests turn on; a build of
//! `wyrmd` does not have it, so this never ships.
//!
//! It is version 0.2.0 unless a file `test-build.json` sits beside it
//! (`{"version": "0.3.0", "schema_bump": {"registry": 1}}`): the tests put
//! that file into the archive to make a version that says it moves a
//! SCHEMA.

fn main() -> Result<(), wyrmd::Error> {
    let beside = std::env::current_exe()
        .ok()
        .and_then(|exe| Some(exe.parent()?.join("test-build.json")));
    let build = beside
        .and_then(|p| std::fs::read(p).ok())
        .and_then(|b| serde_json::from_slice::<wyrmd::update::TestBuild>(&b).ok())
        .unwrap_or_else(|| wyrmd::update::TestBuild {
            version: "0.2.0".into(),
            ..Default::default()
        });
    wyrmd::cli::main(Some(build))
}
