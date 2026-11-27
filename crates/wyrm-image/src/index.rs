//! The index of base images: one entry per board, with what an assembler checks before it
//! writes (the image's size and SHA-256) and where the config region is. The index is a JSON
//! file published beside the images; its signature is checked by the caller, over the bytes of
//! the file, before the text comes here.

use serde::{Deserialize, Serialize};
use wyrm_core::hex;

use crate::region::CONFIG_SIZE;
use crate::ImageError;

/// The format name of an index this crate reads.
pub const FORMAT: &str = "wyrm-images/1";

/// One base image.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ImageEntry {
    /// The board id, as in `boards.json`.
    pub board: String,
    /// The image's file name beside the index. It is the raw image, not compressed:
    /// `config_offset` counts in these bytes.
    pub file: String,
    /// The size of the file, in bytes.
    pub size: u64,
    /// The SHA-256 of the file, 64 lower-case hex digits.
    pub sha256: String,
    /// Where the config region starts in the file.
    pub config_offset: u64,
    /// The OpenWrt release the image is built from.
    pub openwrt: String,
    /// The version of `wyrmd` in the image.
    pub wyrmd: String,
    /// The SHA-256 of the `wyrmd` binary in the image, 64 lower-case hex digits: which
    /// build of that version it is.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub wyrmd_sha256: Option<String>,
    /// The SHA-256 of the image's package manifest (the list of its packages with their
    /// versions, published beside the image). The packages of an OpenWrt release are
    /// signed, not pinned: two builds of one release may hold other package versions, and
    /// this tells them apart.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub manifest_sha256: Option<String>,
    /// The compressed file a page or a person downloads, when the image is published
    /// compressed. `file`, `size` and `sha256` above stay those of the raw image.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub download: Option<Download>,
    /// The board's name a person reads (`title` of `boards.json`).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub title: Option<String>,
    /// What a person is told about the board: how it boots, where the card goes (`notes`
    /// of `boards.json`).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub notes: Option<String>,
    /// The network ports of the interface `lan` in the image, as OpenWrt sets them up for
    /// the board. A static address is written onto them; without it, only DHCP.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub lan: Option<Lan>,
}

/// The ports of the interface `lan` of an image: one network device, or a bridge of
/// ports (OpenWrt bridges `lan` as `br-lan` even when it has one port).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(untagged, try_from = "LanFields")]
pub enum Lan {
    /// The interface is on this device.
    Device {
        /// The device, `eth0`.
        device: String,
    },
    /// The interface is on a bridge of these ports.
    Bridge {
        /// The bridge's name, `br-lan`.
        bridge: String,
        /// The ports of the bridge, at least one.
        ports: Vec<String>,
    },
}

/// The JSON of a [`Lan`]: `{"device"}` or `{"bridge", "ports"}`, nothing else. An object
/// with both shapes, or a field of neither, is refused rather than read as one of them.
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct LanFields {
    device: Option<String>,
    bridge: Option<String>,
    ports: Option<Vec<String>>,
}

/// A `lan` that is neither one device nor a bridge with its ports.
#[derive(Debug, thiserror::Error)]
#[error("`lan` is `{{\"device\"}}` or `{{\"bridge\", \"ports\"}}`, not both")]
struct NotOneShape;

impl TryFrom<LanFields> for Lan {
    type Error = NotOneShape;

    fn try_from(fields: LanFields) -> Result<Self, NotOneShape> {
        match fields {
            LanFields {
                device: Some(device),
                bridge: None,
                ports: None,
            } => Ok(Self::Device { device }),
            LanFields {
                device: None,
                bridge: Some(bridge),
                ports: Some(ports),
            } => Ok(Self::Bridge { bridge, ports }),
            _ => Err(NotOneShape),
        }
    }
}

/// The longest name of a network device in Linux (`IFNAMSIZ` less its NUL).
const IFNAME_MAX: usize = 15;

