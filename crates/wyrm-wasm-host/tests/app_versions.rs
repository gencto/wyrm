//! ADR 0025: the host runs components of `wyrm:app@0.1.0` (frozen, e.g. installed scheduler
//! packages) and of `wyrm:app@0.2.0` (with `list` / `on-list`) side by side.

use std::path::Path;

use wit_parser::{LiftLowerAbi, ManglingAndAbi, Resolve};
use wyrm_wasm_host::{component_world, AppWorld, ComponentWorld, Host};

/// A component of the world in `wit/<dir>` whose functions all trap: enough to load it.
fn dummy(dir: &str) -> Vec<u8> {
    let mut resolve = Resolve::default();
    let (pkg, _) = resolve
        .push_path(Path::new(env!("CARGO_MANIFEST_DIR")).join("wit").join(dir))
        .expect("wit");
    let world = resolve.select_world(&[pkg], Some("app")).expect("world");
    let mangling = ManglingAndAbi::Legacy(LiftLowerAbi::Sync);
    let mut module = wit_component::dummy_module(&resolve, world, mangling);
    wit_component::embed_component_metadata(
        &mut module,
        &resolve,
        world,
        wit_component::StringEncoding::UTF8,
    )
    .expect("metadata");
    wit_component::ComponentEncoder::default()
        .module(&module)
        .expect("module")
        .validate(true)
        .encode()
        .expect("component")
}

#[test]
fn both_app_world_versions_load() {
    let host = Host::new().unwrap();
    for (dir, version) in [("app", "0.1.0"), ("app2", "0.2.0")] {
        let bytes = dummy(dir);
        assert_eq!(
            component_world(&bytes).unwrap(),
            ComponentWorld::App,
            "{dir}"
        );
        let art = host
            .load::<AppWorld>(&bytes)
            .unwrap_or_else(|e| panic!("{dir}: {e}"));
        assert_eq!(art.app_version(), version);
    }
}
