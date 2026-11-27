//! `wyr image build` and `wyr image inspect` (ADR 0051 §4): a person's configuration written
//! into the config region of a board's base image, offline.
//!
//! The format and every check of it are `wyrm-image` (pure; the page runs the same code).
//! This module is the I/O around it: the base image is read once, raw or gzip, and copied
//! into a temporary file beside the output while its SHA-256 is taken; the image is compared
//! with its index entry, the region must be the empty one of a base image, and only then the
//! region is written and the file gets its name. A refused or failed run leaves no output.
//!
//! The output holds the setup hash and the configuration, so it is made for its owner alone
//! (0600 on Unix). A new setup code is printed once, on stdout; its hash is printed nowhere.

use clap::Subcommand;
use std::fs::File;
use std::io::{self, Read, Seek, SeekFrom, Write};
use std::path::{Path, PathBuf};
use wyrm_core::files::{gone_ok, read_full};
use wyrm_core::hex::{self, Sha256Stream};
use wyrm_image::{
    read_region, region, ConfigFiles, ImageEntry, ImageError, Index, CONFIG_SIZE, MAGIC_FULL,
};
use zeroize::Zeroizing;

#[derive(Subcommand, Debug)]
pub enum ImageCmd {
    /// Write a configuration into a board's base image: the result is an image to put on
    /// the card. The base image (raw or `.gz`) must be the one the index describes.
    Build {
        /// The base image of the board, as downloaded: raw (`.img`) or gzip (`.img.gz`).
        #[arg(long)]
        image: PathBuf,
        /// The index of base images (`wyrm-images/1`) the image was published with.
        #[arg(long)]
        index: PathBuf,
        /// The board id, as the index names it.
        #[arg(long)]
        board: String,
        /// The broker's configuration (`wyrmd.json5`).
        #[arg(long)]
        config: PathBuf,
        /// The network configuration of the device, a UCI file. Without it: DHCP.
        #[arg(long)]
        network: Option<PathBuf>,
        /// Which of the links the image carries are installed at the first start
        /// (`wyrm-seed/1`).
        #[arg(long)]
        seed: Option<PathBuf>,
        /// A file with the hash of a setup code made before (the second line of `wyrmd
        /// setup-code`): 64 hex digits. The hash is a secret of the image, so it is read
        /// from a file and never given as an argument.
        #[arg(long, value_name = "FILE")]
        setup_hash_file: Option<PathBuf>,
        /// Make a new setup code, put its hash into the image and print the code once.
        #[arg(long, conflicts_with = "setup_hash_file")]
        new_setup_code: bool,
        /// SSH public keys for `root`. Without it the device has no SSH login.
        #[arg(long)]
        authorized_keys: Option<PathBuf>,
        /// The IANA name of the time zone (`Europe/Kyiv`).
        #[arg(long, value_name = "TZ")]
        timezone: Option<String>,
        /// NTP servers, separated by commas.
        #[arg(long, value_name = "SERVERS")]
        ntp: Option<String>,
        /// The image to write (raw).
        #[arg(long)]
        out: PathBuf,
        /// Replace `--out` when it exists.
        #[arg(long)]
        force: bool,
    },
    /// Make the base image of a board with OpenWrt's ImageBuilder in a container: the image
    /// (raw and gzip), with an empty config region, and its entry in `index.json`.
    Base(crate::image_base::BaseArgs),
    /// Show what the config region of an image holds: empty or assembled, and the names
    /// and sizes of its files. Never a file's content.
    Inspect {
        /// The image: raw or gzip.
        #[arg(long)]
        image: PathBuf,
        /// The index of base images the image was published with.
        #[arg(long)]
        index: PathBuf,
        /// The board id, as the index names it.
        #[arg(long)]
        board: String,
    },
}