impl Lan {
    /// Every name is the name of a network device: 1 to 15 of `A-Z a-z 0-9 _ . -`, not
    /// starting with `.` or `-`, and a bridge has a port. A writer puts these names into
    /// the device's UCI text between quotes.
    pub fn is_plain(&self) -> bool {
        let name = |n: &String| {
            !n.is_empty()
                && n.len() <= IFNAME_MAX
                && !n.starts_with(['.', '-'])
                && n.chars()
                    .all(|c| c.is_ascii_alphanumeric() || "_.-".contains(c))
        };
        match self {
            Self::Device { device } => name(device),
            Self::Bridge { bridge, ports } => {
                name(bridge) && !ports.is_empty() && ports.iter().all(name)
            }
        }
    }
}

/// The compressed form of a base image, as it is published beside the index (gzip). Its size
/// and SHA-256 are those of the compressed file: a download is checked against them before
/// it is unpacked, and the unpacked bytes against the entry.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Download {
    /// The file name beside the index.
    pub file: String,
    /// The size of the compressed file, in bytes.
    pub size: u64,
    /// The SHA-256 of the compressed file, 64 lower-case hex digits.
    pub sha256: String,
    /// The gzip members of the file when it is written as three (head, region, tail): the
    /// head unpacks to the `config_offset` bytes before the region, the region member to
    /// the [`CONFIG_SIZE`] bytes of the empty region, the tail to the rest of the image
    /// (nothing, for an image that ends with its region). A page writes a configuration
    /// by putting a member of its own region between the head and the tail; the file stays
    /// a plain gzip file of the image for any reader that reads every member.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub members: Option<[Member; 3]>,
}

/// One gzip member of a [`Download`]: a byte range of the compressed file.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub struct Member {
    /// Where the member starts in the compressed file.
    pub offset: u64,
    /// Its size in the compressed file, in bytes.
    pub size: u64,
}

impl Download {
    /// The members follow each other from the start of the file to its end, none empty.
    fn members_tile(&self) -> bool {
        let Some(members) = &self.members else {
            return true;
        };
        let mut end = 0u64;
        for member in members {
            if member.offset != end || member.size == 0 {
                return false;
            }
            match end.checked_add(member.size) {
                Some(next) => end = next,
                None => return false,
            }
        }
        end == self.size
    }
}

impl Download {
    /// A downloaded file of this size and SHA-256 is the one of this entry.
    pub fn matches(&self, size: u64, sha256: &[u8; 32]) -> bool {
        size == self.size && hex::encode(sha256) == self.sha256
    }
}

impl ImageEntry {
    /// An image of this size and SHA-256 is the one of this entry. An assembler writes
    /// nothing into an image that is not: the offset is right for these bytes only.
    pub fn matches(&self, size: u64, sha256: &[u8; 32]) -> bool {
        size == self.size && hex::encode(sha256) == self.sha256
    }
}

/// The index of base images.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Index {
    /// [`FORMAT`].
    pub format: String,
    /// The images, one per board.
    pub images: Vec<ImageEntry>,
}

