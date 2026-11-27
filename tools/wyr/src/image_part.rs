//! The config partition of a base image (ADR 0051 §4): a partition of [`CONFIG_SIZE`] bytes
//! appended after the last partition of the image OpenWrt's ImageBuilder made, in the image
//! file itself.
//!
//! The table is edited here and not by a tool of the build container: the container is
//! OpenWrt's own, pinned by digest, and it carries neither `sfdisk` nor `sgdisk`. A file needs
//! no root to be edited, and the edit is small:
//!
//! - **MBR** (`bcm27xx`): one more entry of the four in the first sector.
//! - **GPT** (`mediatek/filogic`, `armsr`): one more entry in the array, the two checksums of
//!   the header, and the second header with its array at the new end of the image. The first
//!   sector is never written: an image whose boot ROM reads a hybrid MBR keeps it byte for
//!   byte.
//!
//! No entry that was there is changed. The functions that edit work on the sectors as bytes
//! and do no I/O; [`append_config`] is the I/O around them.

use std::fs::File;
use std::io::{self, Seek, SeekFrom, Write};
use wyrm_core::files::read_full;
use wyrm_image::{CONFIG_SIZE, MAGIC_EMPTY};

/// The bytes of a sector. Images of every board count in sectors of this size.
pub const SECTOR: u64 = 512;
const SECTOR_LEN: usize = 512;
/// A partition starts on 1 MiB.
const ALIGN: u64 = 2048;
/// The config region in sectors.
const REGION_SECTORS: u64 = CONFIG_SIZE / SECTOR;

/// The MBR type of the config partition: "Non-FS data", which no system mounts.
pub const MBR_TYPE: u8 = 0xda;
/// The GPT type of the config partition, as it lies in an entry: "Linux reserved"
/// (`8DA63339-0007-60C0-C436-083AC8230908`), which no system mounts by itself.
pub const GPT_TYPE: [u8; 16] = [
    0x39, 0x33, 0xa6, 0x8d, 0x07, 0x00, 0xc0, 0x60, 0xc4, 0x36, 0x08, 0x3a, 0xc8, 0x23, 0x09, 0x08,
];
/// The unique id of the config partition, as it lies in an entry
/// (`57595243-4647-4000-8000-575952434647`). It is the same in every image, so that an image
/// is the same bytes each time it is built; a root partition is never found by it.
pub const GPT_UUID: [u8; 16] = [
    0x43, 0x52, 0x59, 0x57, 0x47, 0x46, 0x00, 0x40, 0x80, 0x00, 0x57, 0x59, 0x52, 0x43, 0x46, 0x47,
];
/// The GPT name of the config partition.
pub const GPT_NAME: &str = "wyrm-config";

const MBR_ENTRIES: usize = 446;
const MBR_ENTRY: usize = 16;
const GPT_ENTRY: usize = 128;
/// A GPT header this build edits is the 92 bytes of revision 1.0.
const GPT_HEADER: usize = 92;
/// More entries than any image has; the array is read into memory.
const GPT_MAX_ENTRIES: u32 = 1024;

/// Why the partition table of an image is not edited.
#[derive(Debug, thiserror::Error)]
pub enum PartError {
    /// The image could not be read or written.
    #[error("{0}")]
    Io(#[from] io::Error),
    /// The first sector does not end with the boot signature.
    #[error("the image has no partition table: its first sector does not end with 55 AA")]
    NoTable,
    /// The image has a GPT and the board's table is MBR, or the other way round.
    #[error("the image has {found}; the board's table is {want}")]
    OtherTable {
        found: &'static str,
        want: &'static str,
    },
    /// A GPT this build does not edit; the text says what it found.
    #[error("the GPT of the image is refused: {0}")]
    Gpt(&'static str),
    /// No partition in the table.
    #[error("the partition table of the image has no partition")]
    Empty,
    /// No free entry for one more partition.
    #[error("the partition table of the image has no free entry")]
    Full,
    /// A number of the table does not fit the image.
    #[error("the partition table of the image names sectors that cannot be")]
    Range,
}

type Result<T> = std::result::Result<T, PartError>;

/// One partition of a table, for the listing that is published beside an image.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Partition {
    /// The number the kernel gives it (`…p3`).
    pub number: u32,
    /// The first sector.
    pub start: u64,
    /// The sectors.
    pub sectors: u64,
    /// The type: two hex digits of an MBR, the type id of a GPT as it is written.
    pub kind: String,
    /// The GPT name; empty in an MBR.
    pub name: String,
}

/// What [`append_config`] did.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Appended {
    /// Where the config region starts, in bytes of the image.
    pub config_offset: u64,
    /// The number of the config partition.
    pub config_part: u32,
    /// The size of the image now.
    pub size: u64,
    /// Every partition of the image, the config partition among them.
    pub partitions: Vec<Partition>,
}

