//! A minimal ustar writer and reader: regular files of the listed names, mode 0600, no
//! directories. The device reads the archive with busybox `tar`, so the writer keeps to the
//! standard header (octal fields, the checksum, 512-byte blocks, two zero blocks at the end).

use crate::ImageError;

wyrm_core::name_enum! {
    /// The files of a config archive, in the order they are written.
    pub(crate) enum File as "config file" without codec {
        Wyrmd => "wyrmd.json5",
        Network => "network",
        Seed => "seed.json",
        Setup => "setup",
        AuthorizedKeys => "authorized_keys",
        Timezone => "timezone",
        Ntp => "ntp",
    }
}

pub(crate) const BLOCK: usize = 512;
const BLOCK_U64: u64 = 512;
/// The two zero blocks that end an archive.
const END: usize = 2 * BLOCK;

// Header fields: (offset, length).
const NAME: (usize, usize) = (0, 100);
const MODE: usize = 100;
const UID: usize = 108;
const GID: usize = 116;
const SIZE: (usize, usize) = (124, 12);
const MTIME: usize = 136;
const CHKSUM: (usize, usize) = (148, 8);
const TYPEFLAG: usize = 156;
const MAGIC: usize = 257;
const VERSION: usize = 263;
const PREFIX: (usize, usize) = (345, 155);

/// A regular file: `'0'`, or NUL as archives older than ustar wrote it.
const REGULAR: u8 = b'0';

/// The size of the archive of files with these content lengths; `None` beyond `u64`.
pub(crate) fn archive_len(lengths: impl Iterator<Item = u64>) -> Option<u64> {
    let mut total = BLOCK_U64.checked_mul(2)?;
    for len in lengths {
        let data = len.div_ceil(BLOCK_U64).checked_mul(BLOCK_U64)?;
        total = total.checked_add(BLOCK_U64)?.checked_add(data)?;
    }
    Some(total)
}

/// The archive of these files, in the order given.
pub(crate) fn write(files: &[(File, &[u8])]) -> Result<Vec<u8>, ImageError> {
    let mut out = Vec::new();
    for (file, data) in files {
        out.extend_from_slice(&header(*file, data.len())?);
        out.extend_from_slice(data);
        out.resize(out.len().div_ceil(BLOCK) * BLOCK, 0);
    }
    out.resize(out.len() + END, 0);
    Ok(out)
}

fn header(file: File, len: usize) -> Result<[u8; BLOCK], ImageError> {
    let mut h = [0u8; BLOCK];
    // every name of the list is shorter than the name field and has no `/`
    put(&mut h, NAME.0, file.name().as_bytes());
    put(&mut h, MODE, b"0000600\0");
    put(&mut h, UID, b"0000000\0");
    put(&mut h, GID, b"0000000\0");
    let size = format!("{len:011o}\0");
    if size.len() != SIZE.1 {
        return Err(ImageError::TooLarge);
    }
    put(&mut h, SIZE.0, size.as_bytes());
    // no clock: the time of every file is the epoch, so the same files give the same bytes
    put(&mut h, MTIME, b"00000000000\0");
    put(&mut h, TYPEFLAG, &[REGULAR]);
    put(&mut h, MAGIC, b"ustar\0");
    put(&mut h, VERSION, b"00");
    // six octal digits, NUL, space: the sum of 512 bytes is below 0o777777
    let sum = format!("{:06o}\0 ", checksum(&h));
    put(&mut h, CHKSUM.0, sum.as_bytes());
    Ok(h)
}

/// Copies `bytes` into the header at `at`; what does not fit the block is not written (every
/// call writes a constant that fits its field).
fn put(h: &mut [u8; BLOCK], at: usize, bytes: &[u8]) {
    if let Some(field) = at
        .checked_add(bytes.len())
        .and_then(|end| h.get_mut(at..end))
    {
        field.copy_from_slice(bytes);
    }
}

/// The sum of the header's bytes with the checksum field read as spaces.
fn checksum(h: &[u8; BLOCK]) -> u64 {
    let field = CHKSUM.0..CHKSUM.0 + CHKSUM.1;
    h.iter()
        .enumerate()
        .map(|(i, b)| u64::from(if field.contains(&i) { b' ' } else { *b }))
        .sum()
}

