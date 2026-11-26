//! `wyr image build` and `wyr image inspect` (ADR 0051 §4) on a synthetic base image: 8 MiB
//! of filler with an empty config region at a chosen offset, and an index made for it. The
//! tests run the built `wyr`.

#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    clippy::panic,
    clippy::unreachable,
    clippy::print_stdout,
    reason = "test code: a failed step fails the test"
)]

use std::path::{Path, PathBuf};
use std::process::{Command, Output};
use wyrm_core::hex::sha256_hex;
use wyrm_image::{read_region, CONFIG_SIZE, MAGIC_EMPTY};

const SIZE: usize = 8 * 1024 * 1024;
/// Not on a 1 MiB boundary: the region starts inside one part of the copy and ends in another.
const OFFSET: usize = 3 * 1024 * 1024 + 512;
const CONFIG: &str = "{ site: \"plant\", gateway: { tls: \"site_ca\" } }\n";
const SETUP: &str = "3f0a9c1e5b7d2468ace013579bdf02468ace13579bdf0246813579bdf02468ac";
const KEYS: &str = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOnlyThePersonsKey person@host\n";

fn region_size() -> usize {
    usize::try_from(CONFIG_SIZE).unwrap()
}

/// The base image: filler that is not zeros outside the region, the empty magic at `OFFSET`.
fn base() -> Vec<u8> {
    let mut image: Vec<u8> = (0..SIZE).map(|i| u8::try_from(i % 251).unwrap()).collect();
    image[OFFSET..OFFSET + region_size()].fill(0);
    image[OFFSET..OFFSET + 8].copy_from_slice(MAGIC_EMPTY);
    image
}

fn index_for(image: &[u8], offset: usize) -> String {
    format!(
        r#"{{"format": "wyrm-images/1", "images": [
            {{"board": "rpi4", "file": "base.img", "size": {}, "sha256": "{}",
              "config_offset": {offset}, "openwrt": "24.10.4", "wyrmd": "0.9.0"}}]}}"#,
        image.len(),
        sha256_hex(image)
    )
}

/// A directory of one test with the base image, its index and a configuration.
struct Dir(PathBuf);

impl Dir {
    fn new(name: &str) -> Self {
        let dir = std::env::temp_dir().join(format!("wyr-image-{name}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        let image = base();
        std::fs::write(dir.join("base.img"), &image).unwrap();
        std::fs::write(dir.join("index.json"), index_for(&image, OFFSET)).unwrap();
        std::fs::write(dir.join("wyrmd.json5"), CONFIG).unwrap();
        Self(dir)
    }

    fn path(&self, name: &str) -> PathBuf {
        self.0.join(name)
    }

    fn write(&self, name: &str, data: impl AsRef<[u8]>) -> PathBuf {
        let path = self.path(name);
        std::fs::write(&path, data).unwrap();
        path
    }

    fn wyr(&self, args: &[&str]) -> Output {
        Command::new(env!("CARGO_BIN_EXE_wyr"))
            .args(args)
            .current_dir(&self.0)
            .output()
            .unwrap()
    }

    /// `wyr image build` of the base image with `more` arguments, into `out.img`.
    fn build(&self, more: &[&str]) -> Output {
        let mut args = vec![
            "image",
            "build",
            "--image",
            "base.img",
            "--index",
            "index.json",
            "--board",
            "rpi4",
            "--config",
            "wyrmd.json5",
            "--out",
            "out.img",
        ];
        args.extend_from_slice(more);
        self.wyr(&args)
    }

    /// What the directory holds, sorted: a refused build leaves only what was there.
    fn names(&self) -> Vec<String> {
        let mut names: Vec<String> = std::fs::read_dir(&self.0)
            .unwrap()
            .map(|e| e.unwrap().file_name().into_string().unwrap())
            .collect();
        names.sort();
        names
    }
}

impl Drop for Dir {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.0);
    }
}

fn text(bytes: &[u8]) -> &str {
    std::str::from_utf8(bytes).unwrap()
}

fn ok(out: &Output) -> &str {
    assert!(out.status.success(), "{}", text(&out.stderr));
    text(&out.stdout)
}

fn refused(out: &Output) -> &str {
    assert!(!out.status.success(), "not refused: {}", text(&out.stdout));
    assert_eq!(text(&out.stdout), "", "a refused run prints no result");
    text(&out.stderr)
}

fn region_of(image: &Path) -> Vec<u8> {
    let bytes = std::fs::read(image).unwrap();
    bytes[OFFSET..OFFSET + region_size()].to_vec()
}

