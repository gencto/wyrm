//! The config region: its files, the bytes an assembler writes and what a reader takes back.

use std::borrow::Cow;

use wyrm_core::hex::{is_hex, sha256};

use crate::tar::{self, File};
use crate::ImageError;

/// The size of the config region of every image, in bytes.
pub const CONFIG_SIZE: u64 = 4 * 1024 * 1024;
/// The first bytes of a region that holds a configuration.
pub const MAGIC_FULL: &[u8; 8] = b"WYRMCFG1";
/// The first bytes of an empty region, as CI writes it and as the device leaves it.
pub const MAGIC_EMPTY: &[u8; 8] = b"WYRMCFG0";
/// The bytes before the payload: the magic, the payload length and the payload's SHA-256.
pub const HEADER_SIZE: u64 = 8 + 8 + 32;
/// The largest payload (the archive with its headers and end blocks).
pub const MAX_PAYLOAD: u64 = CONFIG_SIZE - HEADER_SIZE;

/// The files of a configuration. The archive names them `wyrmd.json5`, `network`,
/// `seed.json`, `setup`, `authorized_keys`, `timezone` and `ntp`.
///
/// `Debug` shows the size of each file, never its content: `setup` is kept like a secret of
/// the image (ADR 0051 "Built").
#[derive(Clone, PartialEq, Eq)]
pub struct ConfigFiles {
    /// The broker's configuration. Required, not empty.
    pub wyrmd_json5: String,
    /// The network configuration of the device, as UCI text.
    pub network: Option<String>,
    /// Which of the links the image carries are installed on the first start (`wyrm-seed/1`).
    pub seed_json: Option<String>,
    /// The SHA-256 of the setup code: 64 hex digits, no newline (the archive adds one).
    pub setup: Option<String>,
    /// SSH public keys for `root`. Without the file the device has no SSH login.
    pub authorized_keys: Option<String>,
    /// The IANA name of the time zone.
    pub timezone: Option<String>,
    /// NTP servers, one per line.
    pub ntp: Option<String>,
}

impl std::fmt::Debug for ConfigFiles {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        let mut d = f.debug_struct("ConfigFiles");
        for file in File::ALL {
            if let Some(text) = self.get(*file) {
                d.field(file.name(), &format_args!("{} bytes", text.len()));
            }
        }
        d.finish()
    }
}

impl ConfigFiles {
    fn get(&self, file: File) -> Option<&str> {
        match file {
            File::Wyrmd => Some(&self.wyrmd_json5),
            File::Network => self.network.as_deref(),
            File::Seed => self.seed_json.as_deref(),
            File::Setup => self.setup.as_deref(),
            File::AuthorizedKeys => self.authorized_keys.as_deref(),
            File::Timezone => self.timezone.as_deref(),
            File::Ntp => self.ntp.as_deref(),
        }
    }

    /// The files that are there, in the order of the archive, each as the archive holds it:
    /// `setup` with its one newline, every other file as it is.
    fn entries(&self) -> Vec<(File, Cow<'_, [u8]>)> {
        File::ALL
            .iter()
            .filter_map(|file| {
                let text = self.get(*file)?;
                let data = match file {
                    File::Setup => Cow::Owned(format!("{text}\n").into_bytes()),
                    _ => Cow::Borrowed(text.as_bytes()),
                };
                Some((*file, data))
            })
            .collect()
    }

    /// Checks the files as a reader will: the archive fits the region
    /// ([`ImageError::TooLarge`]), `setup` is 64 hex digits ([`ImageError::BadSetup`]), no
    /// file holds a NUL and `wyrmd.json5` is not empty ([`ImageError::BadContent`]).
    pub fn check(&self) -> Result<(), ImageError> {
        let lengths = self
            .entries()
            .into_iter()
            .map(|(_, data)| u64::try_from(data.len()).unwrap_or(u64::MAX));
        if tar::archive_len(lengths).is_none_or(|len| len > MAX_PAYLOAD) {
            return Err(ImageError::TooLarge);
        }
        for file in File::ALL {
            let Some(text) = self.get(*file) else {
                continue;
            };
            if text.contains('\0') || (*file == File::Wyrmd && text.is_empty()) {
                return Err(ImageError::BadContent(file.name()));
            }
            if *file == File::Setup && !is_hex(text, 32) {
                return Err(ImageError::BadSetup);
            }
        }
        Ok(())
    }
}