/// Why `wyr image` refused or failed.
#[derive(Debug, thiserror::Error)]
pub enum ImageCmdError {
    /// A file could not be read or written (`what` says which step).
    #[error("{what} `{}`: {source}", path.display())]
    Io {
        what: &'static str,
        path: PathBuf,
        source: io::Error,
    },
    /// The format refused the index, the files or the region.
    #[error(transparent)]
    Image(#[from] ImageError),
    /// `wyr image base` refused or failed.
    #[error(transparent)]
    Base(#[from] crate::image_base::BaseError),
    /// The index has no entry for the board.
    #[error("no board `{board}` in the index; it has: {known}")]
    NoBoard { board: String, known: String },
    /// The file of `--setup-hash-file` does not hold a hash. Its text is not repeated.
    #[error("`{}` does not hold the hash of a setup code (64 hex digits)", .0.display())]
    BadSetupHash(PathBuf),
    /// `--out` names the base image itself.
    #[error("`{}` is the base image: --out must be another file", .0.display())]
    SameFile(PathBuf),
    /// The OS gave no randomness for a new setup code.
    #[error("setup code: {0}")]
    NoRandomness(#[from] wyrm_core::rand::NoRandomness),
    /// `--out` is there and `--force` is not.
    #[error("`{}` exists; give --force to replace it", .0.display())]
    Exists(PathBuf),
    /// The region of the image holds a configuration already.
    #[error(
        "`{}` already holds a configuration: an assembled image is not a base image. \
         Take the base image of board `{board}` as it was published",
        image.display()
    )]
    Assembled { image: PathBuf, board: String },
    /// The image is not the one of the index entry: nothing is written into it, since the
    /// offset of the region is right for those bytes only. `found` says what the image has
    /// and what the index says.
    #[error("`{}` is not the base image of board `{board}`: {found}", image.display())]
    NotBase {
        image: PathBuf,
        board: String,
        found: String,
    },
    /// The file is too short (or, raw, of another size) to be an image of the board.
    #[error("`{}` is not an image of board `{board}`: the index says {want_size} bytes", image.display())]
    NotImage {
        image: PathBuf,
        board: String,
        want_size: u64,
    },
    /// A run failed and its temporary file could not be removed.
    #[error("{why}; the temporary file `{}` stays: {source}", path.display())]
    Left {
        why: Box<ImageCmdError>,
        path: PathBuf,
        source: io::Error,
    },
}

type Result<T> = std::result::Result<T, ImageCmdError>;

fn io_err<'a>(
    what: &'static str,
    path: &'a Path,
) -> impl FnOnce(io::Error) -> ImageCmdError + use<'a> {
    move |source| ImageCmdError::Io {
        what,
        path: path.to_owned(),
        source,
    }
}

pub fn run(cmd: ImageCmd) -> Result<()> {
    match cmd {
        ImageCmd::Build {
            image,
            index,
            board,
            config,
            network,
            seed,
            setup_hash_file,
            new_setup_code,
            authorized_keys,
            timezone,
            ntp,
            out,
            force,
        } => {
            let entry = entry(&index, &board)?;
            let text = |path: &Option<PathBuf>| path.as_deref().map(read_text).transpose();
            let (setup, code) = setup(setup_hash_file.as_deref(), new_setup_code)?;
            let files = ConfigFiles {
                wyrmd_json5: read_text(&config)?,
                network: text(&network)?,
                seed_json: text(&seed)?,
                setup,
                authorized_keys: text(&authorized_keys)?,
                // one name, as given: a space inside it is refused by the check, not split
                timezone: timezone.as_deref().map(|tz| format!("{}\n", tz.trim())),
                ntp: ntp.as_deref().and_then(servers),
            };
            // refused here, before the image is read
            let region = region(&files)?;
            build(&image, &entry, &region, &out, force)?;
            out!("{}", out.display());
            if let Some(code) = code {
                out!("setup code: {}", code.as_str());
            }
            Ok(())
        }
        ImageCmd::Base(args) => Ok(crate::image_base::run(&args)?),
        ImageCmd::Inspect {
            image,
            index,
            board,
        } => inspect(&image, &entry(&index, &board)?),
    }
}

/// The entry of `board` in the index file.
fn entry(index: &Path, board: &str) -> Result<ImageEntry> {
    let index = Index::parse(&read_text(index)?)?;
    index
        .image(board)
        .cloned()
        .ok_or_else(|| ImageCmdError::NoBoard {
            board: board.to_owned(),
            known: index
                .images
                .iter()
                .map(|image| image.board.as_str())
                .collect::<Vec<_>>()
                .join(", "),
        })
}