#[test]
fn build_writes_the_region() {
    let dir = Dir::new("build");
    dir.write("network", "config interface 'lan'\n\toption proto 'dhcp'\n");
    dir.write("seed.json", "{\"format\":\"wyrm-seed/1\",\"links\":[]}");
    dir.write("keys", KEYS);
    // the hash as `wyrmd setup-code` prints it, in a file
    dir.write("setup.hash", format!("{}\n", SETUP.to_uppercase()));
    let out = dir.build(&[
        "--network",
        "network",
        "--seed",
        "seed.json",
        "--setup-hash-file",
        "setup.hash",
        "--authorized-keys",
        "keys",
        "--timezone",
        "Europe/Kyiv",
        "--ntp",
        "0.openwrt.pool.ntp.org, 1.openwrt.pool.ntp.org",
    ]);
    // the result is the output path, and nothing of the setup
    let stdout = ok(&out);
    assert_eq!(stdout.trim_end(), "out.img");
    assert!(!format!("{stdout}{}", text(&out.stderr))
        .to_lowercase()
        .contains(SETUP));

    let base = base();
    let built = std::fs::read(dir.path("out.img")).unwrap();
    assert_eq!(built.len(), SIZE);
    // only the region differs
    assert_eq!(built[..OFFSET], base[..OFFSET]);
    assert_eq!(
        built[OFFSET + region_size()..],
        base[OFFSET + region_size()..]
    );
    let files = read_region(&built[OFFSET..OFFSET + region_size()])
        .unwrap()
        .unwrap();
    assert_eq!(files.wyrmd_json5, CONFIG);
    assert_eq!(
        files.network.as_deref(),
        Some("config interface 'lan'\n\toption proto 'dhcp'\n")
    );
    assert_eq!(
        files.seed_json.as_deref(),
        Some("{\"format\":\"wyrm-seed/1\",\"links\":[]}")
    );
    assert_eq!(files.setup.as_deref(), Some(SETUP));
    assert_eq!(files.authorized_keys.as_deref(), Some(KEYS));
    assert_eq!(files.timezone.as_deref(), Some("Europe/Kyiv\n"));
    assert_eq!(
        files.ntp.as_deref(),
        Some("0.openwrt.pool.ntp.org\n1.openwrt.pool.ntp.org\n")
    );
    // the base image is as it was, and no temporary file stays
    assert_eq!(std::fs::read(dir.path("base.img")).unwrap(), base);
    assert!(
        dir.names().iter().all(|n| !n.contains("tmp")),
        "{:?}",
        dir.names()
    );
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let mode = std::fs::metadata(dir.path("out.img"))
            .unwrap()
            .permissions()
            .mode();
        assert_eq!(mode & 0o777, 0o600, "the image holds the setup hash");
    }
}

#[test]
fn only_the_config_is_required() {
    let dir = Dir::new("minimal");
    ok(&dir.build(&[]));
    let files = read_region(&region_of(&dir.path("out.img")))
        .unwrap()
        .unwrap();
    assert_eq!(files.wyrmd_json5, CONFIG);
    assert!(files.network.is_none() && files.seed_json.is_none() && files.setup.is_none());
    assert!(files.authorized_keys.is_none() && files.timezone.is_none() && files.ntp.is_none());
}

#[test]
fn a_new_setup_code_is_printed_once() {
    let dir = Dir::new("code");
    let out = dir.build(&["--new-setup-code"]);
    let stdout = ok(&out);
    let mut lines = stdout.lines();
    assert_eq!(lines.next(), Some("out.img"));
    let code = lines.next().unwrap().strip_prefix("setup code: ").unwrap();
    assert_eq!(lines.next(), None);
    assert_eq!(code.split('-').count(), 7, "{code}");
    // the image holds the hash of that code, and the hash is printed nowhere
    let hash = wyrm_core::hex::encode(wyrm_core::setup::code_hash(code).unwrap());
    let files = read_region(&region_of(&dir.path("out.img")))
        .unwrap()
        .unwrap();
    assert_eq!(files.setup.as_deref(), Some(hash.as_str()));
    assert!(!format!("{stdout}{}", text(&out.stderr)).contains(&hash));

    // one or the other
    dir.write("setup.hash", SETUP);
    let both = dir.build(&[
        "--force",
        "--new-setup-code",
        "--setup-hash-file",
        "setup.hash",
    ]);
    assert!(
        refused(&both).contains("cannot be used with"),
        "{}",
        text(&both.stderr)
    );
    // a hash that is none is refused before anything is written, and is not echoed
    dir.write("setup.hash", "abc123\n");
    let bad = dir.build(&["--force", "--setup-hash-file", "setup.hash"]);
    let why = refused(&bad);
    assert!(why.contains("64 hex digits"), "{why}");
    assert!(!why.contains("abc123"), "{why}");
    // the hash is a secret of the image: it is not taken as an argument
    let arg = dir.build(&["--force", "--setup-hash", SETUP]);
    assert!(!refused(&arg).contains(SETUP), "{}", text(&arg.stderr));
}