/// The bytes of a full config region for these files: exactly [`CONFIG_SIZE`] bytes, to be
/// written at the image's `config_offset`. Refuses what [`ConfigFiles::check`] refuses.
pub fn region(files: &ConfigFiles) -> Result<Vec<u8>, ImageError> {
    files.check()?;
    let entries = files.entries();
    let borrowed: Vec<(File, &[u8])> = entries.iter().map(|(f, d)| (*f, d.as_ref())).collect();
    let payload = tar::write(&borrowed)?;
    let (Ok(len), Ok(size)) = (u64::try_from(payload.len()), usize::try_from(CONFIG_SIZE)) else {
        return Err(ImageError::TooLarge);
    };
    if len > MAX_PAYLOAD {
        return Err(ImageError::TooLarge);
    }
    let mut out = Vec::with_capacity(size);
    out.extend_from_slice(MAGIC_FULL);
    out.extend_from_slice(&len.to_le_bytes());
    out.extend_from_slice(&sha256(&payload));
    out.extend_from_slice(&payload);
    out.resize(size, 0);
    Ok(out)
}

/// Reads a config region: `None` for an empty one, the files of a full one.
///
/// `bytes` is the whole region, exactly [`CONFIG_SIZE`] bytes. Neither magic is
/// [`ImageError::NoRegion`]. A region with a magic that does not follow the format is
/// [`ImageError::Damaged`]: an empty region with anything but zeros, a length beyond
/// [`MAX_PAYLOAD`], a SHA-256 that does not match, bytes after the payload, a broken archive.
/// An archive entry that is not a regular file of the list, a name twice or a missing
/// `wyrmd.json5` is [`ImageError::BadName`]; content is checked as [`ConfigFiles::check`] does.
pub fn read_region(bytes: &[u8]) -> Result<Option<ConfigFiles>, ImageError> {
    let (magic, rest) = bytes.split_first_chunk::<8>().ok_or(ImageError::Damaged)?;
    check_slot(magic)?;
    if u64::try_from(bytes.len()).ok() != Some(CONFIG_SIZE) {
        return Err(ImageError::Damaged);
    }
    let zeros = |bytes: &[u8]| bytes.iter().all(|b| *b == 0);
    if magic == MAGIC_EMPTY {
        return if zeros(rest) {
            Ok(None)
        } else {
            Err(ImageError::Damaged)
        };
    }
    let (len, rest) = rest.split_first_chunk::<8>().ok_or(ImageError::Damaged)?;
    let (hash, rest) = rest.split_first_chunk::<32>().ok_or(ImageError::Damaged)?;
    let Ok(len) = usize::try_from(u64::from_le_bytes(*len)) else {
        return Err(ImageError::Damaged);
    };
    // `rest` is CONFIG_SIZE - HEADER_SIZE bytes, so a length beyond MAX_PAYLOAD does not split
    let (payload, padding) = rest.split_at_checked(len).ok_or(ImageError::Damaged)?;
    if sha256(payload) != *hash || !zeros(padding) {
        return Err(ImageError::Damaged);
    }

    let mut files = ConfigFiles {
        wyrmd_json5: String::new(),
        network: None,
        seed_json: None,
        setup: None,
        authorized_keys: None,
        timezone: None,
        ntp: None,
    };
    let mut config = false;
    for (file, data) in tar::read(payload)? {
        let Ok(text) = std::str::from_utf8(data) else {
            return Err(ImageError::BadContent(file.name()));
        };
        let text = match file {
            // the hash with or without its one newline
            File::Setup => text.strip_suffix('\n').unwrap_or(text),
            _ => text,
        }
        .to_owned();
        match file {
            File::Wyrmd => {
                files.wyrmd_json5 = text;
                config = true;
            }
            File::Network => files.network = Some(text),
            File::Seed => files.seed_json = Some(text),
            File::Setup => files.setup = Some(text),
            File::AuthorizedKeys => files.authorized_keys = Some(text),
            File::Timezone => files.timezone = Some(text),
            File::Ntp => files.ntp = Some(text),
        }
    }
    if !config {
        return Err(ImageError::BadName(File::Wyrmd.name().to_owned()));
    }
    files.check()?;
    Ok(Some(files))
}

/// Checks the eight bytes at an image's `config_offset` before an assembler writes there:
/// either magic passes, anything else is [`ImageError::NoRegion`] (a wrong offset, another
/// board's index entry, a file that is no WYRM image).
pub fn check_slot(at_offset: &[u8; 8]) -> Result<(), ImageError> {
    if at_offset == MAGIC_FULL || at_offset == MAGIC_EMPTY {
        Ok(())
    } else {
        Err(ImageError::NoRegion)
    }
}
