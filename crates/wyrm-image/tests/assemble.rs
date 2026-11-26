//! The config region of a board image (ADR 0051 §4): what an assembler writes, what a reader
//! takes back and what both refuse. The hand-built archives below are written by this file's
//! own ustar writer, so they do not depend on the crate's.

#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    clippy::panic,
    clippy::unreachable,
    clippy::print_stdout,
    reason = "test code: a failed step fails the test"
)]

use wyrm_core::hex::sha256;
use wyrm_image::{
    check_slot, read_region, region, ConfigFiles, ImageError, Index, IndexError, CONFIG_SIZE,
    HEADER_SIZE, MAGIC_EMPTY, MAGIC_FULL, MAX_PAYLOAD,
};

const SETUP: &str = "3f0a9c1e5b7d2468ace013579bdf02468ace13579bdf0246813579bdf02468ac";

fn size() -> usize {
    usize::try_from(CONFIG_SIZE).unwrap()
}

fn all_files() -> ConfigFiles {
    ConfigFiles {
        wyrmd_json5: "{ site: \"plant\", gateway: { tls: \"site_ca\" } }\n".into(),
        network: Some("config interface 'lan'\n\toption proto 'dhcp'\n".into()),
        seed_json: Some("{\"format\":\"wyrm-seed/1\",\"links\":[]}".into()),
        setup: Some(SETUP.into()),
        authorized_keys: Some("ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIA person@host\n".into()),
        timezone: Some("Europe/Kyiv".into()),
        ntp: Some("0.openwrt.pool.ntp.org\n1.openwrt.pool.ntp.org\n".into()),
    }
}

fn only(config: &str) -> ConfigFiles {
    ConfigFiles {
        wyrmd_json5: config.into(),
        network: None,
        seed_json: None,
        setup: None,
        authorized_keys: None,
        timezone: None,
        ntp: None,
    }
}

/// One ustar entry: the header and the data padded to a block.
fn entry(name: &str, typeflag: u8, data: &[u8]) -> Vec<u8> {
    let mut h = [0u8; 512];
    h[..name.len()].copy_from_slice(name.as_bytes());
    h[100..108].copy_from_slice(b"0000600\0");
    h[108..116].copy_from_slice(b"0000000\0");
    h[116..124].copy_from_slice(b"0000000\0");
    h[124..136].copy_from_slice(format!("{:011o}\0", data.len()).as_bytes());
    h[136..148].copy_from_slice(b"00000000000\0");
    h[148..156].copy_from_slice(b"        ");
    h[156] = typeflag;
    h[257..263].copy_from_slice(b"ustar\0");
    h[263..265].copy_from_slice(b"00");
    let sum: u32 = h.iter().map(|b| u32::from(*b)).sum();
    h[148..156].copy_from_slice(format!("{sum:06o}\0 ").as_bytes());
    let mut out = h.to_vec();
    out.extend_from_slice(data);
    out.resize(out.len().div_ceil(512) * 512, 0);
    out
}

fn archive(entries: &[Vec<u8>]) -> Vec<u8> {
    let mut out = entries.concat();
    out.resize(out.len() + 1024, 0);
    out
}

/// A full region around any payload, as the format says.
fn wrap(payload: &[u8]) -> Vec<u8> {
    let mut out = Vec::with_capacity(size());
    out.extend_from_slice(MAGIC_FULL);
    out.extend_from_slice(&u64::try_from(payload.len()).unwrap().to_le_bytes());
    out.extend_from_slice(&sha256(payload));
    out.extend_from_slice(payload);
    out.resize(size(), 0);
    out
}

fn empty_region() -> Vec<u8> {
    let mut out = MAGIC_EMPTY.to_vec();
    out.resize(size(), 0);
    out
}

fn payload_of(region: &[u8]) -> &[u8] {
    let len = u64::from_le_bytes(region[8..16].try_into().unwrap());
    &region[48..48 + usize::try_from(len).unwrap()]
}

#[test]
fn region_round_trips() {
    let files = all_files();
    let bytes = region(&files).unwrap();
    assert_eq!(bytes.len(), size());
    assert_eq!(&bytes[..8], MAGIC_FULL);
    assert_eq!(bytes[16..48], sha256(payload_of(&bytes)));
    assert_eq!(read_region(&bytes).unwrap(), Some(files));

    // only the required file
    let one = only("{}\n");
    assert_eq!(read_region(&region(&one).unwrap()).unwrap(), Some(one));
    // the same files give the same bytes: no clock and no randomness in the archive
    assert_eq!(region(&all_files()).unwrap(), bytes);
}