#[test]
fn a_wrong_sha_is_refused() {
    let dir = Dir::new("sha");
    let before = dir.names();
    // one byte of the image differs from what the index describes
    let mut image = base();
    image[100] ^= 1;
    dir.write("base.img", &image);
    let why = refused(&dir.build(&[])).to_owned();
    assert!(
        why.contains("is not the base image of board `rpi4`"),
        "{why}"
    );
    assert_eq!(dir.names(), before, "no output and no temporary file");

    // a shorter and a longer file
    dir.write("base.img", &base()[..SIZE - 1]);
    let why = refused(&dir.build(&[])).to_owned();
    assert!(
        why.contains("is not the base image of board `rpi4`"),
        "{why}"
    );
    let mut long = base();
    long.extend_from_slice(&[0; 4096]);
    dir.write("base.img", &long);
    let why = refused(&dir.build(&[])).to_owned();
    assert!(
        why.contains("is not the base image of board `rpi4`"),
        "{why}"
    );
    assert_eq!(dir.names(), before);

    // a board the index does not have
    dir.write("base.img", base());
    let out = dir.wyr(&[
        "image",
        "build",
        "--image",
        "base.img",
        "--index",
        "index.json",
        "--board",
        "rpi5",
        "--config",
        "wyrmd.json5",
        "--out",
        "out.img",
    ]);
    let why = refused(&out);
    assert!(
        why.contains("no board `rpi5`") && why.contains("rpi4"),
        "{why}"
    );
    assert_eq!(dir.names(), before);
}

#[test]
fn a_wrong_offset_is_refused() {
    let dir = Dir::new("offset");
    let before = dir.names();
    // the index points into zeros of the region instead of its magic
    dir.write("index.json", index_for(&base(), OFFSET + 16));
    let why = refused(&dir.build(&[])).to_owned();
    assert!(why.contains("no config region"), "{why}");
    assert_eq!(dir.names(), before, "no output and no temporary file");
}

#[test]
fn an_assembled_image_is_no_base_image() {
    let dir = Dir::new("assembled");
    ok(&dir.build(&[]));
    let before = dir.names();
    let out = dir.wyr(&[
        "image",
        "build",
        "--image",
        "out.img",
        "--index",
        "index.json",
        "--board",
        "rpi4",
        "--config",
        "wyrmd.json5",
        "--out",
        "again.img",
    ]);
    let why = refused(&out);
    assert!(why.contains("already holds a configuration"), "{why}");
    assert!(why.contains("base image"), "{why}");
    assert_eq!(dir.names(), before);
}

#[test]
fn an_existing_output_needs_force() {
    let dir = Dir::new("force");
    dir.write("out.img", "what was there");
    let why = refused(&dir.build(&[])).to_owned();
    assert!(why.contains("exists") && why.contains("--force"), "{why}");
    assert_eq!(
        std::fs::read(dir.path("out.img")).unwrap(),
        b"what was there"
    );
    // a refused build with --force leaves the old file too
    dir.write("bad.json5", "");
    let out = dir.wyr(&[
        "image",
        "build",
        "--image",
        "base.img",
        "--index",
        "index.json",
        "--board",
        "rpi4",
        "--config",
        "bad.json5",
        "--out",
        "out.img",
        "--force",
    ]);
    refused(&out);
    assert_eq!(
        std::fs::read(dir.path("out.img")).unwrap(),
        b"what was there"
    );

    ok(&dir.build(&["--force"]));
    assert!(read_region(&region_of(&dir.path("out.img")))
        .unwrap()
        .is_some());
}

#[test]
fn the_output_is_never_the_base_image() {
    let dir = Dir::new("same");
    for out in ["base.img", "./base.img"] {
        let run = dir.wyr(&[
            "image",
            "build",
            "--image",
            "base.img",
            "--index",
            "index.json",
            "--board",
            "rpi4",
            "--config",
            "wyrmd.json5",
            "--out",
            out,
            "--force",
        ]);
        let why = refused(&run);
        assert!(why.contains("is the base image"), "{why}");
    }
    assert_eq!(std::fs::read(dir.path("base.img")).unwrap(), base());
}

/// A temporary file an interrupted run left under the same name does not stop the next run.
#[test]
fn a_stale_temporary_file_is_replaced() {
    let dir = Dir::new("stale");
    // the name of the next run is not known (its process id): any earlier name stays, and a
    // run still ends well beside it
    dir.write("out.img.1.tmp", "left by an interrupted run");
    ok(&dir.build(&[]));
    assert!(read_region(&region_of(&dir.path("out.img")))
        .unwrap()
        .is_some());
}