/// Why an index is refused.
#[derive(Debug, thiserror::Error)]
pub enum IndexError {
    /// Not JSON, or a field is missing or of another type.
    #[error("{0}")]
    Json(#[from] serde_json::Error),
    /// The index is of another format (the text is the format it names).
    #[error("format `{0}`, this build reads `{FORMAT}`")]
    Format(String),
    /// An entry without a board or without a file.
    #[error("an entry without a board or without a file")]
    NoName,
    /// A board or a file whose name is not a plain file name (the text is the name): it holds
    /// `/`, `\` or `..`. A reader joins these names to a directory or a URL.
    #[error("`{0}` is no plain name: a board and a file are named without `/`, `\\` and `..`")]
    BadName(String),
    /// Two entries for this board.
    #[error("board `{0}` is there twice")]
    Twice(String),
    /// A SHA-256 of this board's entry (the image raw or compressed, its `wyrmd`, its
    /// manifest) is not 64 lower-case hex digits.
    #[error("board `{0}`: a SHA-256 is not 64 lower-case hex digits")]
    BadHash(String),
    /// The config region of this board's image does not lie inside the image.
    #[error("board `{0}`: the config region does not lie inside the image")]
    Outside(String),
    /// The `lan` of this board's entry names no network device ([`Lan::is_plain`]).
    #[error("board `{0}`: `lan` names no network device (1 to 15 of A-Z a-z 0-9 _ . -, a bridge with ports)")]
    BadLan(String),
    /// The `members` of this board's `download` do not cover the compressed file exactly:
    /// the first starts at 0, each next one where the one before ends, none is empty, and
    /// the last ends at `download.size`.
    #[error("board `{0}`: the gzip members of the download do not cover the file from its start to its end")]
    Members(String),
}

/// A name a reader may join to a directory or a URL: not empty, no separator, no `..`.
fn plain_name(name: &str) -> Result<(), IndexError> {
    if name.is_empty() {
        return Err(IndexError::NoName);
    }
    if name.contains(['/', '\\']) || name.contains("..") {
        return Err(IndexError::BadName(name.to_owned()));
    }
    Ok(())
}

impl Index {
    /// Reads and checks an index ([`Index::check`]). Fields this build does not know are
    /// passed over.
    pub fn parse(text: &str) -> Result<Self, ImageError> {
        let index: Self = serde_json::from_str(text).map_err(IndexError::Json)?;
        index.check()?;
        Ok(index)
    }

    /// Checks the index: its format, one entry per board, each with a name, a file, a SHA-256
    /// and a config region of [`CONFIG_SIZE`] bytes inside the image. A board, a file and the
    /// file of a `download` are plain names: not empty, without `/`, `\` and `..`. A
    /// `download` has a SHA-256 too, and its `members`, when it names them, cover the file
    /// from its start to its end. A `lan` names network devices ([`Lan::is_plain`]).
    pub fn check(&self) -> Result<(), ImageError> {
        if self.format != FORMAT {
            return Err(IndexError::Format(self.format.clone()).into());
        }
        for (i, image) in self.images.iter().enumerate() {
            let board = || image.board.clone();
            let download = image.download.as_ref();
            let names = [
                Some(&image.board),
                Some(&image.file),
                download.map(|d| &d.file),
            ];
            for name in names.into_iter().flatten() {
                plain_name(name)?;
            }
            if self.images.iter().take(i).any(|e| e.board == image.board) {
                return Err(IndexError::Twice(board()).into());
            }
            let hashes = [
                Some(&image.sha256),
                download.map(|d| &d.sha256),
                image.wyrmd_sha256.as_ref(),
                image.manifest_sha256.as_ref(),
            ];
            if !hashes
                .into_iter()
                .flatten()
                .all(|h| hex::is_lower_hex(h, 32))
            {
                return Err(IndexError::BadHash(board()).into());
            }
            let inside = image
                .config_offset
                .checked_add(CONFIG_SIZE)
                .is_some_and(|end| end <= image.size);
            if !inside {
                return Err(IndexError::Outside(board()).into());
            }
            if image.lan.as_ref().is_some_and(|lan| !lan.is_plain()) {
                return Err(IndexError::BadLan(board()).into());
            }
            if download.is_some_and(|d| !d.members_tile()) {
                return Err(IndexError::Members(board()).into());
            }
        }
        Ok(())
    }

