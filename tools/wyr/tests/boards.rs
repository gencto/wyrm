//! `packaging/images/boards.json` (ADR 0051 §2) as a reader of the file meets it, without
//! `wyr`'s own types: the page and CI read the same JSON. The strict reader of `wyr image
//! base` has its tests beside it (`src/image_base.rs`).

#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    clippy::panic,
    clippy::unreachable,
    clippy::print_stdout,
    clippy::print_stderr,
    reason = "test code: a failed step fails the test"
)]

use serde_json::Value;
use std::collections::BTreeMap;
use std::path::PathBuf;
use std::process::Command;

/// The file's path in the repository, as `git` names it.
const IN_REPO: &str = "packaging/images/boards.json";

fn repo() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../..")
}

fn boards_json() -> Value {
    let text = std::fs::read_to_string(repo().join(IN_REPO)).unwrap();
    serde_json::from_str(&text).unwrap()
}

fn text<'a>(of: &'a Value, field: &str) -> &'a str {
    of[field]
        .as_str()
        .unwrap_or_else(|| panic!("`{field}` is no text in {of}"))
}

/// `id` → `rootfs_partsize_mb` of every board of a list.
fn partsizes(list: &Value) -> BTreeMap<String, u64> {
    list["boards"]
        .as_array()
        .unwrap()
        .iter()
        .map(|board| {
            (
                text(board, "id").to_owned(),
                board["rootfs_partsize_mb"].as_u64().unwrap(),
            )
        })
        .collect()
}

#[test]
fn boards_json_is_valid() {
    let list = boards_json();
    assert_eq!(text(&list, "format"), "wyrm-boards/1");
    let openwrt = text(&list, "openwrt");
    assert!(!openwrt.is_empty());
    // the build container is named by digest
    let (_, digest) = text(&list, "container").rsplit_once("@sha256:").unwrap();
    assert_eq!(digest.len(), 64);
    assert!(digest.bytes().all(|b| b.is_ascii_hexdigit()));

    // one archive per target, of the pinned release, with its SHA-256
    let mut targets = Vec::new();
    for archive in list["imagebuilders"].as_array().unwrap() {
        let target = text(archive, "target");
        assert!(!targets.contains(&target), "{target} twice");
        targets.push(target);
        let url = text(archive, "url");
        let dir = format!("https://downloads.openwrt.org/releases/{openwrt}/targets/{target}/");
        assert!(url.starts_with(&dir), "{url}");
        assert!(url.contains(&format!("imagebuilder-{openwrt}-")), "{url}");
        let sha256 = text(archive, "sha256");
        assert_eq!(sha256.len(), 64, "{target}");
        assert!(sha256
            .bytes()
            .all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b)));
    }

    let boards = list["boards"].as_array().unwrap();
    let mut ids = Vec::new();
    for board in boards {
        let id = text(board, "id");
        assert!(!ids.contains(&id), "board {id} twice");
        ids.push(id);
        assert!(!text(board, "title").is_empty(), "{id}");
        let target = text(board, "target");
        assert!(targets.contains(&target), "{id}: no archive for {target}");
        let profile = text(board, "profile");
        assert!(!profile.is_empty(), "{id}");
        assert!(!text(board, "arch").is_empty(), "{id}");
        // the image is one of this release and this profile
        let image = text(board, "image");
        assert!(image.starts_with(&format!("openwrt-{openwrt}-")), "{id}");
        assert!(image.contains(&format!("-{profile}-")), "{id}");
        assert!(image.ends_with(".img.gz"), "{id}");
        assert!(["mbr", "gpt"].contains(&text(board, "table")), "{id}");
        let size = board["rootfs_partsize_mb"].as_u64();
        assert!(size.is_some_and(|mb| mb > 0), "{id}");
        assert_eq!(text(board, "config_part"), "append", "{id}");
        let config_dev = text(board, "config_dev");
        let data_dev = text(board, "data_dev");
        for dev in [config_dev, data_dev] {
            assert!(dev.starts_with("/dev/"), "{id}: {dev}");
            assert!(dev.ends_with(|c: char| c.is_ascii_digit()), "{id}: {dev}");
        }
        assert_ne!(config_dev, data_dev, "{id}");
        assert!(!text(board, "boot_from").is_empty(), "{id}");
        assert!(board["listed"].is_boolean(), "{id}");
        assert!(!text(board, "notes").is_empty(), "{id}");
        // a board without an image says why, and the page does not list it
        if !board["unavailable"].is_null() {
            assert!(!text(board, "unavailable").is_empty(), "{id}");
            assert_eq!(board["listed"], false, "{id}");
        }
    }
    // the boards of the first version (ADR 0051), and the board of the tests off the page
    for id in ["rpi4", "rpi5", "bpi-r4", "bpi-r4-8g", "qemu-armsr"] {
        assert!(ids.contains(&id), "no board {id}");
    }
    let qemu = boards
        .iter()
        .find(|board| board["id"] == "qemu-armsr")
        .unwrap();
    assert_eq!(qemu["listed"], false);
}

/// `ROOTFS_PARTSIZE` of a board is fixed for its life (ADR 0051 §3): every partition after
/// the root starts where it puts them, so a later image with another value loses the data
/// of a device it is written over. A board that `origin/main` has keeps its value.
#[test]
fn rootfs_partsize_never_changes() {
    let show = Command::new("git")
        .arg("-C")
        .arg(repo())
        .args(["show", &format!("origin/main:{IN_REPO}")])
        .output();
    let before = match show {
        Ok(output) if output.status.success() => output.stdout,
        // no git, no such ref (a shallow or detached checkout), or the file is new there
        Ok(output) => {
            eprintln!(
                "skipped: origin/main has no {IN_REPO}: {}",
                String::from_utf8_lossy(&output.stderr).trim()
            );
            return;
        }
        Err(e) => {
            eprintln!("skipped: git does not run: {e}");
            return;
        }
    };
    let before: Value = serde_json::from_slice(&before).unwrap();
    let changed = changed_partsizes(&before, &boards_json());
    assert!(
        changed.is_empty(),
        "rootfs_partsize_mb is fixed for the life of a board (ADR 0051 §3): {changed:?}"
    );
}

/// The boards of `before` that `now` has with another `rootfs_partsize_mb`. A board that
/// is new or gone is no change.
fn changed_partsizes(before: &Value, now: &Value) -> Vec<String> {
    let now = partsizes(now);
    partsizes(before)
        .into_iter()
        .filter_map(|(id, was)| {
            let is = *now.get(&id)?;
            (is != was).then(|| format!("board `{id}`: {was} MiB, now {is} MiB"))
        })
        .collect()
}

/// The comparison itself, on two lists: the test above skips where `origin/main` has no
/// list yet.
#[test]
fn a_changed_partsize_is_seen() {
    let now = boards_json();
    assert!(changed_partsizes(&now, &now).is_empty());
    let mut other = now.clone();
    other["boards"][0]["rootfs_partsize_mb"] = 512.into();
    assert_eq!(
        changed_partsizes(&now, &other),
        ["board `rpi4`: 256 MiB, now 512 MiB"]
    );
    // a new board and a board that is gone are no change of a size
    let mut fewer = now.clone();
    fewer["boards"].as_array_mut().unwrap().remove(0);
    assert!(changed_partsizes(&now, &fewer).is_empty());
    assert!(changed_partsizes(&fewer, &now).is_empty());
}