#[test]
fn gz_input_is_unpacked() {
    use std::io::Write as _;
    let dir = Dir::new("gz");
    let mut gz = flate2::write::GzEncoder::new(Vec::new(), flate2::Compression::fast());
    gz.write_all(&base()).unwrap();
    let gz = gz.finish().unwrap();
    assert!(gz.len() < SIZE / 4);
    dir.write("base.img.gz", &gz);
    std::fs::remove_file(dir.path("base.img")).unwrap();
    let out = dir.wyr(&[
        "image",
        "build",
        "--image",
        "base.img.gz",
        "--index",
        "index.json",
        "--board",
        "rpi4",
        "--config",
        "wyrmd.json5",
        "--out",
        "out.img",
    ]);
    ok(&out);
    // the output is the raw image with the region written
    let built = std::fs::read(dir.path("out.img")).unwrap();
    assert_eq!(built.len(), SIZE);
    assert_eq!(built[..OFFSET], base()[..OFFSET]);
    let files = read_region(&built[OFFSET..OFFSET + region_size()])
        .unwrap()
        .unwrap();
    assert_eq!(files.wyrmd_json5, CONFIG);
    // inspect reads a compressed image too
    let seen = dir.wyr(&[
        "image",
        "inspect",
        "--image",
        "base.img.gz",
        "--index",
        "index.json",
        "--board",
        "rpi4",
    ]);
    assert!(
        ok(&seen).contains("region: empty"),
        "{}",
        text(&seen.stdout)
    );

    // an image packed in several members (`pigz`) is one image
    let mut members = Vec::new();
    for part in base().chunks(SIZE / 3 + 1) {
        let mut gz = flate2::write::GzEncoder::new(Vec::new(), flate2::Compression::fast());
        gz.write_all(part).unwrap();
        members.extend_from_slice(&gz.finish().unwrap());
    }
    dir.write("members.img.gz", &members);
    let out = dir.wyr(&[
        "image",
        "build",
        "--image",
        "members.img.gz",
        "--index",
        "index.json",
        "--board",
        "rpi4",
        "--config",
        "wyrmd.json5",
        "--out",
        "members.img",
    ]);
    ok(&out);
    assert_eq!(
        std::fs::read(dir.path("members.img")).unwrap(),
        std::fs::read(dir.path("out.img")).unwrap()
    );
    std::fs::remove_file(dir.path("members.img")).unwrap();
    std::fs::remove_file(dir.path("members.img.gz")).unwrap();

    // a cut download is refused
    let before = {
        std::fs::remove_file(dir.path("out.img")).unwrap();
        dir.write("base.img.gz", &gz[..gz.len() / 2]);
        dir.names()
    };
    let cut = dir.wyr(&[
        "image",
        "build",
        "--image",
        "base.img.gz",
        "--index",
        "index.json",
        "--board",
        "rpi4",
        "--config",
        "wyrmd.json5",
        "--out",
        "out.img",
    ]);
    refused(&cut);
    assert_eq!(dir.names(), before);
}

#[test]
fn inspect_hides_the_setup_hash() {
    let dir = Dir::new("inspect");
    let inspect = |image: &str| {
        dir.wyr(&[
            "image",
            "inspect",
            "--image",
            image,
            "--index",
            "index.json",
            "--board",
            "rpi4",
        ])
    };
    let empty = inspect("base.img");
    assert_eq!(ok(&empty), "board: rpi4\nregion: empty\n");

    dir.write("keys", KEYS);
    dir.write("setup.hash", SETUP);
    ok(&dir.build(&[
        "--setup-hash-file",
        "setup.hash",
        "--authorized-keys",
        "keys",
        "--timezone",
        "Europe/Kyiv",
    ]));
    let full = inspect("out.img");
    let stdout = ok(&full);
    assert_eq!(
        stdout,
        format!(
            "board: rpi4\nregion: assembled\nwyrmd.json5 {}\nsetup 64\nauthorized_keys {}\ntimezone 12\n",
            CONFIG.len(),
            KEYS.len()
        )
    );
    let all = format!("{stdout}{}", text(&full.stderr));
    assert!(!all.contains(SETUP) && !all.contains(&SETUP[..16]));
    assert!(!all.contains("OnlyThePersonsKey") && !all.contains("person@host"));
    assert!(!all.contains("plant"), "no content of any file");

    // a file that is no image of the board, and a damaged region
    dir.write("other.img", vec![7u8; SIZE]);
    assert!(refused(&inspect("other.img")).contains("no config region"));
    let mut damaged = std::fs::read(dir.path("out.img")).unwrap();
    damaged[OFFSET + 100] ^= 1;
    dir.write("damaged.img", &damaged);
    assert!(refused(&inspect("damaged.img")).contains("damaged"));
    dir.write("short.img", &base()[..SIZE - 512]);
    assert!(refused(&inspect("short.img")).contains("is not an image of board `rpi4`"));
}