fn read_text(path: &Path) -> Result<String> {
    std::fs::read_to_string(path).map_err(io_err("read", path))
}

/// The NTP servers of `--ntp` as the file `ntp`: split at commas and white space, one per
/// line. `None` when there is none.
fn servers(arg: &str) -> Option<String> {
    let mut out = String::new();
    for word in arg.split(|c: char| c.is_whitespace() || c == ',') {
        if !word.is_empty() {
            out.push_str(word);
            out.push('\n');
        }
    }
    (!out.is_empty()).then_some(out)
}

/// The `setup` file (the hash as lower-case hex) and, for a new code, the code to print.
/// `hash_file` holds a hash made before: 64 hex digits, white space around them ignored (the
/// format of `gateway.setup_file`).
fn setup(
    hash_file: Option<&Path>,
    new_code: bool,
) -> Result<(Option<String>, Option<Zeroizing<String>>)> {
    if new_code {
        let (code, hash) = wyrm_core::setup::new_code()?;
        return Ok((Some(hex::encode(hash)), Some(Zeroizing::new(code))));
    }
    let Some(path) = hash_file else {
        return Ok((None, None));
    };
    let text = Zeroizing::new(read_text(path)?);
    let hash = text.trim();
    if !hex::is_hex(hash, 32) {
        return Err(ImageCmdError::BadSetupHash(path.to_owned()));
    }
    Ok((Some(hash.to_ascii_lowercase()), None))
}

/// An image file as its raw bytes: a gzip file (told by its first two bytes) is unpacked
/// while it is read, every member of it (`pigz` writes several).
enum Input {
    Raw(File),
    Gz(Box<flate2::read::MultiGzDecoder<io::BufReader<File>>>),
}

impl Input {
    fn open(path: &Path) -> io::Result<Self> {
        let mut file = File::open(path)?;
        let mut magic = [0u8; 2];
        let got = read_full(&mut file, &mut magic)?;
        file.seek(SeekFrom::Start(0))?;
        Ok(if got == 2 && magic == [0x1f, 0x8b] {
            Self::Gz(Box::new(flate2::read::MultiGzDecoder::new(
                io::BufReader::new(file),
            )))
        } else {
            Self::Raw(file)
        })
    }

    /// Moves to `offset` of the raw bytes, from the start. `false` when a gzip file ends
    /// before it.
    fn skip(&mut self, offset: u64) -> io::Result<bool> {
        match self {
            Self::Raw(file) => file.seek(SeekFrom::Start(offset)).map(|_| true),
            Self::Gz(gz) => Ok(io::copy(&mut gz.take(offset), &mut io::sink())? == offset),
        }
    }
}

impl Read for Input {
    fn read(&mut self, buf: &mut [u8]) -> io::Result<usize> {
        match self {
            Self::Raw(file) => file.read(buf),
            Self::Gz(gz) => gz.read(buf),
        }
    }
}

/// The temporary file of an output: beside it, so the last step is one rename.
fn temp_beside(out: &Path) -> PathBuf {
    let mut name = out.file_name().unwrap_or_default().to_owned();
    name.push(format!(".{}.tmp", std::process::id()));
    out.with_file_name(name)
}

fn create_private(path: &Path) -> io::Result<File> {
    let mut options = File::options();
    options.read(true).write(true).create_new(true);
    #[cfg(unix)]
    {
        use std::os::unix::fs::OpenOptionsExt as _;
        options.mode(0o600);
    }
    options.open(path)
}

