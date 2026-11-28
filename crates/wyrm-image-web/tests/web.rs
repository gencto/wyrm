//! The functions under the page's bindings, natively: the same code, hash, files and region
//! as `wyrmd` and `wyr image build --choices` make.

#![allow(
    clippy::unwrap_used,
    clippy::panic,
    reason = "test code: a failed step fails the test"
)]

use std::collections::BTreeSet;

use qrcode::{Color, EcLevel, QrCode};
use wyrm_core::{hex, setup};
use wyrm_image::{region, Catalog, Choices, ImageEntry, CONFIG_SIZE};
use wyrm_image_web::{check, offered, region_of, setup_from, WebError};

const RANDOM: [u8; 16] = [
    0x3f, 0x0a, 0x9c, 0x1e, 0x5b, 0x7d, 0x24, 0x68, 0xac, 0xe0, 0x13, 0x57, 0x9b, 0xdf, 0x02, 0x46,
];

/// One entry of an index, with a `download` or without.
fn entry_json(board: &str, download: bool) -> String {
    let download = if download {
        format!(
            r#", "download": {{"file": "wyrm-{board}.img.gz", "size": 1000, "sha256": "{}"}}"#,
            "ef".repeat(32)
        )
    } else {
        String::new()
    };
    format!(
        r#"{{"board": "{board}", "file": "wyrm-{board}.img", "size": 1073741824,
            "sha256": "{}", "config_offset": 343932928, "openwrt": "25.12.6",
            "wyrmd": "0.9.0", "title": "Board {board}", "notes": "Write it to a card.",
            "lan": {{"bridge": "br-lan", "ports": ["eth0"]}}{download}}}"#,
        "cd".repeat(32)
    )
}

fn index_json(entries: &[String]) -> String {
    format!(
        r#"{{"format": "wyrm-images/1", "images": [{}]}}"#,
        entries.join(",")
    )
}

const CATALOG: &str = r#"{"links": [
    {"id": "modbus", "form": "builtin", "driver": "modbus", "title": "Modbus"},
    {"id": "alarm", "form": "service"},
    {"id": "scheduler", "form": "service"},
    {"id": "mqtt", "form": "seed", "file": "mqtt-0.1.0.zip"}]}"#;

const CHOICES: &str = r#"{"format": "wyrm-choices/1", "site": "plant",
    "network": {"mode": "static", "address": "192.168.10.5", "prefix": 24,
                "gateway": "192.168.10.1", "dns": ["192.168.10.1"]},
    "links": ["mqtt", "alarm", "modbus"], "timezone": "Europe/Kyiv",
    "ntp": ["0.openwrt.pool.ntp.org"], "ssh_keys": "ssh-ed25519 AAAA plant"}"#;

#[test]
fn a_setup_from_16_bytes_matches_wyrmd() {
    let made = setup_from(&RANDOM).unwrap();
    let (code, hash) = setup::code_of(&RANDOM);
    assert_eq!(made.code, code);
    assert_eq!(made.hash_hex, hex::encode(hash));
    // the code the person types gives the hash the gateway checks
    assert_eq!(setup::code_hash(&made.code), Some(hash));
}

#[test]
fn fewer_than_16_bytes_are_refused() {
    for len in [0, 15, 17, 32] {
        let random = vec![7u8; len];
        match setup_from(&random) {
            Err(e @ WebError::SetupBytes(n)) => {
                assert_eq!(n, len);
                assert_eq!(
                    e.to_string(),
                    format!("a setup code is made of 16 random bytes, not {len}")
                );
            }
            Err(e) => panic!("{len} bytes: {e}"),
            Ok(_) => panic!("{len} bytes were taken"),
        }
    }
}