#[test]
fn the_layout_is_the_documented_one() {
    assert_eq!(CONFIG_SIZE, 4 * 1024 * 1024);
    assert_eq!(HEADER_SIZE, 48);
    assert_eq!(MAX_PAYLOAD, CONFIG_SIZE - 48);
    assert_eq!(MAGIC_FULL, b"WYRMCFG1");
    assert_eq!(MAGIC_EMPTY, b"WYRMCFG0");

    // a region written by hand around a hand-built archive reads as its files
    let hand = wrap(&archive(&[
        entry("wyrmd.json5", b'0', b"{}\n"),
        entry("setup", b'0', format!("{SETUP}\n").as_bytes()),
        entry("timezone", 0, b"UTC"),
    ]));
    let read = read_region(&hand).unwrap().unwrap();
    assert_eq!(read.wyrmd_json5, "{}\n");
    assert_eq!(read.setup.as_deref(), Some(SETUP));
    assert_eq!(read.timezone.as_deref(), Some("UTC"));
    assert_eq!(read.network, None);

    // the archive is `wyrmd.json5` first, then the others in the order of the list, mode 0600
    let bytes = region(&all_files()).unwrap();
    let payload = payload_of(&bytes);
    assert_eq!(payload.len() % 512, 0);
    assert_eq!(&payload[..12], b"wyrmd.json5\0");
    assert_eq!(&payload[100..108], b"0000600\0");
    assert_eq!(&payload[257..265], b"ustar\x0000");
    assert!(payload[payload.len() - 1024..].iter().all(|b| *b == 0));
    // `setup` is written as its 64 characters and one newline
    let at = payload
        .windows(SETUP.len() + 1)
        .position(|w| w == format!("{SETUP}\n").as_bytes());
    assert!(at.is_some());
}

#[test]
fn the_system_tar_lists_the_archive() {
    let bytes = region(&all_files()).unwrap();
    let dir = std::env::temp_dir().join(format!("wyrm-image-test-{}", std::process::id()));
    std::fs::create_dir_all(&dir).unwrap();
    let file = dir.join("config.tar");
    std::fs::write(&file, payload_of(&bytes)).unwrap();
    let listed = std::process::Command::new("tar")
        .arg("-tf")
        .arg(&file)
        .output();
    let out = dir.join("out");
    std::fs::create_dir_all(&out).unwrap();
    let unpacked = std::process::Command::new("tar")
        .arg("-xf")
        .arg(&file)
        .arg("-C")
        .arg(&out)
        .output();
    let setup = std::fs::read_to_string(out.join("setup"));
    let ntp = std::fs::read_to_string(out.join("ntp"));
    std::fs::remove_dir_all(&dir).unwrap();
    let (Ok(listed), Ok(unpacked)) = (listed, unpacked) else {
        println!("no `tar` on this host: the listing is not checked");
        return;
    };
    assert!(listed.status.success(), "{listed:?}");
    assert!(listed.stderr.is_empty(), "{listed:?}");
    let names: Vec<&str> = std::str::from_utf8(&listed.stdout)
        .unwrap()
        .lines()
        .collect();
    assert_eq!(
        names,
        [
            "wyrmd.json5",
            "network",
            "seed.json",
            "setup",
            "authorized_keys",
            "timezone",
            "ntp"
        ]
    );
    assert!(unpacked.status.success(), "{unpacked:?}");
    assert_eq!(setup.unwrap(), format!("{SETUP}\n"));
    assert_eq!(ntp.unwrap(), all_files().ntp.unwrap());
}

#[test]
fn empty_region_reads_as_none() {
    assert_eq!(read_region(&empty_region()).unwrap(), None);

    // an empty region is its magic and zeros, nothing else
    let mut dirty = empty_region();
    dirty[4096] = 1;
    assert!(matches!(read_region(&dirty), Err(ImageError::Damaged)));
    // a region is exactly CONFIG_SIZE bytes
    let short = &empty_region()[..size() - 1];
    assert!(matches!(read_region(short), Err(ImageError::Damaged)));
    let mut long = empty_region();
    long.push(0);
    assert!(matches!(read_region(&long), Err(ImageError::Damaged)));
    // neither magic: this is not a config region
    let mut other = empty_region();
    other[..8].copy_from_slice(b"\x1f\x8b\x08\0\0\0\0\0");
    assert!(matches!(read_region(&other), Err(ImageError::NoRegion)));
    assert!(matches!(
        read_region(&vec![0u8; size()]),
        Err(ImageError::NoRegion)
    ));
}

