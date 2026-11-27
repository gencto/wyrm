//! The `wyrmd.json5` that `wyrm_image::Choices::files` writes for a board image (ADR 0051
//! §4) is a configuration this `wyrmd` loads: read by `Config::from_json5`, the function
//! `wyrmd check` runs, for DHCP and a static address and with every link form of the
//! official links.

#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    clippy::panic,
    reason = "test code: a failed step fails the test"
)]

use serde_json::Value;
use wyrm_image::{Catalog, CatalogLink, Choices, ImageEntry, Lan, LinkForm, Network};
use wyrmd::Config;

/// The catalog of an image that carries every official link: a built-in driver as
/// `Builtin`, the broker's own links as `Service`, a WASM package as `Seed`.
fn catalog() -> Catalog {
    let path = concat!(env!("CARGO_MANIFEST_DIR"), "/../../links/official.json");
    let manifest: Value = serde_json::from_str(&std::fs::read_to_string(path).unwrap()).unwrap();
    let links = manifest["links"]
        .as_array()
        .unwrap()
        .iter()
        .map(|link| {
            let id = link["id"].as_str().unwrap().to_owned();
            let forms = &link["forms"];
            let (form, driver, file) =
                if ["scheduler", "alarm", "dql", "uplink"].contains(&id.as_str()) {
                    (LinkForm::Service, None, None)
                } else if let Some(driver) = forms["builtin"].as_str() {
                    (LinkForm::Builtin, Some(driver.to_owned()), None)
                } else {
                    let package = forms["wasm"].as_str().unwrap();
                    let version = link["version"].as_str().unwrap();
                    (
                        LinkForm::Seed,
                        None,
                        Some(format!("{package}-{version}.zip")),
                    )
                };
            CatalogLink {
                id,
                form,
                driver,
                file,
            }
        })
        .collect();
    Catalog { links }
}

fn entry() -> ImageEntry {
    ImageEntry {
        board: "rpi4".to_owned(),
        file: "wyrm-rpi4.img".to_owned(),
        size: 1 << 30,
        sha256: "ab".repeat(32),
        config_offset: 343_932_928,
        openwrt: "25.12.6".to_owned(),
        wyrmd: "0.9.0".to_owned(),
        wyrmd_sha256: None,
        manifest_sha256: None,
        download: None,
        title: None,
        notes: None,
        lan: Some(Lan::Bridge {
            bridge: "br-lan".to_owned(),
            ports: vec!["eth0".to_owned()],
        }),
    }
}

fn load(choices: &Choices, catalog: &Catalog) -> Config {
    let files = choices.files(&entry(), catalog, &[0x5a; 32]).unwrap();
    Config::from_json5(&files.wyrmd_json5)
        .unwrap_or_else(|e| panic!("wyrmd refuses:\n{}\n{e}", files.wyrmd_json5))
}

#[test]
fn the_config_of_choices_is_one_wyrmd_loads() {
    let catalog = catalog();
    let forms = |form| catalog.links.iter().filter(move |l| l.form == form).count();
    assert!(
        forms(LinkForm::Builtin) > 0 && forms(LinkForm::Service) == 4 && forms(LinkForm::Seed) > 0
    );
    let every: Vec<String> = catalog.links.iter().map(|l| l.id.clone()).collect();
    let networks = [
        Network::Dhcp,
        Network::Static {
            address: "192.168.10.5".to_owned(),
            prefix: 24,
            gateway: Some("192.168.10.1".to_owned()),
            dns: vec!["192.168.10.1".to_owned()],
        },
    ];
    for network in networks {
        for links in [Vec::new(), vec!["modbus".to_owned()], every.clone()] {
            let choices = Choices {
                site: "plant".to_owned(),
                network: network.clone(),
                links: links.clone(),
                timezone: Some("Europe/Kyiv".to_owned()),
                ntp: vec!["pool.ntp.org".to_owned()],
                ssh_keys: None,
            };
            let cfg = load(&choices, &catalog);
            assert_eq!(cfg.site, "plant");
            assert_eq!(cfg.data_dir, std::path::Path::new(wyrm_image::DATA_DIR));
            let gateway = cfg.gateway.as_ref().unwrap();
            assert_eq!(gateway.listen.to_string(), wyrm_image::GATEWAY_LISTEN);
            assert_eq!(
                cfg.packages.seed_dir.is_some(),
                links.len() == every.len(),
                "{links:?}"
            );
            // the built-in links are there with their drivers, nothing else is
            let builtin: Vec<(&str, &str)> = catalog
                .links
                .iter()
                .filter(|l| l.form == LinkForm::Builtin && links.contains(&l.id))
                .map(|l| (l.id.as_str(), l.driver.as_deref().unwrap()))
                .collect();
            let loaded: Vec<(&str, &str)> = cfg
                .links
                .iter()
                .map(|(id, l)| (id.as_str(), l.driver.as_str()))
                .collect();
            let mut want = builtin.clone();
            want.sort_unstable();
            assert_eq!(loaded, want);
            // a service is on exactly when it was chosen
            let on = |id: &str| links.iter().any(|l| l == id);
            assert_eq!(cfg.scheduler.enabled, on("scheduler"));
            assert_eq!(cfg.alarm.enabled, on("alarm"));
            assert_eq!(cfg.dql.enabled, on("dql"));
            assert_eq!(cfg.uplink.enabled, on("uplink"));
        }
    }
}