    /// The image of a board.
    pub fn image(&self, board: &str) -> Option<&ImageEntry> {
        self.images.iter().find(|image| image.board == board)
    }
}

#[cfg(test)]
mod tests {
    #![allow(
        clippy::unwrap_used,
        reason = "test code: a failed step fails the test"
    )]

    use super::*;

    fn with_members(members: [(u64, u64); 3], size: u64) -> Result<(), ImageError> {
        let index = Index {
            format: FORMAT.to_owned(),
            images: vec![ImageEntry {
                board: "rpi4".to_owned(),
                file: "wyrm-rpi4.img".to_owned(),
                size: 64 << 20,
                sha256: "ab".repeat(32),
                config_offset: 1 << 20,
                openwrt: "25.12.6".to_owned(),
                wyrmd: "0.9.0".to_owned(),
                wyrmd_sha256: None,
                manifest_sha256: None,
                download: Some(Download {
                    file: "wyrm-rpi4.img.gz".to_owned(),
                    size,
                    sha256: "cd".repeat(32),
                    members: Some(members.map(|(offset, size)| Member { offset, size })),
                }),
                title: None,
                notes: None,
                lan: None,
            }],
        };
        Index::parse(&serde_json::to_string(&index).unwrap()).map(drop)
    }

    #[test]
    fn members_must_tile_the_download() {
        with_members([(0, 1000), (1000, 4200), (5200, 20)], 5220).unwrap();
        let refused = |members, size| {
            assert!(
                matches!(
                    with_members(members, size),
                    Err(ImageError::Index(IndexError::Members(board))) if board == "rpi4"
                ),
                "{members:?} of {size}"
            );
        };
        // a gap, an overlap, a first member that does not start the file
        refused([(0, 1000), (1001, 4200), (5201, 20)], 5221);
        refused([(0, 1000), (999, 4200), (5199, 20)], 5219);
        refused([(10, 1000), (1010, 4200), (5210, 20)], 5230);
        // short of the file, past its end
        refused([(0, 1000), (1000, 4200), (5200, 20)], 5221);
        refused([(0, 1000), (1000, 4200), (5200, 20)], 5219);
        // an empty member is no gzip member
        refused([(0, 1000), (1000, 0), (1000, 20)], 1020);
        // a sum past u64
        refused([(0, u64::MAX), (u64::MAX, 2), (1, 0)], 1);
        // and an index without members still reads
        let plain = r#"{"format": "wyrm-images/1", "images": [{"board": "rpi4",
            "file": "a.img", "size": 8388608, "sha256": "abababababababababababababababababababababababababababababababab",
            "config_offset": 0, "openwrt": "25.12.6", "wyrmd": "0.9.0",
            "download": {"file": "a.img.gz", "size": 10,
              "sha256": "cdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcd"}}]}"#;
        let index = Index::parse(plain).unwrap();
        assert_eq!(index.images[0].download.as_ref().unwrap().members, None);
    }

    #[test]
    fn lan_is_one_shape_or_refused() {
        let read = |text: &str| serde_json::from_str::<Lan>(text);
        assert_eq!(
            read(r#"{"device": "eth0"}"#).unwrap(),
            Lan::Device {
                device: "eth0".to_owned()
            }
        );
        assert_eq!(
            read(r#"{"bridge": "br-lan", "ports": ["lan1", "lan2"]}"#).unwrap(),
            Lan::Bridge {
                bridge: "br-lan".to_owned(),
                ports: vec!["lan1".to_owned(), "lan2".to_owned()]
            }
        );
        for bad in [
            r#"{"device": "eth0", "bridge": "br-lan", "ports": ["lan1"]}"#,
            r#"{"device": "eth0", "ports": ["lan1"]}"#,
            r#"{"bridge": "br-lan"}"#,
            r#"{"device": "eth0", "vlan": 2}"#,
            r#"{}"#,
            r#""eth0""#,
        ] {
            assert!(read(bad).is_err(), "{bad}");
        }
        // and written back in its own shape
        for lan in [
            Lan::Device {
                device: "eth0".to_owned(),
            },
            Lan::Bridge {
                bridge: "br-lan".to_owned(),
                ports: vec!["eth0".to_owned()],
            },
        ] {
            assert_eq!(read(&serde_json::to_string(&lan).unwrap()).unwrap(), lan);
        }
    }
}