fn le32(bytes: &[u8], at: usize) -> Option<u32> {
    let end = at.checked_add(4)?;
    Some(u32::from_le_bytes(bytes.get(at..end)?.try_into().ok()?))
}

fn le64(bytes: &[u8], at: usize) -> Option<u64> {
    let end = at.checked_add(8)?;
    Some(u64::from_le_bytes(bytes.get(at..end)?.try_into().ok()?))
}

fn put(bytes: &mut [u8], at: usize, value: &[u8]) -> Result<()> {
    at.checked_add(value.len())
        .and_then(|end| bytes.get_mut(at..end))
        .ok_or(PartError::Range)?
        .copy_from_slice(value);
    Ok(())
}

fn crc32(bytes: &[u8]) -> u32 {
    let mut crc = flate2::Crc::new();
    crc.update(bytes);
    crc.sum()
}

/// The number the kernel gives the partition of an entry: the entries count from one.
fn number_of(index: usize) -> Result<u32> {
    u32::try_from(index)
        .ok()
        .and_then(|index| index.checked_add(1))
        .ok_or(PartError::Range)
}

/// The first sector on a 1 MiB boundary at or after `end`.
fn aligned(end: u64) -> Result<u64> {
    end.checked_add(ALIGN - 1)
        .map(|n| n / ALIGN * ALIGN)
        .ok_or(PartError::Range)
}

/// The entries of an MBR that hold a partition: `(index, type, start, sectors)`.
fn mbr_entries(sector0: &[u8]) -> Vec<(usize, u8, u64, u64)> {
    (0..4)
        .filter_map(|i| {
            let at = MBR_ENTRIES + i * MBR_ENTRY;
            let kind = *sector0.get(at + 4)?;
            let start = le32(sector0, at + 8)?;
            let sectors = le32(sector0, at + 12)?;
            (kind != 0).then_some((i, kind, u64::from(start), u64::from(sectors)))
        })
        .collect()
}

fn has_signature(sector0: &[u8]) -> bool {
    sector0.get(510..512) == Some(&[0x55, 0xaa])
}

/// The first sector says GPT: an entry of the type `EE` (alone in a protective MBR, beside
/// others in a hybrid one).
fn says_gpt(sector0: &[u8]) -> bool {
    mbr_entries(sector0)
        .iter()
        .any(|(_, kind, ..)| *kind == 0xee)
}

/// Adds the config partition to an MBR: the first free entry, after the end of the last
/// partition. Returns its number and its first sector.
pub fn mbr_append(sector0: &mut [u8]) -> Result<(u32, u64)> {
    if !has_signature(sector0) {
        return Err(PartError::NoTable);
    }
    let used = mbr_entries(sector0);
    let end = used
        .iter()
        .filter_map(|(_, _, start, sectors)| start.checked_add(*sectors))
        .max()
        .ok_or(PartError::Empty)?;
    let start = aligned(end)?;
    let (Ok(start32), Ok(sectors32)) = (u32::try_from(start), u32::try_from(REGION_SECTORS)) else {
        return Err(PartError::Range);
    };
    let free = (0..4usize)
        .find(|i| {
            let at = MBR_ENTRIES + i * MBR_ENTRY;
            sector0
                .get(at..at + MBR_ENTRY)
                .is_some_and(|entry| entry.iter().all(|b| *b == 0))
        })
        .ok_or(PartError::Full)?;
    let mut entry = [0u8; MBR_ENTRY];
    // no CHS address: the marker of an entry that is read by its LBA
    put(&mut entry, 1, &[0xfe, 0xff, 0xff])?;
    put(&mut entry, 4, &[MBR_TYPE])?;
    put(&mut entry, 5, &[0xfe, 0xff, 0xff])?;
    put(&mut entry, 8, &start32.to_le_bytes())?;
    put(&mut entry, 12, &sectors32.to_le_bytes())?;
    put(sector0, MBR_ENTRIES + free * MBR_ENTRY, &entry)?;
    let number = number_of(free)?;
    Ok((number, start))
}

/// A GPT as it is read from an image: the header's sector and the array of entries.
#[derive(Debug, Clone)]
pub struct Gpt {
    /// The sector of the first header (LBA 1).
    pub header: Vec<u8>,
    /// The array of entries, whole.
    pub entries: Vec<u8>,
    /// The sectors the array takes.
    pub entries_sectors: u64,
    header_size: usize,
}

