//! The gzip of a base image as it is published (ADR 0051 §4): three gzip members, cut where
//! the config region starts and ends. The head holds the bytes before the region, the
//! second member the empty region alone, the tail the rest of the image (none for an image
//! that ends with its region). Together they are a plain gzip file of the image: gzip
//! readers read every member of a file. The image builder page writes a configuration
//! without unpacking the image: it puts a member of its own region between the published
//! head and tail.
//!
//! The members carry no name and no time in their headers: the same image gives the same
//! file. `tools/wyr/tests/image.rs` includes this file by its path, so it uses no item of
//! `wyr`.

use std::io::{self, Read, Write};
use wyrm_core::hex::Sha256Stream;
use wyrm_image::{Member, CONFIG_SIZE};

/// What [`write_members`] wrote: the size and the SHA-256 of the raw image it read and of
/// the gzip file it wrote, and the members of that file.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Packed {
    /// The size of the raw image, in bytes.
    pub raw_size: u64,
    /// The SHA-256 of the raw image.
    pub raw_sha256: [u8; 32],
    /// The size of the gzip file, in bytes.
    pub gz_size: u64,
    /// The SHA-256 of the gzip file.
    pub gz_sha256: [u8; 32],
    /// The head, the region and the tail, as byte ranges of the gzip file.
    pub members: [Member; 3],
}

/// Counts and hashes what is written through it.
struct Sum<W> {
    to: W,
    hash: Sha256Stream,
    size: u64,
}

impl<W: Write> Write for Sum<W> {
    fn write(&mut self, buf: &[u8]) -> io::Result<usize> {
        let n = self.to.write(buf)?;
        let part = buf.get(..n).unwrap_or(buf);
        self.hash.update(part);
        self.size = self
            .size
            .saturating_add(u64::try_from(part.len()).unwrap_or(u64::MAX));
        Ok(n)
    }

    fn flush(&mut self) -> io::Result<()> {
        self.to.flush()
    }
}

/// Hashes what is read through it.
struct Hashed<R> {
    from: R,
    hash: Sha256Stream,
    size: u64,
}

impl<R: Read> Read for Hashed<R> {
    fn read(&mut self, buf: &mut [u8]) -> io::Result<usize> {
        let n = self.from.read(buf)?;
        let part = buf.get(..n).unwrap_or(buf);
        self.hash.update(part);
        self.size = self
            .size
            .saturating_add(u64::try_from(part.len()).unwrap_or(u64::MAX));
        Ok(n)
    }
}

/// Writes one gzip member of `len` bytes of `input`, or of all the rest of it when `len` is
/// `None`. Returns where the member lies in the output. Fails when `input` ends before
/// `len` bytes.
fn member<R: Read, W: Write>(
    input: &mut R,
    len: Option<u64>,
    out: &mut Sum<W>,
) -> io::Result<Member> {
    let offset = out.size;
    // no name and no time in the header: the same image is the same file
    let mut encoder = flate2::GzBuilder::new()
        .mtime(0)
        .write(&mut *out, flate2::Compression::best());
    match len {
        Some(len) => {
            let copied = io::copy(&mut input.by_ref().take(len), &mut encoder)?;
            if copied != len {
                return Err(io::Error::new(
                    io::ErrorKind::UnexpectedEof,
                    format!("the image ends {copied} bytes into a part of {len} bytes: it ends before its config region does"),
                ));
            }
        }
        None => {
            io::copy(input, &mut encoder)?;
        }
    }
    encoder.finish()?;
    Ok(Member {
        offset,
        size: out.size.saturating_sub(offset),
    })
}

/// Reads the raw image from `input` and writes its gzip into `out` as three members, cut at
/// `config_offset` and `config_offset + CONFIG_SIZE`. Fails when the image ends before its
/// config region does.
pub fn write_members<R: Read, W: Write>(
    input: &mut R,
    config_offset: u64,
    out: W,
) -> io::Result<Packed> {
    let mut input = Hashed {
        from: input,
        hash: Sha256Stream::new(),
        size: 0,
    };
    let mut out = Sum {
        to: io::BufWriter::new(out),
        hash: Sha256Stream::new(),
        size: 0,
    };
    let head = member(&mut input, Some(config_offset), &mut out)?;
    let region = member(&mut input, Some(CONFIG_SIZE), &mut out)?;
    let tail = member(&mut input, None, &mut out)?;
    out.flush()?;
    Ok(Packed {
        raw_size: input.size,
        raw_sha256: input.hash.finish(),
        gz_size: out.size,
        gz_sha256: out.hash.finish(),
        members: [head, region, tail],
    })
}