#[test]
fn the_qr_is_svg_of_the_code() {
    let made = setup_from(&RANDOM).unwrap();
    let svg = &made.qr_svg;
    assert!(svg.starts_with("<svg"), "{svg}");
    assert!(svg.ends_with("</svg>"), "{svg}");
    assert!(!svg.contains("width="), "{svg}");
    assert!(!svg.contains("height="), "{svg}");
    assert!(svg.contains(r#"fill="currentColor""#), "{svg}");
    assert!(!svg.contains("#fff") && !svg.contains("#000"), "{svg}");

    // the dark modules are those of the code's QR (error correction M), inside a quiet
    // zone of four modules
    let qr = QrCode::with_error_correction_level(&made.code, EcLevel::M).unwrap();
    let width = qr.width();
    let side = width + 8;
    assert!(
        svg.contains(&format!(r#"viewBox="0 0 {side} {side}""#)),
        "{svg}"
    );
    let want: BTreeSet<(usize, usize)> = qr
        .to_colors()
        .chunks(width)
        .enumerate()
        .flat_map(|(y, row)| {
            row.iter()
                .enumerate()
                .filter(|(_, c)| **c == Color::Dark)
                .map(move |(x, _)| (x + 4, y + 4))
        })
        .collect();
    let d = svg.split(r#" d=""#).nth(1).unwrap();
    let d = d.split('"').next().unwrap();
    let got: BTreeSet<(usize, usize)> = d
        .split('M')
        .filter(|m| !m.is_empty())
        .map(|m| {
            let at = m.strip_suffix("h1v1h-1z").unwrap();
            let (x, y) = at.split_once(' ').unwrap();
            (x.parse().unwrap(), y.parse().unwrap())
        })
        .collect();
    assert!(!want.is_empty());
    assert_eq!(got, want);
}

#[test]
fn region_for_matches_wyr() {
    let made = setup_from(&RANDOM).unwrap();
    let entry = entry_json("rpi4", true);
    let ours = region_of(CHOICES, &entry, CATALOG, &made.hash_hex).unwrap();

    // what `wyr image build --choices` writes: `Choices::files`, then `region`
    let parsed = Choices::parse(CHOICES).unwrap();
    let entry_v: ImageEntry = serde_json::from_str(&entry).unwrap();
    let catalog: Catalog = serde_json::from_str(CATALOG).unwrap();
    let hash = setup::code_of(&RANDOM).1;
    let theirs = region(&parsed.files(&entry_v, &catalog, &hash).unwrap()).unwrap();
    assert_eq!(ours, theirs);
    assert_eq!(u64::try_from(ours.len()).unwrap(), CONFIG_SIZE);

    // the files carry the hash, never the code
    let files = wyrm_image::read_region(&ours).unwrap().unwrap();
    assert_eq!(files.setup.as_deref(), Some(made.hash_hex.as_str()));
    let text = String::from_utf8_lossy(&ours);
    assert!(!text.contains(&made.code));
    assert!(!text.contains(&made.code.replace('-', "")));

    // a hash that is not 64 hex digits
    for bad in ["", "ab", &"g".repeat(64), &"a".repeat(63)] {
        assert!(matches!(
            region_of(CHOICES, &entry, CATALOG, bad),
            Err(WebError::SetupHash)
        ));
    }
}

#[test]
fn check_choices_refuses_what_region_for_refuses() {
    let entry = entry_json("rpi4", true);
    check(CHOICES, &entry, CATALOG).unwrap();
    let hash = "ab".repeat(32);
    for (choices, entry, catalog, says) in [
        (
            CHOICES.replace("\"modbus\"]", "\"nope\"]"),
            entry.clone(),
            CATALOG.to_owned(),
            "the link `nope` is not one this image offers",
        ),
        (
            CHOICES.replace("\"prefix\": 24", "\"prefix\": 33"),
            entry.clone(),
            CATALOG.to_owned(),
            "the prefix /33 is refused",
        ),
        (
            CHOICES.replace("\"site\": \"plant\"", "\"site\": \"pl ant\""),
            entry.clone(),
            CATALOG.to_owned(),
            "names no site a board takes",
        ),
        (
            CHOICES.to_owned(),
            entry.replace(
                r#""lan": {"bridge": "br-lan", "ports": ["eth0"]}"#,
                r#""lan": null"#,
            ),
            CATALOG.to_owned(),
            "choose DHCP",
        ),
        (
            CHOICES.to_owned(),
            "{}".to_owned(),
            CATALOG.to_owned(),
            "the image entry cannot be read",
        ),
        (
            CHOICES.to_owned(),
            entry.clone(),
            "[]".to_owned(),
            "the catalog of links cannot be read",
        ),
    ] {
        let checked = check(&choices, &entry, &catalog).unwrap_err().to_string();
        let built = region_of(&choices, &entry, &catalog, &hash)
            .unwrap_err()
            .to_string();
        assert!(checked.contains(says), "{says}: {checked}");
        assert_eq!(checked, built);
    }
}

#[test]
fn check_index_offers_only_listed_boards_with_a_download() {
    // the index carries no `listed`: a board is offered when its image has a download
    let text = index_json(&[
        entry_json("rpi4", true),
        entry_json("bpi-r4", false),
        entry_json("rpi5", true),
    ]);
    let boards: Vec<String> = offered(&text)
        .unwrap()
        .into_iter()
        .map(|e| e.board)
        .collect();
    assert_eq!(boards, ["rpi4", "rpi5"]);

    // the offered entries are those of the index, and read back as entries
    let offered_entries = offered(&text).unwrap();
    let json = serde_json::to_string(&offered_entries).unwrap();
    let back: Vec<ImageEntry> = serde_json::from_str(&json).unwrap();
    assert_eq!(back, offered_entries);
    assert_eq!(back[0].title.as_deref(), Some("Board rpi4"));

    // an index the format refuses is refused, with its sentence
    let twice = index_json(&[entry_json("rpi4", true), entry_json("rpi4", true)]);
    let e = offered(&twice).unwrap_err().to_string();
    assert!(e.contains("board `rpi4` is there twice"), "{e}");
    let other = text.replace("wyrm-images/1", "wyrm-images/2");
    assert!(offered(&other).unwrap_err().to_string().contains("format"));
    assert!(offered("not json").is_err());
    // no image with a download: nothing to offer
    assert!(offered(&index_json(&[entry_json("rpi4", false)]))
        .unwrap()
        .is_empty());
}