#[test]
fn a_region_too_large_is_refused() {
    let big = only(&"x".repeat(size() + 1));
    assert!(matches!(big.check(), Err(ImageError::TooLarge)));
    assert!(matches!(region(&big), Err(ImageError::TooLarge)));

    // the limit is the payload, CONFIG_SIZE - 48: one header block, the data, two end blocks
    let room = usize::try_from(MAX_PAYLOAD).unwrap() / 512 * 512 - 512 - 1024;
    let fits = only(&"x".repeat(room));
    let bytes = region(&fits).unwrap();
    assert_eq!(bytes.len(), size());
    assert_eq!(read_region(&bytes).unwrap(), Some(fits));
    let over = only(&"x".repeat(room + 1));
    assert!(matches!(region(&over), Err(ImageError::TooLarge)));

    // a reader refuses a length that does not fit the region
    let mut lying = region(&only("{}")).unwrap();
    lying[8..16].copy_from_slice(&(MAX_PAYLOAD + 1).to_le_bytes());
    assert!(matches!(read_region(&lying), Err(ImageError::Damaged)));
    lying[8..16].copy_from_slice(&u64::MAX.to_le_bytes());
    assert!(matches!(read_region(&lying), Err(ImageError::Damaged)));
}

#[test]
fn names_outside_the_list_are_refused() {
    let config = || entry("wyrmd.json5", b'0', b"{}");
    let refused = |entries: &[Vec<u8>]| match read_region(&wrap(&archive(entries))) {
        Err(ImageError::BadName(name)) => name,
        other => panic!("not refused by name: {other:?}"),
    };
    assert_eq!(refused(&[config(), entry("../x", b'0', b"x")]), "../x");
    assert_eq!(refused(&[config(), entry("extra", b'0', b"x")]), "extra");
    assert_eq!(
        refused(&[config(), entry("/network", b'0', b"x")]),
        "/network"
    );
    assert_eq!(
        refused(&[config(), entry("./network", b'0', b"x")]),
        "./network"
    );
    assert_eq!(
        refused(&[config(), entry("etc/network", b'0', b"x")]),
        "etc/network"
    );
    assert_eq!(refused(&[config(), entry("..", b'0', b"x")]), "..");
    assert_eq!(
        refused(&[config(), entry("NETWORK", b'0', b"x")]),
        "NETWORK"
    );
    assert_eq!(refused(&[config(), entry("", b'0', b"x")]), "");
    // a name of the list that is no regular file: a symlink, a hard link, a directory, a pax header
    for flag in *b"1235xgL" {
        assert_eq!(refused(&[config(), entry("network", flag, b"")]), "network");
    }
    // a name twice
    assert_eq!(
        refused(&[config(), entry("ntp", b'0', b"a"), entry("ntp", b'0', b"b")]),
        "ntp"
    );
    assert_eq!(refused(&[config(), config()]), "wyrmd.json5");
    // a ustar prefix is a directory before the name
    let mut prefixed = entry("network", b'0', b"x");
    prefixed[345..348].copy_from_slice(b"etc");
    prefixed[148..156].copy_from_slice(b"        ");
    let sum: u32 = prefixed[..512].iter().map(|b| u32::from(*b)).sum();
    prefixed[148..156].copy_from_slice(format!("{sum:06o}\0 ").as_bytes());
    assert_eq!(refused(&[config(), prefixed]), "etc/network");

    // no `wyrmd.json5`: the name that is missing is named
    assert_eq!(refused(&[entry("network", b'0', b"x")]), "wyrmd.json5");
    assert_eq!(refused(&[]), "wyrmd.json5");
}

