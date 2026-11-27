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
        // the recorded place of the config region: after the root partition, on 1 MiB;
        // `null` only for a board that is not on the page (it was never built)
        match board["config_offset"].as_u64() {
            Some(offset) => {
                assert!(offset > size.unwrap() << 20, "{id}");
                assert_eq!(offset % (1 << 20), 0, "{id}");
            }
            None => {
                assert!(board["config_offset"].is_null(), "{id}");
                assert_eq!(
                    board["listed"], false,
                    "{id}: listed without a recorded layout"
                );
            }
        }
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
        // the page offers a static address on the `lan` ports of a listed board: a bridge
        // with its ports, or one device
        let lan = &board["lan"];
        if board["listed"] == true || !lan.is_null() {
            let names: Vec<&str> = match (lan["bridge"].as_str(), lan["device"].as_str()) {
                (Some(bridge), None) => {
                    let ports = lan["ports"].as_array().unwrap();
                    assert!(!ports.is_empty(), "{id}: a bridge without ports");
                    std::iter::once(bridge)
                        .chain(ports.iter().map(|p| p.as_str().unwrap()))
                        .collect()
                }
                (None, Some(device)) => vec![device],
                _ => panic!("{id}: `lan` is {lan}"),
            };
            for name in names {
                assert!(
                    (1..=15).contains(&name.len())
                        && name
                            .bytes()
                            .all(|b| b.is_ascii_alphanumeric() || b"_.-".contains(&b)),
                    "{id}: {name}"
                );
            }
        }
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
/// of a device it is written over. A board that the base of the change has keeps its value,
/// and a `config_offset` the base records stays (`null` may become a number once).
///
/// The base is the commit `BOARDS_BASE` names (CI: the base of the pull request, or the
/// commit before the push), else `origin/main`. The test passes without a comparison in one
/// case only: the base is there and has no `boards.json` yet. A base that cannot be read is
/// a failure in CI (`CI` is set there) and a skip on a developer's machine.
#[test]
fn rootfs_partsize_never_changes() {
    let base = std::env::var("BOARDS_BASE")
        .ok()
        .filter(|base| !base.is_empty())
        .unwrap_or_else(|| "origin/main".to_owned());
    let git = |args: &[&str]| {
        Command::new("git")
            .arg("-C")
            .arg(repo())
            .args(args)
            .output()
    };
    let in_ci = std::env::var_os("CI").is_some();
    let no_base = |why: String| {
        assert!(
            !in_ci,
            "the base `{base}` cannot be read ({why}): CI fetches it before this test, \
             and without it a changed rootfs_partsize_mb would pass"
        );
        eprintln!("skipped: the base `{base}` cannot be read ({why})");
    };
    match git(&[
        "rev-parse",
        "--verify",
        "--quiet",
        &format!("{base}^{{commit}}"),
    ]) {
        Ok(output) if output.status.success() => {}
        Ok(_) => return no_base("no such commit here".to_owned()),
        Err(e) => return no_base(format!("git does not run: {e}")),
    }
    // the commit is there: the file is either in it or new
    let listed = git(&["ls-tree", "--name-only", &base, "--", IN_REPO]).unwrap();
    assert!(listed.status.success(), "git ls-tree {base}");
    if listed.stdout.is_empty() {
        eprintln!("no comparison: `{base}` has no {IN_REPO} yet");
        return;
    }
    let show = git(&["show", &format!("{base}:{IN_REPO}")]).unwrap();
    assert!(show.status.success(), "git show {base}:{IN_REPO}");
    let before: Value = serde_json::from_slice(&show.stdout).unwrap();
    let now = boards_json();
    let changed = changed_partsizes(&before, &now);
    assert!(
        changed.is_empty(),
        "rootfs_partsize_mb is fixed for the life of a board (ADR 0051 §3): {changed:?}"
    );
    let moved = moved_offsets(&before, &now);
    assert!(
        moved.is_empty(),
        "a recorded config_offset is fixed for the life of a board (ADR 0051 §3): {moved:?}"
    );
}

/// The boards of `before` with a recorded `config_offset` that `now` has with another one
/// (or none). A board that is new or gone, or had no record, is no change.
fn moved_offsets(before: &Value, now: &Value) -> Vec<String> {
    let offsets = |list: &Value| -> BTreeMap<String, Value> {
        list["boards"]
            .as_array()
            .unwrap()
            .iter()
            .map(|board| (text(board, "id").to_owned(), board["config_offset"].clone()))
            .collect()
    };
    let now = offsets(now);
    offsets(before)
        .into_iter()
        .filter_map(|(id, was)| {
            let is = now.get(&id)?;
            (was.is_u64() && *is != was).then(|| format!("board `{id}`: {was}, now {is}"))
        })
        .collect()
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

/// The same for the recorded place of the config region.
#[test]
fn a_moved_offset_is_seen() {
    let now = boards_json();
    assert!(moved_offsets(&now, &now).is_empty());
    let rpi4 = now["boards"][0]["config_offset"].as_u64().unwrap();
    let mut other = now.clone();
    other["boards"][0]["config_offset"] = (rpi4 + (1 << 20)).into();
    assert_eq!(
        moved_offsets(&now, &other),
        [format!("board `rpi4`: {rpi4}, now {}", rpi4 + (1 << 20))]
    );
    other["boards"][0]["config_offset"] = Value::Null;
    assert_eq!(
        moved_offsets(&now, &other),
        [format!("board `rpi4`: {rpi4}, now null")]
    );
    // a board without a record gets one: no change
    let mut unrecorded = now.clone();
    unrecorded["boards"][0]["config_offset"] = Value::Null;
    assert!(moved_offsets(&unrecorded, &now).is_empty());
}