/// Assembles `out` from the base image: all of it in a temporary file first, which is
/// removed when any step refuses or fails.
fn build(image: &Path, entry: &ImageEntry, region: &[u8], out: &Path, force: bool) -> Result<()> {
    let exists = || match out.try_exists() {
        Ok(true) if !force => Err(ImageCmdError::Exists(out.to_owned())),
        Ok(_) => Ok(()),
        Err(e) => Err(io_err("look for", out)(e)),
    };
    exists()?;
    // also with --force: the base image is not replaced by what is made of it
    if let (Ok(a), Ok(b)) = (out.canonicalize(), image.canonicalize()) {
        if a == b {
            return Err(ImageCmdError::SameFile(out.to_owned()));
        }
    }
    let tmp = temp_beside(out);
    // what an interrupted run of the same process id left
    std::fs::remove_file(&tmp)
        .or_else(gone_ok)
        .map_err(io_err("remove", &tmp))?;
    let mut file = create_private(&tmp).map_err(io_err("create", &tmp))?;
    let done = assemble(image, entry, region, &mut file, &tmp)
        .and_then(|()| exists())
        .and_then(|()| std::fs::rename(&tmp, out).map_err(io_err("write", out)));
    drop(file);
    match done {
        Ok(()) => Ok(()),
        Err(why) => Err(match std::fs::remove_file(&tmp).or_else(gone_ok) {
            Ok(()) => why,
            Err(source) => ImageCmdError::Left {
                why: Box::new(why),
                path: tmp,
                source,
            },
        }),
    }
}

/// Copies the image into `file` (the temporary file at `tmp`), checks it and writes the
/// region: the image is the one of `entry`, and its region is the empty one of a base image.
fn assemble(
    image: &Path,
    entry: &ImageEntry,
    region: &[u8],
    file: &mut File,
    tmp: &Path,
) -> Result<()> {
    let write = || io_err("write", tmp);
    let mut input = Input::open(image).map_err(io_err("read", image))?;
    // one byte past the entry's size is enough to know the image is another one
    let mut input = (&mut input).take(entry.size.saturating_add(1));
    let mut hash = Sha256Stream::new();
    let mut size = 0u64;
    let mut buf = vec![0u8; 1 << 20];
    loop {
        let n = read_full(&mut input, &mut buf).map_err(io_err("read", image))?;
        let Some(part) = buf.get(..n).filter(|part| !part.is_empty()) else {
            break;
        };
        hash.update(part);
        file.write_all(part).map_err(write())?;
        size = size.saturating_add(u64::try_from(n).unwrap_or(u64::MAX));
    }
    let hash = hash.finish();

    let mut read_at = |buf: &mut [u8]| -> Result<usize> {
        file.seek(SeekFrom::Start(entry.config_offset))
            .map_err(write())?;
        read_full(file, buf).map_err(write())
    };
    // told before the SHA-256, which an assembled image fails too
    let mut magic = [0u8; 8];
    if read_at(&mut magic)? == magic.len() && magic == *MAGIC_FULL {
        return Err(ImageCmdError::Assembled {
            image: image.to_owned(),
            board: entry.board.clone(),
        });
    }
    if !entry.matches(size, &hash) {
        // the copy stops one byte past the entry's size: a longer file has no SHA-256 here
        let has = if size > entry.size {
            format!("it has more than {} bytes", entry.size)
        } else {
            format!("it has {size} bytes and SHA-256 {}", hex::encode(hash))
        };
        return Err(ImageCmdError::NotBase {
            image: image.to_owned(),
            board: entry.board.clone(),
            found: format!(
                "{has}, the index says {} bytes and SHA-256 {}",
                entry.size, entry.sha256
            ),
        });
    }
    // the image is the entry's, so the region lies inside it (`Index::check`)
    let mut was = vec![0u8; region.len()];
    read_at(&mut was)?;
    if read_region(&was)?.is_some() {
        return Err(ImageCmdError::Assembled {
            image: image.to_owned(),
            board: entry.board.clone(),
        });
    }
    file.seek(SeekFrom::Start(entry.config_offset))
        .map_err(write())?;
    file.write_all(region).map_err(write())?;
    file.sync_all().map_err(write())
}