#[test]
fn a_bad_setup_is_refused() {
    for setup in [
        "",
        "abc",
        &SETUP[1..],
        &format!("{SETUP}0"),
        &format!("{SETUP}\n"),
        &SETUP.replace('3', "g"),
        &format!(" {}", &SETUP[1..]),
    ] {
        let mut files = only("{}");
        files.setup = Some(setup.to_owned());
        assert!(
            matches!(files.check(), Err(ImageError::BadSetup)),
            "{setup:?}"
        );
        assert!(matches!(region(&files), Err(ImageError::BadSetup)));
    }
    let mut upper = only("{}");
    upper.setup = Some(SETUP.to_uppercase());
    assert_eq!(read_region(&region(&upper).unwrap()).unwrap(), Some(upper));

    // a reader takes the hash with or without its one newline, and nothing else
    let read = |setup: &[u8]| {
        read_region(&wrap(&archive(&[
            entry("wyrmd.json5", b'0', b"{}"),
            entry("setup", b'0', setup),
        ])))
    };
    assert_eq!(
        read(SETUP.as_bytes()).unwrap().unwrap().setup.unwrap(),
        SETUP
    );
    assert!(matches!(
        read(format!("{SETUP}\n\n").as_bytes()),
        Err(ImageError::BadSetup)
    ));
    assert!(matches!(read(b"1234\n"), Err(ImageError::BadSetup)));
}

#[test]
fn content_that_is_no_text_is_refused() {
    let mut files = all_files();
    files.network = Some("config\0interface".into());
    assert!(matches!(
        files.check(),
        Err(ImageError::BadContent("network"))
    ));
    assert!(matches!(
        region(&files),
        Err(ImageError::BadContent("network"))
    ));
    assert!(matches!(
        only("").check(),
        Err(ImageError::BadContent("wyrmd.json5"))
    ));

    let read = |data: &[u8]| read_region(&wrap(&archive(&[entry("wyrmd.json5", b'0', data)])));
    assert!(matches!(
        read(b"{\0}"),
        Err(ImageError::BadContent("wyrmd.json5"))
    ));
    assert!(matches!(
        read(b"\xff\xfe"),
        Err(ImageError::BadContent("wyrmd.json5"))
    ));
    assert!(matches!(
        read(b""),
        Err(ImageError::BadContent("wyrmd.json5"))
    ));
}

#[test]
fn a_flipped_byte_is_damaged() {
    let good = region(&all_files()).unwrap();
    let len = payload_of(&good).len();
    // the length, the hash, the first and the last byte of the payload, a name, the padding
    for at in [
        8,
        15,
        16,
        47,
        48,
        48 + 2,
        48 + 600,
        48 + len - 1,
        48 + len,
        size() - 1,
    ] {
        let mut bad = good.clone();
        bad[at] ^= 0x01;
        assert!(
            matches!(read_region(&bad), Err(ImageError::Damaged)),
            "byte {at}"
        );
    }
    let mut magic = good.clone();
    magic[7] ^= 0x04;
    assert!(matches!(read_region(&magic), Err(ImageError::NoRegion)));

    // an archive with the right hash that is no archive
    let damaged = |payload: &[u8]| matches!(read_region(&wrap(payload)), Err(ImageError::Damaged));
    assert!(damaged(b"not a tar"));
    assert!(damaged(&[b'x'; 512]));
    // a header whose checksum is wrong
    let mut sum = archive(&[entry("wyrmd.json5", b'0', b"{}")]);
    sum[110] ^= 0x01;
    assert!(damaged(&sum));
    // no end blocks, one end block, bytes after the end
    let one = entry("wyrmd.json5", b'0', b"{}");
    assert!(damaged(&one));
    let mut single = one.clone();
    single.resize(one.len() + 512, 0);
    assert!(damaged(&single));
    let mut tail = archive(std::slice::from_ref(&one));
    tail.extend_from_slice(&entry("network", b'0', b"x"));
    assert!(damaged(&tail));
    // a size that runs past the payload
    let mut long = entry("wyrmd.json5", b'0', b"{}");
    long[124..136].copy_from_slice(b"00000777777\0");
    long[148..156].copy_from_slice(b"        ");
    let s: u32 = long[..512].iter().map(|b| u32::from(*b)).sum();
    long[148..156].copy_from_slice(format!("{s:06o}\0 ").as_bytes());
    assert!(damaged(&archive(&[long])));
    // an empty payload
    assert!(damaged(b""));
}

#[test]
fn check_slot_knows_both_magics() {
    assert!(check_slot(MAGIC_FULL).is_ok());
    assert!(check_slot(MAGIC_EMPTY).is_ok());
    for other in [
        b"WYRMCFG2",
        b"wyrmcfg1",
        b"\0\0\0\0\0\0\0\0",
        b"\x1f\x8b\x08\0\0\0\0\0",
    ] {
        assert!(matches!(check_slot(other), Err(ImageError::NoRegion)));
    }
    // the first bytes of what the crate writes pass
    let full = region(&only("{}")).unwrap();
    assert!(check_slot(full[..8].try_into().unwrap()).is_ok());
}