/// Where the array of entries of a GPT header lies: `(first sector, entries)`. Checks the
/// header: its signature, its size, its checksum, entries of 128 bytes.
pub fn gpt_header(sector1: &[u8]) -> Result<(u64, u32)> {
    if sector1.get(..8) != Some(b"EFI PART") {
        return Err(PartError::Gpt("no `EFI PART` in the second sector"));
    }
    let size = le32(sector1, 12)
        .and_then(|n| usize::try_from(n).ok())
        .filter(|n| (GPT_HEADER..=SECTOR_LEN).contains(n))
        .ok_or(PartError::Gpt("the size of its header"))?;
    let mut copy = sector1.get(..size).ok_or(PartError::Range)?.to_vec();
    put(&mut copy, 16, &[0; 4])?;
    if le32(sector1, 16) != Some(crc32(&copy)) {
        return Err(PartError::Gpt("the checksum of its header"));
    }
    if le64(sector1, 24) != Some(1) {
        return Err(PartError::Gpt(
            "its header does not lie in the second sector",
        ));
    }
    let entries_lba = le64(sector1, 72).ok_or(PartError::Range)?;
    let count = le32(sector1, 80).ok_or(PartError::Range)?;
    if le32(sector1, 84).and_then(|n| usize::try_from(n).ok()) != Some(GPT_ENTRY) {
        return Err(PartError::Gpt("entries that are not 128 bytes"));
    }
    if count == 0 || count > GPT_MAX_ENTRIES || entries_lba < 2 {
        return Err(PartError::Gpt("the place or the length of its entries"));
    }
    Ok((entries_lba, count))
}

impl Gpt {
    /// A GPT from its header's sector and its array of entries (the bytes of `count`
    /// entries, read where [`gpt_header`] says). Checks the checksum of the array.
    pub fn new(header: Vec<u8>, entries: Vec<u8>) -> Result<Self> {
        let (_, count) = gpt_header(&header)?;
        let len = usize::try_from(count)
            .ok()
            .and_then(|n| n.checked_mul(GPT_ENTRY))
            .ok_or(PartError::Range)?;
        if entries.len() != len {
            return Err(PartError::Range);
        }
        if le32(&header, 88) != Some(crc32(&entries)) {
            return Err(PartError::Gpt("the checksum of its entries"));
        }
        let header_size = le32(&header, 12)
            .and_then(|n| usize::try_from(n).ok())
            .ok_or(PartError::Range)?;
        let entries_sectors = u64::try_from(len.div_ceil(SECTOR_LEN))
            .ok()
            .ok_or(PartError::Range)?;
        Ok(Self {
            header,
            entries,
            entries_sectors,
            header_size,
        })
    }

    /// The entries that hold a partition: `(index, first sector, last sector)`.
    fn used(&self) -> Vec<(usize, u64, u64)> {
        self.entries
            .as_chunks::<GPT_ENTRY>()
            .0
            .iter()
            .enumerate()
            .filter_map(|(i, entry)| {
                let free = entry.get(..16)?.iter().all(|b| *b == 0);
                (!free).then_some((i, le64(entry, 32)?, le64(entry, 40)?))
            })
            .collect()
    }

    /// Adds the config partition: the first free entry, after the end of the last
    /// partition. The image then has `sectors` sectors (the second return value), and the
    /// second header lies in the last of them. Returns the partition's number, its first
    /// sector and the sectors of the image. `have` is the sectors the image has now.
    pub fn append(&mut self, have: u64) -> Result<(u32, u64, u64)> {
        let used = self.used();
        let end = used
            .iter()
            .filter_map(|(_, _, last)| last.checked_add(1))
            .max()
            .ok_or(PartError::Empty)?;
        let start = aligned(end)?;
        let free = self
            .entries
            .as_chunks::<GPT_ENTRY>()
            .0
            .iter()
            .position(|entry| entry.iter().all(|b| *b == 0))
            .ok_or(PartError::Full)?;
        let last = start
            .checked_add(REGION_SECTORS - 1)
            .ok_or(PartError::Range)?;
        // the second table takes the last sectors: its array, then its header. 1 MiB is
        // kept for it, so the image ends on a boundary
        let sectors = aligned(have)?.max(last.checked_add(1 + ALIGN).ok_or(PartError::Range)?);
        let backup = sectors - 1;
        let last_usable = backup
            .checked_sub(self.entries_sectors + 1)
            .filter(|usable| *usable >= last)
            .ok_or(PartError::Range)?;

        let mut entry = [0u8; GPT_ENTRY];
        put(&mut entry, 0, &GPT_TYPE)?;
        put(&mut entry, 16, &GPT_UUID)?;
        put(&mut entry, 32, &start.to_le_bytes())?;
        put(&mut entry, 40, &last.to_le_bytes())?;
        let name: Vec<u8> = GPT_NAME.encode_utf16().flat_map(u16::to_le_bytes).collect();
        put(&mut entry, 56, &name)?;
        put(&mut self.entries, free * GPT_ENTRY, &entry)?;

        put(&mut self.header, 32, &backup.to_le_bytes())?;
        put(&mut self.header, 48, &last_usable.to_le_bytes())?;
        let crc = crc32(&self.entries);
        put(&mut self.header, 88, &crc.to_le_bytes())?;
        self.seal()?;
        let number = number_of(free)?;
        Ok((number, start, sectors))
    }

