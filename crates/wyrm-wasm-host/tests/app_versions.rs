//! ADR 0025, ADR 0030: the host runs components of `wyrm:app@0.1.0` (frozen, e.g. installed
//! scheduler packages), of `wyrm:app@0.2.0` (with `list` / `on-list`, frozen) and of
//! `wyrm:app@0.3.0` (with `tls-connect`, `tls-upgrade`, `random-bytes`) side by side.

use std::path::Path;

use wit_parser::{LiftLowerAbi, ManglingAndAbi, Resolve};
use wyrm_wasm_host::{app_version, component_world, AppWorld, ComponentWorld, Host};

/// A component of the world in `wit/<dir>` whose functions all trap: enough to load it.
fn dummy(dir: &str) -> Vec<u8> {
    dummy_at(&Path::new(env!("CARGO_MANIFEST_DIR")).join("wit").join(dir))
}

fn dummy_at(dir: &Path) -> Vec<u8> {
    let mut resolve = Resolve::default();
    let (pkg, _) = resolve.push_path(dir).expect("wit");
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
fn every_app_world_version_loads() {
    let host = Host::new().unwrap();
    for (dir, version) in [("app", "0.1.0"), ("app2", "0.2.0"), ("app3", "0.3.0")] {
        let bytes = dummy(dir);
        assert_eq!(
            component_world(&bytes).unwrap(),
            ComponentWorld::App,
            "{dir}"
        );
        let art = host
            .load::<AppWorld>(&bytes)
            .unwrap_or_else(|e| panic!("{dir}: {e}"));
        assert_eq!(art.app_version(), version, "{dir}");
        assert_eq!(app_version(&bytes).unwrap(), version, "{dir}");
    }
}

/// A `wyrm:app` version the host does not run is refused, at load and when told by its imports.
#[test]
fn an_unknown_app_world_version_is_refused() {
    let wit =
        std::fs::read_to_string(Path::new(env!("CARGO_MANIFEST_DIR")).join("wit/app3/app.wit"))
            .unwrap()
            .replace("package wyrm:app@0.3.0;", "package wyrm:app@9.9.9;");
    let dir = Path::new(env!("CARGO_TARGET_TMPDIR")).join("wit-app-9.9.9");
    std::fs::create_dir_all(&dir).unwrap();
    std::fs::write(dir.join("app.wit"), wit).unwrap();
    let bytes = dummy_at(&dir);
    assert_eq!(component_world(&bytes).unwrap(), ComponentWorld::App);
    let e = app_version(&bytes).unwrap_err().to_string();
    assert!(e.contains("9.9.9"), "{e}");
    match Host::new().unwrap().load::<AppWorld>(&bytes) {
        Err(wyrm_wasm_host::Error::Denied(name)) => assert_eq!(name, "wyrm:app/host@9.9.9"),
        Err(e) => panic!("not denied: {e}"),
        Ok(_) => panic!("loaded"),
    }
}