const INDEX: &str = r#"{
  "format": "wyrm-images/1",
  "images": [
    {"board": "rpi4", "file": "wyrm-0.9.0-rpi4.img", "size": 268435456,
     "sha256": "9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08",
     "config_offset": 67108864, "openwrt": "24.10.4", "wyrmd": "0.9.0"},
    {"board": "bpi-r4", "file": "wyrm-0.9.0-bpi-r4.img", "size": 536870912,
     "sha256": "2c26b46b68ffc68ff99b453c1d30413413422d706483bfa0f98a5e886266e7ae",
     "config_offset": 532676608, "openwrt": "24.10.4", "wyrmd": "0.9.0", "later": true}
  ]
}"#;

#[test]
fn index_parses_and_refuses_another_format() {
    let index = Index::parse(INDEX).unwrap();
    assert_eq!(index.format, "wyrm-images/1");
    assert_eq!(index.images.len(), 2);
    let rpi4 = index.image("rpi4").unwrap();
    assert_eq!(rpi4.file, "wyrm-0.9.0-rpi4.img");
    assert_eq!(rpi4.size, 268_435_456);
    assert_eq!(rpi4.config_offset, 67_108_864);
    assert_eq!(rpi4.openwrt, "24.10.4");
    assert_eq!(rpi4.wyrmd, "0.9.0");
    assert!(index.image("rpi5").is_none());
    // the region of the second image ends exactly at the end of the image
    assert_eq!(
        index.image("bpi-r4").unwrap().config_offset + CONFIG_SIZE,
        536_870_912
    );

    // an image is the one of its entry by size and SHA-256
    assert!(rpi4.matches(268_435_456, &sha256(b"test")));
    assert!(!rpi4.matches(268_435_457, &sha256(b"test")));
    assert!(!rpi4.matches(268_435_456, &sha256(b"tesu")));

    // written and read back
    let again = Index::parse(&serde_json::to_string(&index).unwrap()).unwrap();
    assert_eq!(again, index);

    let refused = |text: &str| match Index::parse(text) {
        Err(ImageError::Index(e)) => e,
        other => panic!("not refused: {other:?}"),
    };
    assert!(matches!(
        refused(&INDEX.replace("wyrm-images/1", "wyrm-images/2")),
        IndexError::Format(f) if f == "wyrm-images/2"
    ));
    assert!(matches!(
        refused(r#"{"format": "wyrm-seed/1", "images": []}"#),
        IndexError::Format(_)
    ));
    assert!(matches!(refused("{"), IndexError::Json(_)));
    assert!(matches!(refused(r#"{"images": []}"#), IndexError::Json(_)));
    // an entry without its offset
    assert!(matches!(
        refused(&INDEX.replace("\"config_offset\": 67108864,", "")),
        IndexError::Json(_)
    ));
    // a region that does not lie inside its image
    assert!(matches!(
        refused(&INDEX.replace("\"config_offset\": 532676608", "\"config_offset\": 532676609")),
        IndexError::Outside(board) if board == "bpi-r4"
    ));
    assert!(matches!(
        refused(&INDEX.replace("67108864", "18446744073709551615")),
        IndexError::Outside(board) if board == "rpi4"
    ));
    // a hash that is not 64 lower-case hex digits
    assert!(matches!(
        refused(&INDEX.replace("9f86d081", "9F86D081")),
        IndexError::BadHash(board) if board == "rpi4"
    ));
    assert!(matches!(
        refused(&INDEX.replace("9f86d081", "9f86d08")),
        IndexError::BadHash(_)
    ));
    // a board twice, a board or a file without a name
    assert!(matches!(
        refused(&INDEX.replace("\"bpi-r4\"", "\"rpi4\"")),
        IndexError::Twice(board) if board == "rpi4"
    ));
    assert!(matches!(
        refused(&INDEX.replace("\"rpi4\"", "\"\"")),
        IndexError::NoName
    ));
    assert!(matches!(
        refused(&INDEX.replace("wyrm-0.9.0-rpi4.img", "")),
        IndexError::NoName
    ));
}

#[test]
fn index_names_are_plain_file_names() {
    let refused = |text: &str| match Index::parse(text) {
        Err(ImageError::Index(e)) => e,
        other => panic!("not refused: {other:?}"),
    };
    // a file or a board that is a path: an assembler and a page join it to a directory
    for bad in [
        "../wyrm.img",
        "a/wyrm.img",
        "/wyrm.img",
        "a\\wyrm.img",
        "..",
        "wyrm..img",
    ] {
        let text = INDEX.replace("wyrm-0.9.0-rpi4.img", &bad.replace('\\', "\\\\"));
        assert!(
            matches!(refused(&text), IndexError::BadName(name) if name == bad),
            "file {bad}"
        );
        let text = INDEX.replace("\"rpi4\"", &format!("\"{}\"", bad.replace('\\', "\\\\")));
        assert!(
            matches!(refused(&text), IndexError::BadName(name) if name == bad),
            "board {bad}"
        );
    }
}

#[test]
fn index_download_is_optional_and_checked() {
    // without it: `None`, and it is not written back
    let index = Index::parse(INDEX).unwrap();
    assert!(index.images.iter().all(|image| image.download.is_none()));
    assert!(!serde_json::to_string(&index).unwrap().contains("download"));

    let with = |download: &str| {
        INDEX.replace(
            "\"openwrt\": \"24.10.4\", \"wyrmd\": \"0.9.0\"},",
            &format!("\"openwrt\": \"24.10.4\", \"wyrmd\": \"0.9.0\", \"download\": {download}}},"),
        )
    };
    const GZ: &str = r#"{"file": "wyrm-0.9.0-rpi4.img.gz", "size": 41943040,
        "sha256": "2c26b46b68ffc68ff99b453c1d30413413422d706483bfa0f98a5e886266e7ae"}"#;
    let index = Index::parse(&with(GZ)).unwrap();
    let download = index.image("rpi4").unwrap().download.as_ref().unwrap();
    assert_eq!(download.file, "wyrm-0.9.0-rpi4.img.gz");
    assert_eq!(download.size, 41_943_040);
    assert!(download.matches(41_943_040, &sha256(b"foo")));
    assert!(!download.matches(41_943_041, &sha256(b"foo")));
    assert!(!download.matches(41_943_040, &sha256(b"fop")));
    assert!(index.image("bpi-r4").unwrap().download.is_none());
    let again = Index::parse(&serde_json::to_string(&index).unwrap()).unwrap();
    assert_eq!(again, index);

    let refused = |text: &str| match Index::parse(text) {
        Err(ImageError::Index(e)) => e,
        other => panic!("not refused: {other:?}"),
    };
    assert!(matches!(
        refused(&with(&GZ.replace("wyrm-0.9.0-rpi4.img.gz", "../x.gz"))),
        IndexError::BadName(name) if name == "../x.gz"
    ));
    assert!(matches!(
        refused(&with(&GZ.replace("wyrm-0.9.0-rpi4.img.gz", ""))),
        IndexError::NoName
    ));
    assert!(matches!(
        refused(&with(&GZ.replace("2c26b46b", "2C26B46B"))),
        IndexError::BadHash(board) if board == "rpi4"
    ));
    assert!(matches!(
        refused(&with(r#"{"file": "x.gz"}"#)),
        IndexError::Json(_)
    ));
}

/// xorshift64*: the same mutations at every run.
struct Rng(u64);

impl Rng {
    fn next(&mut self) -> u64 {
        self.0 ^= self.0 >> 12;
        self.0 ^= self.0 << 25;
        self.0 ^= self.0 >> 27;
        self.0.wrapping_mul(0x2545_F491_4F6C_DD1D)
    }

    fn below(&mut self, n: usize) -> usize {
        usize::try_from(self.next() % u64::try_from(n).unwrap()).unwrap()
    }
}

/// Sets the header of a region to its payload of `len` bytes, so a mutation of the archive
/// reaches the archive reader instead of ending at the SHA-256.
fn reseal(region: &mut [u8], len: usize) {
    let hash = sha256(&region[48..48 + len]);
    region[8..16].copy_from_slice(&u64::try_from(len).unwrap().to_le_bytes());
    region[16..48].copy_from_slice(&hash);
}

/// Sets the checksum of the ustar header at `at`, so a mutation of the header is read.
fn fix_checksum(region: &mut [u8], at: usize) {
    region[at + 148..at + 156].copy_from_slice(b"        ");
    let sum: u32 = region[at..at + 512].iter().map(|b| u32::from(*b)).sum();
    region[at + 148..at + 156].copy_from_slice(format!("{sum:06o}\0 ").as_bytes());
}

/// A reader never panics, whatever the bytes: every mutation of a good region is read to an
/// answer. The answer itself is not judged here (the tests above do), except that a region
/// that still reads holds a configuration `check` passes.
#[test]
fn mutations_never_panic() {
    // 300 of each of the eight kinds
    const ROUNDS: u32 = 2400;
    let good = region(&all_files()).unwrap();
    let len = payload_of(&good).len();
    let headers: Vec<usize> = {
        // the offsets of the ustar headers: each entry is its header and its data in blocks
        let mut at = 48;
        let mut out = Vec::new();
        while good[at] != 0 {
            out.push(at);
            let size = std::str::from_utf8(&good[at + 124..at + 135]).unwrap();
            let size = usize::from_str_radix(size, 8).unwrap();
            at += 512 + size.div_ceil(512) * 512;
        }
        out
    };
    assert_eq!(headers.len(), 7);
    let mut rng = Rng(0x9E37_79B9_7F4A_7C15);
    let mut read = 0u32;
    let mut refused = 0u32;
    let mut go = |bytes: &[u8]| match read_region(bytes) {
        Ok(Some(files)) => {
            files.check().unwrap();
            read += 1;
        }
        Ok(None) => read += 1,
        Err(_) => refused += 1,
    };
    for round in 0..ROUNDS {
        let mut bad = good.clone();
        match round % 8 {
            // a flipped bit of the header
            0 => bad[rng.below(48)] ^= 1 << rng.below(8),
            // a flipped bit anywhere in the used part
            1 => bad[rng.below(48 + len + 64)] ^= 1 << rng.below(8),
            // truncated input, from nothing to one byte short (and now and then too long)
            2 => {
                let to = match rng.below(4) {
                    0 => rng.below(64),
                    1 => 48 + rng.below(len),
                    2 => size() - 1 - rng.below(16),
                    _ => size() + 1 + rng.below(16),
                };
                bad.resize(to, 0);
            }
            // a lying length: any u64, or near the true one and the bounds
            3 => {
                let lie = match rng.below(4) {
                    0 => rng.next(),
                    1 => u64::try_from(len + rng.below(1024)).unwrap() - 512,
                    2 => MAX_PAYLOAD - 8 + u64::try_from(rng.below(16)).unwrap(),
                    _ => u64::MAX - u64::try_from(rng.below(64)).unwrap(),
                };
                bad[8..16].copy_from_slice(&lie.to_le_bytes());
            }
            // a lying length with a hash that fits it: the archive reader gets a cut archive
            4 => {
                let lie = rng.below(len + 2048);
                reseal(&mut bad, lie);
            }
            // a damaged tar size field under a right checksum and a right hash
            5 => {
                let at = headers[rng.below(headers.len())];
                let mut random = [0u8; 12];
                random[..8].copy_from_slice(&rng.next().to_le_bytes());
                random[8..].copy_from_slice(&rng.next().to_le_bytes()[..4]);
                let field: &[u8; 12] = match rng.below(6) {
                    0 => b"77777777777\0",
                    1 => b"00000000000\0",
                    2 => b"\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff",
                    3 => b"\x80\0\0\0\x7f\xff\xff\xff\xff\xff\xff\xff",
                    4 => b"           \0",
                    _ => &random,
                };
                bad[at + 124..at + 136].copy_from_slice(field);
                fix_checksum(&mut bad, at);
                reseal(&mut bad, len);
            }
            // any byte of a tar header under a right checksum and a right hash
            6 => {
                let at = headers[rng.below(headers.len())];
                let byte = u8::try_from(rng.below(256)).unwrap();
                bad[at + rng.below(512)] = byte;
                fix_checksum(&mut bad, at);
                reseal(&mut bad, len);
            }
            // a run of random bytes in the archive under a right hash
            _ => {
                let from = 48 + rng.below(len);
                let run = rng.below(700).min(48 + len - from);
                for b in &mut bad[from..from + run] {
                    *b = u8::try_from(rng.below(256)).unwrap();
                }
                reseal(&mut bad, len);
            }
        }
        go(&bad);
    }
    // both happen: the mutations reach the reader behind the hash, and most are refused
    assert_eq!(read + refused, ROUNDS);
    assert!(refused > ROUNDS / 2, "{refused} refused");
    assert!(read > 0, "{read} read");
}