    /// Writes the checksum of the header over itself.
    fn seal(&mut self) -> Result<()> {
        put(&mut self.header, 16, &[0; 4])?;
        let crc = crc32(
            self.header
                .get(..self.header_size)
                .ok_or(PartError::Range)?,
        );
        put(&mut self.header, 16, &crc.to_le_bytes())
    }

    /// The second header of an image of `sectors` sectors, and the sector where its array
    /// starts: the first header with the two places exchanged.
    pub fn backup(&self, sectors: u64) -> Result<(Vec<u8>, u64)> {
        let at = sectors.checked_sub(1).ok_or(PartError::Range)?;
        let entries_at = at
            .checked_sub(self.entries_sectors)
            .ok_or(PartError::Range)?;
        let mut second = self.clone();
        put(&mut second.header, 24, &at.to_le_bytes())?;
        put(&mut second.header, 32, &1u64.to_le_bytes())?;
        put(&mut second.header, 72, &entries_at.to_le_bytes())?;
        second.seal()?;
        Ok((second.header, entries_at))
    }

    fn partitions(&self) -> Vec<Partition> {
        self.used()
            .into_iter()
            .filter_map(|(i, first, last)| {
                let entry = self.entries.as_chunks::<GPT_ENTRY>().0.get(i)?;
                let units: Vec<u16> = entry
                    .get(56..)?
                    .as_chunks::<2>()
                    .0
                    .iter()
                    .map(|pair| u16::from_le_bytes(*pair))
                    .take_while(|unit| *unit != 0)
                    .collect();
                Some(Partition {
                    number: number_of(i).ok()?,
                    start: first,
                    sectors: last.checked_sub(first)?.checked_add(1)?,
                    kind: guid_text(entry.get(..16)?)?,
                    name: String::from_utf16_lossy(&units),
                })
            })
            .collect()
    }
}

/// A GUID of an entry as it is written: the first three fields are little-endian.
fn guid_text(bytes: &[u8]) -> Option<String> {
    let [a0, a1, a2, a3, b0, b1, c0, c1, rest @ ..] = bytes else {
        return None;
    };
    let (d, e) = rest.split_at_checked(2)?;
    Some(
        [
            wyrm_core::hex::encode_upper([*a3, *a2, *a1, *a0]),
            wyrm_core::hex::encode_upper([*b1, *b0]),
            wyrm_core::hex::encode_upper([*c1, *c0]),
            wyrm_core::hex::encode_upper(d),
            wyrm_core::hex::encode_upper(e),
        ]
        .join("-"),
    )
}

fn read_at(file: &mut File, sector: u64, len: usize) -> Result<Vec<u8>> {
    let mut buf = vec![0u8; len];
    let at = sector.checked_mul(SECTOR).ok_or(PartError::Range)?;
    file.seek(SeekFrom::Start(at))?;
    if read_full(file, &mut buf)? != len {
        return Err(PartError::Range);
    }
    Ok(buf)
}

fn write_at(file: &mut File, sector: u64, bytes: &[u8]) -> Result<()> {
    let at = sector.checked_mul(SECTOR).ok_or(PartError::Range)?;
    file.seek(SeekFrom::Start(at))?;
    file.write_all(bytes)?;
    Ok(())
}