/// The files of an archive, in its order. Refuses every entry that is not a regular file of
/// the list ([`ImageError::BadName`]) and every archive that is not whole
/// ([`ImageError::Damaged`]): a broken header, data that runs past the end, no two zero blocks
/// at the end or anything but zeros after them.
pub(crate) fn read(archive: &[u8]) -> Result<Vec<(File, &[u8])>, ImageError> {
    let mut files: Vec<(File, &[u8])> = Vec::new();
    let mut rest = archive;
    loop {
        let Some((h, after)) = rest.split_first_chunk::<BLOCK>() else {
            return Err(ImageError::Damaged);
        };
        if h.iter().all(|b| *b == 0) {
            if rest.len() < END || after.iter().any(|b| *b != 0) {
                return Err(ImageError::Damaged);
            }
            return Ok(files);
        }
        if field(h, (MAGIC, 5)) != b"ustar" || octal(field(h, CHKSUM)) != Some(checksum(h)) {
            return Err(ImageError::Damaged);
        }
        let name = full_name(h);
        let regular = matches!(field(h, (TYPEFLAG, 1)), [REGULAR] | [0]);
        let file = match File::from_name(&name) {
            Some(file) if regular && files.iter().all(|(f, _)| *f != file) => file,
            _ => return Err(ImageError::BadName(name)),
        };
        let len = octal(field(h, SIZE))
            .and_then(|len| usize::try_from(len).ok())
            .ok_or(ImageError::Damaged)?;
        let padded = len
            .checked_next_multiple_of(BLOCK)
            .ok_or(ImageError::Damaged)?;
        let (Some(data), Some(next)) = (after.get(..len), after.get(padded..)) else {
            return Err(ImageError::Damaged);
        };
        files.push((file, data));
        rest = next;
    }
}

/// The bytes of a header field; empty for a field outside the block (none is).
fn field(h: &[u8; BLOCK], (at, len): (usize, usize)) -> &[u8] {
    at.checked_add(len)
        .and_then(|end| h.get(at..end))
        .unwrap_or(&[])
}

/// The text of a field up to its first NUL.
fn text(bytes: &[u8]) -> String {
    let end = bytes.iter().position(|b| *b == 0).unwrap_or(bytes.len());
    String::from_utf8_lossy(bytes.get(..end).unwrap_or(bytes)).into_owned()
}

/// The entry's name as an unpacker reads it: the prefix, when there is one, is a directory
/// before the name. Bytes that are not UTF-8 show as U+FFFD, which no listed name holds.
fn full_name(h: &[u8; BLOCK]) -> String {
    let name = text(field(h, NAME));
    let prefix = text(field(h, PREFIX));
    if prefix.is_empty() {
        name
    } else {
        format!("{prefix}/{name}")
    }
}

/// An octal number field: digits between optional leading spaces and trailing spaces or NULs.
/// `None` for anything else (also the base-256 form of GNU tar).
fn octal(bytes: &[u8]) -> Option<u64> {
    let start = bytes.iter().position(|b| *b != b' ')?;
    let digits = bytes.get(start..)?;
    let end = digits
        .iter()
        .position(|b| matches!(b, b' ' | 0))
        .unwrap_or(digits.len());
    let (digits, tail) = digits.split_at_checked(end)?;
    if digits.is_empty() || tail.iter().any(|b| !matches!(b, b' ' | 0)) {
        return None;
    }
    digits.iter().try_fold(0u64, |n, b| match b {
        b'0'..=b'7' => n.checked_mul(8)?.checked_add(u64::from(b - b'0')),
        _ => None,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn octal_fields() {
        assert_eq!(octal(b"0000600\0"), Some(0o600));
        assert_eq!(octal(b"00000000017\0"), Some(15));
        assert_eq!(octal(b"   17 \0"), Some(15));
        assert_eq!(octal(b"17"), Some(15));
        assert_eq!(octal(b"0\0"), Some(0));
        for bad in [
            &b""[..],
            b"\0\0\0",
            b"   ",
            b"18\0",
            b"1 7\0",
            b"-1\0",
            b"\x80\0\0\x01",
            b"1\0x",
        ] {
            assert_eq!(octal(bad), None, "{bad:?}");
        }
        assert_eq!(octal(b"7777777777777777777777777"), None);
    }

    #[test]
    fn every_name_fits_its_field() {
        for file in File::ALL {
            let name = file.name();
            assert!(name.len() < NAME.1 && !name.contains('/') && name.is_ascii());
            let h = header(*file, 0).unwrap();
            assert_eq!(full_name(&h), name);
            assert_eq!(octal(field(&h, CHKSUM)), Some(checksum(&h)));
        }
        assert_eq!(File::ALL.first(), Some(&File::Wyrmd));
    }

    #[test]
    fn lengths() {
        assert_eq!(archive_len([].into_iter()), Some(1024));
        assert_eq!(
            archive_len([0, 1, 512, 513].into_iter()),
            Some(1024 + 4 * 512 + 2048)
        );
        assert_eq!(archive_len([u64::MAX].into_iter()), None);
        let a = write(&[(File::Wyrmd, b"{}"), (File::Ntp, b"")]).unwrap();
        assert_eq!(u64::try_from(a.len()).ok(), archive_len([2, 0].into_iter()));
        assert!(matches!(
            header(File::Wyrmd, 1 << 33),
            Err(ImageError::TooLarge)
        ));
    }
}
