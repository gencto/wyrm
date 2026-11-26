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
    /// Two entries for this board.
    #[error("board `{0}` is there twice")]
    Twice(String),
    /// The SHA-256 of this board's image is not 64 lower-case hex digits.
    #[error("board `{0}`: the SHA-256 is not 64 lower-case hex digits")]
    BadHash(String),
    /// The config region of this board's image does not lie inside the image.
    #[error("board `{0}`: the config region does not lie inside the image")]
    Outside(String),
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
    /// and a config region of [`CONFIG_SIZE`] bytes inside the image.
    pub fn check(&self) -> Result<(), ImageError> {
        if self.format != FORMAT {
            return Err(IndexError::Format(self.format.clone()).into());
        }
        for (i, image) in self.images.iter().enumerate() {
            let board = || image.board.clone();
            if image.board.is_empty() || image.file.is_empty() {
                return Err(IndexError::NoName.into());
            }
            if self.images.iter().take(i).any(|e| e.board == image.board) {
                return Err(IndexError::Twice(board()).into());
            }
            if !hex::is_lower_hex(&image.sha256, 32) {
                return Err(IndexError::BadHash(board()).into());
            }
            let inside = image
                .config_offset
                .checked_add(CONFIG_SIZE)
                .is_some_and(|end| end <= image.size);
            if !inside {
                return Err(IndexError::Outside(board()).into());
            }
        }
        Ok(())
    }

    /// The image of a board.
    pub fn image(&self, board: &str) -> Option<&ImageEntry> {
        self.images.iter().find(|image| image.board == board)
    }
}