/// Appends the config partition to the image in `file` and fills it with the empty region
/// (`WYRMCFG0` and zeros). `gpt` says which table the board's image has; an image with the
/// other one is refused.
pub fn append_config(file: &mut File, gpt: bool) -> Result<Appended> {
    let len = file.metadata()?.len();
    if len < 2 * SECTOR {
        return Err(PartError::NoTable);
    }
    // an image may end inside a sector (the `sdcard.img` of mediatek/filogic ends with its
    // last file, 4 bytes into one): the sector counts, and the image is made whole below
    let have = len.div_ceil(SECTOR);
    let mut sector0 = read_at(file, 0, SECTOR_LEN)?;
    if !has_signature(&sector0) {
        return Err(PartError::NoTable);
    }
    if says_gpt(&sector0) != gpt {
        let name = |gpt| if gpt { "a GPT" } else { "an MBR" };
        return Err(PartError::OtherTable {
            found: name(!gpt),
            want: name(gpt),
        });
    }
    let region = |file: &mut File, start: u64| -> Result<()> {
        let size = usize::try_from(CONFIG_SIZE).ok().ok_or(PartError::Range)?;
        let mut bytes = vec![0u8; size];
        put(&mut bytes, 0, MAGIC_EMPTY)?;
        // over whatever lay there: the second table of the image as it was built
        write_at(file, start, &bytes)
    };
    let (config_part, start, sectors, partitions) = if gpt {
        let header = read_at(file, 1, SECTOR_LEN)?;
        let (entries_lba, count) = gpt_header(&header)?;
        let entries_len = usize::try_from(count)
            .ok()
            .and_then(|n| n.checked_mul(GPT_ENTRY))
            .ok_or(PartError::Range)?;
        let entries = read_at(file, entries_lba, entries_len)?;
        let mut table = Gpt::new(header, entries)?;
        let (number, start, sectors) = table.append(have)?;
        let (second, second_entries) = table.backup(sectors)?;
        file.set_len(sectors.checked_mul(SECTOR).ok_or(PartError::Range)?)?;
        region(file, start)?;
        // the first sector is not written: a hybrid MBR stays as it is
        write_at(file, 1, &table.header)?;
        write_at(file, entries_lba, &table.entries)?;
        write_at(file, second_entries, &table.entries)?;
        write_at(file, sectors - 1, &second)?;
        (number, start, sectors, table.partitions())
    } else {
        let (number, start) = mbr_append(&mut sector0)?;
        let sectors = have.max(start.checked_add(REGION_SECTORS).ok_or(PartError::Range)?);
        file.set_len(sectors.checked_mul(SECTOR).ok_or(PartError::Range)?)?;
        region(file, start)?;
        write_at(file, 0, &sector0)?;
        let partitions = mbr_entries(&sector0)
            .into_iter()
            .filter_map(|(i, kind, start, sectors)| {
                Some(Partition {
                    number: number_of(i).ok()?,
                    start,
                    sectors,
                    kind: wyrm_core::hex::encode([kind]),
                    name: String::new(),
                })
            })
            .collect();
        (number, start, sectors, partitions)
    };
    file.sync_all()?;
    Ok(Appended {
        config_offset: start.checked_mul(SECTOR).ok_or(PartError::Range)?,
        config_part,
        size: sectors.checked_mul(SECTOR).ok_or(PartError::Range)?,
        partitions,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    const MIB: u64 = 1 << 20;

    fn mbr(parts: &[(u8, u32, u32)]) -> Vec<u8> {
        let mut sector = vec![0u8; SECTOR_LEN];
        sector[510] = 0x55;
        sector[511] = 0xaa;
        // what a boot loader keeps before the entries stays
        sector[..4].copy_from_slice(b"BOOT");
        sector[440..444].copy_from_slice(&0x5452_574f_u32.to_le_bytes());
        for (i, (kind, start, sectors)) in parts.iter().enumerate() {
            let at = MBR_ENTRIES + i * MBR_ENTRY;
            sector[at + 4] = *kind;
            sector[at + 8..at + 12].copy_from_slice(&start.to_le_bytes());
            sector[at + 12..at + 16].copy_from_slice(&sectors.to_le_bytes());
        }
        sector
    }

    /// A GPT image of `sectors` sectors as OpenWrt's `ptgen` lays it out: the header in
    /// sector 1, 128 entries from sector 2, the second table in the last 33 sectors.
    fn gpt_image(sectors: u64, parts: &[(usize, u64, u64, &str)], hybrid: bool) -> Vec<u8> {
        let mut image = vec![0u8; usize::try_from(sectors * SECTOR).unwrap()];
        let pmbr = if hybrid {
            mbr(&[(0x83, 34, 8000), (0xee, 1, 33)])
        } else {
            mbr(&[(0xee, 1, 0xffff_ffff)])
        };
        image[..SECTOR_LEN].copy_from_slice(&pmbr);
        let mut entries = vec![0u8; 128 * GPT_ENTRY];
        for (index, first, last, name) in parts {
            let at = index * GPT_ENTRY;
            entries[at..at + 16].copy_from_slice(&[0xaf; 16]);
            entries[at + 16] = u8::try_from(*index).unwrap() + 1;
            entries[at + 32..at + 40].copy_from_slice(&first.to_le_bytes());
            entries[at + 40..at + 48].copy_from_slice(&last.to_le_bytes());
            let name: Vec<u8> = name.encode_utf16().flat_map(u16::to_le_bytes).collect();
            entries[at + 56..at + 56 + name.len()].copy_from_slice(&name);
        }
        let mut header = vec![0u8; SECTOR_LEN];
        header[..8].copy_from_slice(b"EFI PART");
        header[8..12].copy_from_slice(&0x0001_0000_u32.to_le_bytes());
        header[12..16].copy_from_slice(&92u32.to_le_bytes());
        header[24..32].copy_from_slice(&1u64.to_le_bytes());
        header[32..40].copy_from_slice(&(sectors - 1).to_le_bytes());
        header[40..48].copy_from_slice(&34u64.to_le_bytes());
        header[48..56].copy_from_slice(&(sectors - 34).to_le_bytes());
        header[56..72].copy_from_slice(&[0x11; 16]);
        header[72..80].copy_from_slice(&2u64.to_le_bytes());
        header[80..84].copy_from_slice(&128u32.to_le_bytes());
        header[84..88].copy_from_slice(&128u32.to_le_bytes());
        header[88..92].copy_from_slice(&crc32(&entries).to_le_bytes());
        let crc = crc32(&header[..92]);
        header[16..20].copy_from_slice(&crc.to_le_bytes());
        image[512..1024].copy_from_slice(&header);
        image[1024..1024 + entries.len()].copy_from_slice(&entries);
        image
    }

    /// Checks a GPT as a reader does: both headers, their checksums and their arrays.
    fn check_gpt(image: &[u8]) -> Gpt {
        let sectors = u64::try_from(image.len()).unwrap() / SECTOR;
        let sector = |n: u64, len: usize| {
            let at = usize::try_from(n * SECTOR).unwrap();
            image[at..at + len].to_vec()
        };
        let first = sector(1, SECTOR_LEN);
        let (entries_lba, count) = gpt_header(&first).unwrap();
        let len = usize::try_from(count).unwrap() * GPT_ENTRY;
        let table = Gpt::new(first.clone(), sector(entries_lba, len)).unwrap();
        // the second header lies where the first says, in the last sector
        assert_eq!(le64(&first, 32), Some(sectors - 1));
        let mut second = sector(sectors - 1, SECTOR_LEN);
        assert_eq!(&second[..8], b"EFI PART");
        assert_eq!(le64(&second, 24), Some(sectors - 1));
        assert_eq!(le64(&second, 32), Some(1));
        let second_entries = le64(&second, 72).unwrap();
        assert_eq!(second_entries, sectors - 1 - 32);
        assert_eq!(sector(second_entries, len), table.entries);
        assert_eq!(le32(&second, 88), le32(&first, 88));
        let crc = le32(&second, 16).unwrap();
        second[16..20].fill(0);
        assert_eq!(crc, crc32(&second[..92]));
        // every partition lies between the first and the last usable sector
        let last_usable = le64(&first, 48).unwrap();
        assert!(last_usable < second_entries);
        for (_, start, last) in table.used() {
            assert!(start >= le64(&first, 40).unwrap() && last <= last_usable);
        }
        table
    }

    fn temp(name: &str, bytes: &[u8]) -> (std::path::PathBuf, File) {
        let path = std::env::temp_dir().join(format!("wyr-part-{name}-{}", std::process::id()));
        std::fs::write(&path, bytes).unwrap();
        let file = File::options().read(true).write(true).open(&path).unwrap();
        (path, file)
    }

    #[test]
    fn an_mbr_gets_the_config_partition_after_the_root() {
        // the layout of a Raspberry Pi image: boot at 4 MiB, root of 256 MiB at 68 MiB
        let mut sector = mbr(&[(0x0c, 8192, 131_072), (0x83, 139_264, 524_288)]);
        let before = sector.clone();
        let (number, start) = mbr_append(&mut sector).unwrap();
        assert_eq!((number, start), (3, 663_552));
        assert_eq!(start % ALIGN, 0);
        // nothing but the third entry changed
        assert_eq!(sector[..MBR_ENTRIES + 32], before[..MBR_ENTRIES + 32]);
        assert_eq!(sector[MBR_ENTRIES + 48..], before[MBR_ENTRIES + 48..]);
        assert_eq!(
            mbr_entries(&sector).get(2),
            Some(&(2, MBR_TYPE, 663_552, 8192))
        );
        // a root that does not end on a boundary: the next one
        let mut sector = mbr(&[(0x0c, 8192, 131_072), (0x83, 139_264, 524_289)]);
        assert_eq!(mbr_append(&mut sector).unwrap(), (3, 663_552 + 2048));
        // the entries are found by what they hold, not by their order
        let mut sector = mbr(&[(0x83, 139_264, 524_288), (0x0c, 8192, 131_072)]);
        assert_eq!(mbr_append(&mut sector).unwrap(), (3, 663_552));
    }

    #[test]
    fn an_mbr_that_cannot_take_it_is_refused() {
        let mut full = mbr(&[
            (0x0c, 8192, 8),
            (0x83, 9000, 8),
            (0x83, 9100, 8),
            (0x83, 9200, 8),
        ]);
        assert!(matches!(mbr_append(&mut full), Err(PartError::Full)));
        let mut empty = mbr(&[]);
        assert!(matches!(mbr_append(&mut empty), Err(PartError::Empty)));
        let mut none = vec![0u8; SECTOR_LEN];
        assert!(matches!(mbr_append(&mut none), Err(PartError::NoTable)));
        // a partition that ends at the last sector an MBR can name
        let mut end = mbr(&[(0x83, 0xffff_f000, 0xfff)]);
        assert!(matches!(mbr_append(&mut end), Err(PartError::Range)));
    }

    #[test]
    fn an_mbr_image_grows_by_the_region() {
        let mut image = vec![0x5au8; usize::try_from(70 * MIB).unwrap()];
        // the image ends before its root partition does, as OpenWrt writes it
        image[..SECTOR_LEN]
            .copy_from_slice(&mbr(&[(0x0c, 8192, 131_072), (0x83, 139_264, 524_288)]));
        let (path, mut file) = temp("mbr", &image);
        let done = append_config(&mut file, false).unwrap();
        assert_eq!(done.config_part, 3);
        assert_eq!(done.config_offset, 324 * MIB);
        assert_eq!(done.size, 328 * MIB);
        assert_eq!(
            done.partitions.iter().map(|p| p.number).collect::<Vec<_>>(),
            [1, 2, 3]
        );
        let after = std::fs::read(&path).unwrap();
        assert_eq!(u64::try_from(after.len()).unwrap(), done.size);
        let at = usize::try_from(done.config_offset).unwrap();
        let region = &after[at..];
        assert_eq!(&region[..8], MAGIC_EMPTY);
        assert!(region[8..].iter().all(|b| *b == 0));
        assert!(wyrm_image::read_region(region).unwrap().is_none());
        // what the image held is there as it was, but the one entry
        assert_eq!(after[SECTOR_LEN..image.len()], image[SECTOR_LEN..]);
        assert!(after[image.len()..at].iter().all(|b| *b == 0));
        // a GPT was asked for
        assert!(matches!(
            append_config(&mut file, true),
            Err(PartError::OtherTable { .. })
        ));
        std::fs::remove_file(&path).unwrap();
    }

    #[test]
    fn a_gpt_gets_the_config_partition_and_both_tables() {
        // the layout of an armsr image: a boot partition, a root of 256 MiB, and the entry
        // of the last index that OpenWrt gives a BIOS boot partition
        let sectors = 290 * 2048;
        let parts = [
            (0, 2048, 2048 + 32_768 - 1, "kernel"),
            (1, 67_584, 67_584 + 524_288 - 1, "rootfs"),
            (127, 34, 2047, "bios"),
        ];
        let image = gpt_image(sectors, &parts, false);
        let (path, mut file) = temp("gpt", &image);
        let done = append_config(&mut file, true).unwrap();
        // the first free entry is the third; the region starts where the root ends
        assert_eq!(done.config_part, 3);
        assert_eq!(done.config_offset, (67_584 + 524_288) * SECTOR);
        assert_eq!(done.config_offset % MIB, 0);
        // 4 MiB of region and 1 MiB for the second table
        assert_eq!(done.size, done.config_offset + 5 * MIB);
        let after = std::fs::read(&path).unwrap();
        assert_eq!(u64::try_from(after.len()).unwrap(), done.size);
        let table = check_gpt(&after);
        let used = table.used();
        assert_eq!(used.len(), 4);
        // the entries that were there are there byte for byte
        for (index, ..) in parts {
            let at = 1024 + index * GPT_ENTRY;
            assert_eq!(
                after[at..at + GPT_ENTRY],
                image[at..at + GPT_ENTRY],
                "{index}"
            );
        }
        let config = &done.partitions[2];
        assert_eq!(
            (
                config.number,
                config.start,
                config.sectors,
                config.name.as_str()
            ),
            (3, 67_584 + 524_288, 8192, "wyrm-config")
        );
        assert_eq!(config.kind, "8DA63339-0007-60C0-C436-083AC8230908");
        let entry = &after[1024 + 2 * GPT_ENTRY..1024 + 3 * GPT_ENTRY];
        assert_eq!(
            guid_text(&entry[16..32]).unwrap(),
            "57595243-4647-4000-8000-575952434647"
        );
        // the first sector is not written, the disk id stays
        assert_eq!(after[..SECTOR_LEN], image[..SECTOR_LEN]);
        assert_eq!(after[512 + 56..512 + 72], image[512 + 56..512 + 72]);
        let at = usize::try_from(done.config_offset).unwrap();
        let region = &after[at..at + usize::try_from(CONFIG_SIZE).unwrap()];
        assert!(wyrm_image::read_region(region).unwrap().is_none());
        // an MBR was asked for
        assert!(matches!(
            append_config(&mut file, false),
            Err(PartError::OtherTable { .. })
        ));
        std::fs::remove_file(&path).unwrap();
    }

    #[test]
    fn a_gpt_image_shorter_than_its_partitions_and_a_hybrid_mbr() {
        // mediatek/filogic: the table names a root partition the file does not reach, the
        // first sector is a hybrid MBR, and a second table lies nowhere
        let parts = [
            (0, 34, 8191, "bl2"),
            (1, 8192, 9215, "ubootenv"),
            (2, 9216, 13_311, "factory"),
            (3, 13_312, 21_503, "fip"),
            (4, 24_576, 90_111, "recovery"),
            (5, 90_112, 131_071, "install"),
            (6, 131_072, 131_072 + 524_288 - 1, "production"),
        ];
        let mut image = gpt_image(80 * 2048, &parts, true);
        // as OpenWrt 25.12.6 writes it, the image ends 4 bytes into a sector
        image.extend_from_slice(b"\x01\x02\x03\x04");
        // the header says a disk as large as the partitions
        let disk = 131_072 + 524_288 + 2048u64;
        image[512 + 32..512 + 40].copy_from_slice(&(disk - 1).to_le_bytes());
        image[512 + 48..512 + 56].copy_from_slice(&(disk - 34).to_le_bytes());
        image[512 + 16..512 + 20].fill(0);
        let crc = crc32(&image[512..512 + 92]);
        image[512 + 16..512 + 20].copy_from_slice(&crc.to_le_bytes());
        let (path, mut file) = temp("filogic", &image);
        let done = append_config(&mut file, true).unwrap();
        assert_eq!(done.config_part, 8);
        assert_eq!(done.config_offset, (131_072 + 524_288) * SECTOR);
        assert_eq!(done.size, done.config_offset + 5 * MIB);
        let after = std::fs::read(&path).unwrap();
        check_gpt(&after);
        // the hybrid MBR is there byte for byte, and what the image held
        assert_eq!(after[..SECTOR_LEN], image[..SECTOR_LEN]);
        assert_eq!(after[34 * 512..image.len()], image[34 * 512..]);
        assert_eq!(done.size % SECTOR, 0);
        assert_eq!(
            done.partitions
                .iter()
                .map(|p| p.name.as_str())
                .collect::<Vec<_>>(),
            [
                "bl2",
                "ubootenv",
                "factory",
                "fip",
                "recovery",
                "install",
                "production",
                "wyrm-config"
            ]
        );
        std::fs::remove_file(&path).unwrap();
    }

    #[test]
    fn a_gpt_that_is_not_sound_is_refused() {
        let parts = [(0, 2048, 4095, "a")];
        let sound = gpt_image(16 * 2048, &parts, false);
        let refused = |change: &dyn Fn(&mut Vec<u8>)| {
            let mut image = sound.clone();
            change(&mut image);
            let (path, mut file) = temp("bad", &image);
            let result = append_config(&mut file, true);
            // nothing is written into an image that is refused
            assert_eq!(std::fs::read(&path).unwrap(), image);
            std::fs::remove_file(&path).unwrap();
            result.unwrap_err()
        };
        assert!(matches!(refused(&|i| i[512] = b'X'), PartError::Gpt(_)));
        // one bit of the header, one bit of an entry
        assert!(matches!(refused(&|i| i[512 + 40] ^= 1), PartError::Gpt(_)));
        assert!(matches!(refused(&|i| i[1024 + 33] ^= 1), PartError::Gpt(_)));
        // no room in the array
        let full: Vec<(usize, u64, u64, &str)> = (0..128usize)
            .map(|i| {
                let at = 2048 + u64::try_from(i).unwrap();
                (i, at, at, "x")
            })
            .collect();
        let image = gpt_image(16 * 2048, &full, false);
        let (path, mut file) = temp("full", &image);
        assert!(matches!(
            append_config(&mut file, true),
            Err(PartError::Full)
        ));
        std::fs::remove_file(&path).unwrap();
        // no partition at all
        let image = gpt_image(16 * 2048, &[], false);
        let (path, mut file) = temp("none", &image);
        assert!(matches!(
            append_config(&mut file, true),
            Err(PartError::Empty)
        ));
        std::fs::remove_file(&path).unwrap();
        // a file that is no image
        let (path, mut file) = temp("short", &[0u8; 700]);
        assert!(matches!(
            append_config(&mut file, true),
            Err(PartError::NoTable)
        ));
        std::fs::remove_file(&path).unwrap();
    }
}
