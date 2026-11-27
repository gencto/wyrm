//! The config region of a WYRM board image and the index of base images (ADR 0051 §4).
//!
//! CI builds one base image per board with a reserved region of [`CONFIG_SIZE`] bytes. The
//! person's tool (`wyr image build`, later a page that runs this crate as WebAssembly) writes
//! the chosen configuration into that region, and a shell script on the device reads it on the
//! first boot. This crate is the one implementation of the format on the writing side.
//!
//! The crate is pure. It does no I/O, reads no clock and draws no randomness, and builds for
//! `wasm32-unknown-unknown`: a caller gives bytes and writes bytes.
//!
//! # The region
//!
//! ```text
//! offset  size  content
//!      0     8  magic: "WYRMCFG1" (a configuration) or "WYRMCFG0" (empty)
//!      8     8  payload length, u64 little-endian
//!     16    32  SHA-256 of the payload
//!     48     n  payload: a ustar archive
//!   48+n     …  zeros, to CONFIG_SIZE
//! ```
//!
//! An empty region is `WYRMCFG0` and zeros. The archive holds regular files only, by these
//! names and nothing else: `wyrmd.json5` (required), `network`, `seed.json`, `setup`,
//! `authorized_keys`, `timezone`, `ntp`.
//!
//! The device puts `setup` at [`SETUP_FILE`] and `seed.json` into [`SEED_DIR`]. A configuration
//! with one of them must name that path in its `wyrmd.json5` (`gateway.setup_file`,
//! `packages.seed_dir`), or the broker never reads the file: [`ImageError::NotNamed`].
//!
//! The device refuses what its scripts do not take, and some of it only after the region is
//! applied: an assembler checks the site, `data_dir`, `timezone` and `ntp` by the device's
//! rules ([`ConfigFiles::check_device`]).
//!
//! The region is found by the offset the signed index records for the image
//! ([`ImageEntry::config_offset`]), never by a partition label. Before it writes, an assembler
//! checks the image against its entry ([`ImageEntry::matches`]) and the eight bytes at the
//! offset ([`check_slot`]).

mod device;
mod index;
mod names;
mod region;
mod tar;

pub use device::{plain_site, site_of, DATA_DIR, NTP_MAX, SITE_MAX};
pub use index::{Download, ImageEntry, Index, IndexError, FORMAT};
pub use region::{
    check_slot, read_region, region, ConfigFiles, CONFIG_SIZE, HEADER_SIZE, MAGIC_EMPTY,
    MAGIC_FULL, MAX_PAYLOAD, SEED_DIR, SETUP_FILE,
};

/// Why a config region, its files or an index of images are refused.
#[derive(Debug, thiserror::Error)]
pub enum ImageError {
    /// The archive of the files is larger than [`MAX_PAYLOAD`].
    #[error("the configuration does not fit the config region: its archive may take {MAX_PAYLOAD} bytes")]
    TooLarge,
    /// An entry of the archive that is not one of the files: its name is outside the list
    /// (a path, `..`, another name), it comes twice or it is no regular file. Also the
    /// required `wyrmd.json5` when the archive does not hold it.
    #[error("the config archive is refused at `{0}`: it holds regular files of the listed names, each once, and `wyrmd.json5` is required")]
    BadName(String),
    /// `setup` is not 64 hex digits.
    #[error("`setup` is not the SHA-256 of a setup code (64 hex digits)")]
    BadSetup,
    /// The file of this name is not text: it holds a NUL or is not UTF-8. For `wyrmd.json5`
    /// also: it is empty.
    #[error("the content of `{0}` is refused: a file is UTF-8 text without NUL, and `wyrmd.json5` is not empty")]
    BadContent(&'static str),
    /// The configuration carries `file`, and `wyrmd.json5` does not name the path where the
    /// device puts it: the broker would never read it.
    #[error("`{file}` is in the configuration, but `wyrmd.json5` does not say `{key}: \"{path}\"`: the device puts the file there, and the broker reads it only from where its configuration says")]
    NotNamed {
        /// The file of the archive.
        file: &'static str,
        /// The key of `wyrmd.json5`, with its section.
        key: &'static str,
        /// The path the key must name.
        path: &'static str,
    },
    /// `wyrmd.json5` names no site the device takes: the outermost object has no member
    /// `site`, has it twice, or its value is no plain name ([`plain_site`]).
    #[error("`wyrmd.json5` names no site a board takes: say `site: \"<name>\"` once in the outermost object, 1 to {SITE_MAX} of A-Z a-z 0-9 _ . -, not starting with `.`")]
    Site,
    /// The outermost object of `wyrmd.json5` does not say `data_dir: "/srv/wyrm"`, where the
    /// data partition of a board is mounted.
    #[error("`wyrmd.json5` must say `data_dir: \"{DATA_DIR}\"` in its outermost object: the data partition of a board is mounted there")]
    DataDir,
    /// `timezone` is not one IANA name as the device takes it.
    #[error("`timezone` is not one IANA name: one word of A-Z a-z 0-9 _ + / -, not starting with `/`, without `..` (`Europe/Kyiv`)")]
    Timezone,
    /// `ntp` holds a line the device does not take, or more than [`NTP_MAX`] servers.
    #[error("`ntp` is refused: at most {NTP_MAX} servers, each a host name or an address of A-Z a-z 0-9 . : _ -, not starting with `-` (an IPv6 address without brackets)")]
    Ntp,
    /// Neither magic is at the offset: this is not the config region of a WYRM image.
    #[error("no config region here: neither `WYRMCFG1` nor `WYRMCFG0` at the offset")]
    NoRegion,
    /// The region has a magic and does not follow the format: a wrong size, a length that does
    /// not fit, a SHA-256 that does not match, bytes where zeros belong or a broken archive.
    #[error("the config region is damaged")]
    Damaged,
    /// The index of images is refused.
    #[error("index of images: {0}")]
    Index(#[from] IndexError),
}