/// Prints the board, the state of the region and the names and sizes of its files.
fn inspect(image: &Path, entry: &ImageEntry) -> Result<()> {
    let not_image = || ImageCmdError::NotImage {
        image: image.to_owned(),
        board: entry.board.clone(),
        want_size: entry.size,
    };
    let read = || io_err("read", image);
    let mut input = Input::open(image).map_err(read())?;
    if let Input::Raw(file) = &input {
        // the offset is right for an image of this size only
        if file.metadata().map_err(read())?.len() != entry.size {
            return Err(not_image());
        }
    }
    let Ok(len) = usize::try_from(CONFIG_SIZE) else {
        return Err(ImageError::TooLarge.into());
    };
    let mut bytes = vec![0u8; len];
    if !input.skip(entry.config_offset).map_err(read())?
        || read_full(&mut input, &mut bytes).map_err(read())? != len
    {
        return Err(not_image());
    }
    let files = read_region(&bytes)?;
    out!("board: {}", entry.board);
    let Some(files) = files else {
        out!("region: empty");
        return Ok(());
    };
    out!("region: assembled");
    // sizes only: `setup` and `authorized_keys` are never shown, and no other file is
    let sizes = [
        ("wyrmd.json5", Some(files.wyrmd_json5.len())),
        ("network", files.network.as_ref().map(String::len)),
        ("seed.json", files.seed_json.as_ref().map(String::len)),
        ("setup", files.setup.as_ref().map(String::len)),
        (
            "authorized_keys",
            files.authorized_keys.as_ref().map(String::len),
        ),
        ("timezone", files.timezone.as_ref().map(String::len)),
        ("ntp", files.ntp.as_ref().map(String::len)),
    ];
    for (name, size) in sizes {
        if let Some(size) = size {
            out!("{name} {size}");
        }
    }
    // an image that someone else assembled: a file the broker will never read is told
    for unread in files.not_named() {
        out!("WARNING: {unread}");
    }
    // and what the device refuses: such an image starts no broker
    if let Err(refused) = files.check_device() {
        out!("WARNING: {refused}");
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn servers_become_a_file_of_lines() {
        assert_eq!(
            servers("a.example, b.example,,c.example").as_deref(),
            Some("a.example\nb.example\nc.example\n")
        );
        assert_eq!(servers("pool.ntp.org").as_deref(), Some("pool.ntp.org\n"));
        assert_eq!(servers(" , "), None);
        assert_eq!(servers(""), None);
    }

    #[test]
    fn a_setup_hash_file_is_checked_and_lowered() {
        let hash = "3F0A9C1E5B7D2468ACE013579BDF02468ACE13579BDF0246813579BDF02468AC";
        let path = std::env::temp_dir().join(format!("wyr-image-hash-{}", std::process::id()));
        let with = |text: &str| {
            std::fs::write(&path, text).unwrap();
            setup(Some(&path), false)
        };
        // as `wyrmd setup-code` prints it, with white space around
        let (file, code) = with(&format!("  {hash}\n")).unwrap();
        assert_eq!(file, Some(hash.to_lowercase()));
        assert!(code.is_none());
        assert!(matches!(setup(None, false), Ok((None, None))));
        let short = hash.get(1..).unwrap();
        for bad in [
            "",
            "abc",
            short,
            &format!("{hash}0"),
            &hash.replace('3', "g"),
        ] {
            let e = with(bad).unwrap_err();
            assert!(matches!(e, ImageCmdError::BadSetupHash(_)), "{bad}");
            assert!(bad.is_empty() || !e.to_string().contains(bad));
        }
        std::fs::remove_file(&path).unwrap();
        assert!(matches!(
            setup(Some(&path), false),
            Err(ImageCmdError::Io { .. })
        ));
        // a new code: its hash for the image, the code for the person; never the same twice
        let (file, code) = setup(None, true).unwrap();
        let code = code.unwrap();
        let hash = wyrm_core::setup::code_hash(&code).unwrap();
        assert_eq!(file, Some(hex::encode(hash)));
        let (other, _) = setup(None, true).unwrap();
        assert_ne!(other, file);
    }

    #[test]
    fn the_temporary_file_is_beside_the_output() {
        let tmp = temp_beside(Path::new("images/out.img"));
        assert_eq!(tmp.parent(), Some(Path::new("images")));
        let name = tmp.file_name().unwrap().to_string_lossy().into_owned();
        assert!(
            name.starts_with("out.img.") && name.ends_with(".tmp"),
            "{name}"
        );
        assert_eq!(
            temp_beside(Path::new("out.img")).parent(),
            Some(Path::new(""))
        );
    }
}
