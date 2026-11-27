//! `wyr image base` (ADR 0051 §2, §4): the base image of one board, made locally with
//! OpenWrt's ImageBuilder in a container.
//!
//! The boards are data: `packaging/images/boards.json` names the pinned OpenWrt release, the
//! ImageBuilder archive of each target with its SHA-256, the container the build runs in (by
//! digest) and, per board, the profile, the size of the root partition and where the config
//! region is on the device. This module reads that list, stages the files of the image (the
//! package `wyrmd` as files, the broker's binary, the seed packages and `/etc/wyrm/image.json`),
//! runs `packaging/images/build.sh` in the container, appends the config partition to the
//! image the ImageBuilder made (`image_part`) and writes what is published: the raw image,
//! its gzip, the listing of its partitions and the entry of `index.json`.
//!
//! Nothing here needs root. The container gets the staged files read-only and one directory
//! to write, no capability and no device; the partition table is edited in the image file.
//! The result is read back before it is published: the region must be the empty one at the
//! offset of the entry, in the partition the board's `config_dev` names.

use clap::{Args, ValueEnum};
use serde::{Deserialize, Serialize};
use std::ffi::OsString;
use std::fs::File;
use std::io::{self, Seek, SeekFrom, Write};
use std::path::{Path, PathBuf};
use std::process::Command;
use wyrm_core::files::read_full;
use wyrm_core::hex::{self, Sha256Stream};
use wyrm_image::{read_region, Download, ImageEntry, ImageError, Index, CONFIG_SIZE, SEED_DIR};

use crate::image_part::{append_config, Appended, PartError, SECTOR};

/// The format name of `boards.json`.
pub const BOARDS_FORMAT: &str = "wyrm-boards/1";
/// The format name of `/etc/wyrm/image.json`.
pub const IMAGE_JSON_FORMAT: &str = "wyrm-image/1";
/// Where ImageBuilder archives are published. An archive of `boards.json` is this, the
/// release, the target and the file name OpenWrt gives it: nothing else is downloaded.
const DOWNLOADS: &str = "https://downloads.openwrt.org/releases";
/// The host OpenWrt builds its ImageBuilder for.
const BUILD_PLATFORM: &str = "linux/amd64";

/// The partition table of a board's image.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Deserialize, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum Table {
    /// MBR (`bcm27xx`).
    Mbr,
    /// GPT (`mediatek/filogic`, `armsr`).
    Gpt,
}

/// How the config region gets into the image.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Deserialize, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum ConfigPart {
    /// A partition appended after the last partition of the ImageBuilder's image.
    Append,
}

/// The storage a board starts from.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Deserialize, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum BootFrom {
    /// A (micro)SD card.
    Sd,
    /// A virtio disk (QEMU).
    Virtio,
}

/// The ImageBuilder archive of one OpenWrt target.
#[derive(Debug, Clone, PartialEq, Eq, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub struct ImageBuilder {
    /// The OpenWrt target, `<target>/<subtarget>`.
    pub target: String,
    /// Where the archive is published.
    pub url: String,
    /// The SHA-256 of the archive, from the release's `sha256sums`.
    pub sha256: String,
}

/// One board.
#[derive(Debug, Clone, PartialEq, Eq, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub struct Board {
    /// The id: lower-case letters, digits and `-`.
    pub id: String,
    /// The name a person reads.
    pub title: String,
    /// The OpenWrt target, `<target>/<subtarget>`.
    pub target: String,
    /// The ImageBuilder profile.
    pub profile: String,
    /// The package architecture of the target.
    pub arch: String,
    /// The file of the ImageBuilder's output that becomes the base image (gzip).
    pub image: String,
    /// The partition table of that file.
    pub table: Table,
    /// `ROOTFS_PARTSIZE`, in MiB. Fixed for the life of the board: every partition after
    /// the root starts where this value puts it.
    pub rootfs_partsize_mb: u32,
    /// How the config region is added.
    pub config_part: ConfigPart,
    /// The device path of the config region on the board.
    pub config_dev: String,
    /// The device path of the data partition on the board.
    pub data_dev: String,
    /// What the board starts from.
    pub boot_from: BootFrom,
    /// The page lists the board.
    pub listed: bool,
    /// Why no image is built for the board with this release.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub unavailable: Option<String>,
    /// Packages of this board alone, as the ImageBuilder's `PACKAGES` takes them.
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub packages: Vec<String>,
    /// What the page tells about the board.
    pub notes: String,
}

/// `packaging/images/boards.json`.
#[derive(Debug, Clone, PartialEq, Eq, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub struct Boards {
    /// [`BOARDS_FORMAT`].
    pub format: String,
    /// The pinned OpenWrt release.
    pub openwrt: String,
    /// The image of the build container, by digest.
    pub container: String,
    /// One archive per target of the boards.
    pub imagebuilders: Vec<ImageBuilder>,
    /// Packages of every board: a name adds one, `-name` takes one of OpenWrt's default
    /// away.
    pub packages: Vec<String>,
    /// The boards.
    pub boards: Vec<Board>,
}

/// Why `boards.json` is refused.
#[derive(Debug, thiserror::Error)]
pub enum BoardsError {
    /// Not JSON, a field is missing, of another type or not known.
    #[error("{0}")]
    Json(#[from] serde_json::Error),
    /// The file is of another format (the text is the format it names).
    #[error("format `{0}`, this build reads `{BOARDS_FORMAT}`")]
    Format(String),
    /// A name that is not made of the characters its place allows.
    #[error("{what} `{name}` is refused: {rule}")]
    BadName {
        what: &'static str,
        name: String,
        rule: &'static str,
    },
    /// The build container is not named by digest.
    #[error("container `{0}` is not pinned: it is named as `<image>@sha256:<64 hex digits>`")]
    NotPinned(String),
    /// Two boards of this id, or two archives of this target.
    #[error("`{0}` is there twice")]
    Twice(String),
    /// A board whose target has no archive.
    #[error("board `{board}`: no ImageBuilder archive for target `{target}`")]
    NoArchive { board: String, target: String },
    /// An archive that is not the one OpenWrt publishes for the release and the target.
    #[error("the ImageBuilder archive of `{target}` is `{url}`; for this release it is `{want}`")]
    OtherArchive {
        target: String,
        url: String,
        want: String,
    },
    /// A SHA-256 that is not 64 lower-case hex digits.
    #[error("the SHA-256 of the archive of `{0}` is not 64 lower-case hex digits")]
    BadHash(String),
    /// A field of a board that cannot be right.
    #[error("board `{board}`: {why}")]
    Board { board: String, why: &'static str },
}

/// A name of lower-case letters, digits and the characters of `more`, not empty.
fn plain(name: &str, more: &[char]) -> bool {
    !name.is_empty()
        && name
            .chars()
            .all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || more.contains(&c))
}

/// A package of `PACKAGES`: a name, or `-name` for one that is taken away.
fn package(name: &str) -> bool {
    let name = name.strip_prefix('-').unwrap_or(name);
    !name.starts_with('-') && plain(name, &['-', '_', '.', '+'])
}

impl Boards {
    /// Reads and checks the list ([`Boards::check`]).
    pub fn parse(text: &str) -> Result<Self, BoardsError> {
        let boards: Self = serde_json::from_str(text)?;
        boards.check()?;
        Ok(boards)
    }

    /// Checks the list. Every name that reaches a command line, a path or a URL is made of
    /// a few plain characters; an archive is the one OpenWrt publishes for the pinned
    /// release; the container is named by digest; a board has a profile, an image of the
    /// pinned release, a root partition and device paths.
    pub fn check(&self) -> Result<(), BoardsError> {
        let bad = |what, name: &str, rule| BoardsError::BadName {
            what,
            name: name.to_owned(),
            rule,
        };
        if self.format != BOARDS_FORMAT {
            return Err(BoardsError::Format(self.format.clone()));
        }
        if !plain(&self.openwrt, &['.', '-']) {
            return Err(bad(
                "release",
                &self.openwrt,
                "lower-case letters, digits, `.` and `-`",
            ));
        }
        let pinned = self
            .container
            .rsplit_once("@sha256:")
            .is_some_and(|(image, digest)| {
                plain(image, &['.', '-', '_', '/', ':']) && hex::is_lower_hex(digest, 32)
            });
        if !pinned {
            return Err(BoardsError::NotPinned(self.container.clone()));
        }
        for (i, archive) in self.imagebuilders.iter().enumerate() {
            let target = &archive.target;
            if !target_name(target) {
                return Err(bad(
                    "target",
                    target,
                    "`<target>/<subtarget>` in plain characters",
                ));
            }
            if self
                .imagebuilders
                .iter()
                .take(i)
                .any(|a| a.target == *target)
            {
                return Err(BoardsError::Twice(target.clone()));
            }
            let want = archive_url(&self.openwrt, target);
            if archive.url != want {
                return Err(BoardsError::OtherArchive {
                    target: target.clone(),
                    url: archive.url.clone(),
                    want,
                });
            }
            if !hex::is_lower_hex(&archive.sha256, 32) {
                return Err(BoardsError::BadHash(target.clone()));
            }
        }
        for name in &self.packages {
            if !package(name) {
                return Err(bad("package", name, "a package name, or `-name`"));
            }
        }
        for (i, board) in self.boards.iter().enumerate() {
            if !plain(&board.id, &['-']) {
                return Err(bad(
                    "board",
                    &board.id,
                    "lower-case letters, digits and `-`",
                ));
            }
            if self.boards.iter().take(i).any(|b| b.id == board.id) {
                return Err(BoardsError::Twice(board.id.clone()));
            }
            self.check_board(board)?;
        }
        Ok(())
    }

    fn check_board(&self, board: &Board) -> Result<(), BoardsError> {
        let refuse = |why| BoardsError::Board {
            board: board.id.clone(),
            why,
        };
        if self.archive(&board.target).is_none() {
            return Err(BoardsError::NoArchive {
                board: board.id.clone(),
                target: board.target.clone(),
            });
        }
        if !plain(&board.profile, &['-', '_']) {
            return Err(refuse("the profile is not a plain name"));
        }
        if !plain(&board.arch, &['-', '_', '.']) {
            return Err(refuse("the package architecture is not a plain name"));
        }
        if board.title.trim().is_empty() {
            return Err(refuse("no title"));
        }
        // the file the ImageBuilder writes for this release, target and profile
        let prefix = format!(
            "openwrt-{}-{}-{}-",
            self.openwrt,
            board.target.replace('/', "-"),
            board.profile
        );
        let kind = board
            .image
            .strip_prefix(&prefix)
            .and_then(|rest| rest.strip_suffix(".img.gz"));
        if !kind.is_some_and(|kind| plain(kind, &['-', '_'])) {
            return Err(refuse(
                "the image is not `openwrt-<release>-<target>-<subtarget>-<profile>-<kind>.img.gz`",
            ));
        }
        if board.rootfs_partsize_mb == 0 {
            return Err(refuse("the root partition has no size"));
        }
        if part_number(&board.config_dev).is_none() || part_number(&board.data_dev).is_none() {
            return Err(refuse(
                "a device path is `/dev/<disk><number>` in plain characters",
            ));
        }
        if board.config_dev == board.data_dev {
            return Err(refuse(
                "the config region and the data partition are one device",
            ));
        }
        if board.packages.iter().any(|name| !package(name)) {
            return Err(refuse("a package is not a package name"));
        }
        if board
            .unavailable
            .as_deref()
            .is_some_and(|why| why.trim().is_empty())
        {
            return Err(refuse("`unavailable` says nothing"));
        }
        Ok(())
    }

    /// The board of an id.
    pub fn board(&self, id: &str) -> Option<&Board> {
        self.boards.iter().find(|board| board.id == id)
    }

    /// The archive of a target.
    pub fn archive(&self, target: &str) -> Option<&ImageBuilder> {
        self.imagebuilders.iter().find(|a| a.target == target)
    }

    /// `PACKAGES` of a board: the list of every board, then its own.
    fn packages(&self, board: &Board) -> String {
        self.packages
            .iter()
            .chain(&board.packages)
            .map(String::as_str)
            .collect::<Vec<_>>()
            .join(" ")
    }
}

/// `<target>/<subtarget>`, each a plain name.
fn target_name(target: &str) -> bool {
    target
        .split_once('/')
        .is_some_and(|(a, b)| plain(a, &['-', '_']) && plain(b, &['-', '_']))
}

/// Where OpenWrt publishes the ImageBuilder of a release and a target.
fn archive_url(openwrt: &str, target: &str) -> String {
    format!(
        "{DOWNLOADS}/{openwrt}/targets/{target}/openwrt-imagebuilder-{openwrt}-{}.Linux-x86_64.tar.zst",
        target.replace('/', "-")
    )
}

/// The partition number of a device path `/dev/<disk><number>`.
fn part_number(dev: &str) -> Option<u32> {
    let name = dev.strip_prefix("/dev/")?;
    if !plain(name, &[]) {
        return None;
    }
    // `mmcblk0p3`: the number is what follows the last letter
    let number = name.rsplit(|c: char| !c.is_ascii_digit()).next()?;
    if number.len() == name.len() {
        return None;
    }
    number.parse().ok().filter(|n| *n > 0)
}

/// The container runtime.
#[derive(Debug, Clone, Copy, PartialEq, Eq, ValueEnum)]
pub enum Runtime {
    Docker,
    Podman,
}

impl Runtime {
    fn program(self) -> &'static str {
        match self {
            Self::Docker => "docker",
            Self::Podman => "podman",
        }
    }
}

/// `wyr image base`.
#[derive(Args, Debug)]
pub struct BaseArgs {
    /// The board id, as `boards.json` names it.
    #[arg(long)]
    pub board: String,
    /// The broker's binary for the board: a static `aarch64-unknown-linux-musl` build.
    #[arg(long)]
    pub wyrmd: PathBuf,
    /// The version of that binary, for the index and `/etc/wyrm/image.json`.
    #[arg(long, value_name = "VERSION", default_value = env!("CARGO_PKG_VERSION"))]
    pub wyrmd_version: String,
    /// A directory with the link packages the image carries (`*.wyrm-link`, zip). They go
    /// to the seed directory of the image; which of them are installed is the person's
    /// `seed.json`. Without it the image carries none.
    #[arg(long)]
    pub seed_dir: Option<PathBuf>,
    /// Where the image, its gzip and `index.json` go. An `index.json` that is there keeps
    /// its other boards.
    #[arg(long)]
    pub out: PathBuf,
    /// The repository's `packaging` directory: `images/boards.json`, `images/build.sh`,
    /// `images/files` and `openwrt/wyrmd/files` are read from it.
    #[arg(long, default_value = "packaging")]
    pub packaging: PathBuf,
    /// Where ImageBuilder archives are kept between runs. Default: `<out>/.cache`.
    #[arg(long)]
    pub cache: Option<PathBuf>,
    /// The container runtime.
    #[arg(long, value_enum, default_value = "docker")]
    pub runtime: Runtime,
    /// Keep the work directory (`<out>/.work-<board>`: the staged files and the
    /// container's output).
    #[arg(long)]
    pub keep_work: bool,
}

/// Why `wyr image base` refused or failed.
#[derive(Debug, thiserror::Error)]
pub enum BaseError {
    /// A file could not be read or written (`what` says which step).
    #[error("{what} `{}`: {source}", path.display())]
    Io {
        what: &'static str,
        path: PathBuf,
        source: io::Error,
    },
    /// `boards.json` is refused.
    #[error("`{}`: {source}", path.display())]
    Boards { path: PathBuf, source: BoardsError },
    /// No board of this id.
    #[error("no board `{board}` in boards.json; it has: {known}")]
    NoBoard { board: String, known: String },
    /// The board has no image with the pinned release.
    #[error("board `{board}` is not built: {why}")]
    Unavailable { board: String, why: String },
    /// `--wyrmd` is not a binary for the boards.
    #[error("`{}` is not a binary for a board: it must be an ELF file for aarch64 (a static `aarch64-unknown-linux-musl` build)", .0.display())]
    NotForBoard(PathBuf),
    /// A version that is not a plain word.
    #[error("`{0}` is no version: letters, digits, `.`, `-` and `+`")]
    BadVersion(String),
    /// Something in a directory of files that is neither a file nor a directory, or a name
    /// that is not text.
    #[error("`{}` is neither a regular file nor a directory with a plain name: it does not go into an image", .0.display())]
    NotPlain(PathBuf),
    /// `seed.json` in `--seed-dir`: that file is the person's, written at the first boot.
    #[error("`{}`: the image carries packages only; `seed.json` comes with a person's configuration (`wyr image build --seed`)", .0.display())]
    SeedList(PathBuf),
    /// A path that cannot be given to the container runtime.
    #[error("`{}` cannot be mounted into the container: its path holds `:` or is not text", .0.display())]
    NoMount(PathBuf),
    /// The container runtime did not start.
    #[error("cannot run `{program}`: {source}")]
    Runtime {
        program: &'static str,
        source: io::Error,
    },
    /// The build in the container failed; its output says why.
    #[error("the build in the container failed ({0}); its output is above")]
    Build(std::process::ExitStatus),
    /// The image the ImageBuilder made cannot take the config partition.
    #[error("`{}`: {source}", path.display())]
    Part { path: PathBuf, source: PartError },
    /// The build left a result that is not published.
    #[error("the result of the build is refused: {0}")]
    Result(String),
    /// The image or the index is refused by the format.
    #[error(transparent)]
    Image(#[from] ImageError),
    /// `wyr image base` on a host without Unix file modes.
    #[cfg(not(unix))]
    #[error("`wyr image base` needs a Unix host: the files of an image carry Unix modes")]
    NoModes,
}

type Result<T, E = BaseError> = std::result::Result<T, E>;

fn io_err<'a>(what: &'static str, path: &'a Path) -> impl FnOnce(io::Error) -> BaseError + use<'a> {
    move |source| BaseError::Io {
        what,
        path: path.to_owned(),
        source,
    }
}

/// The arguments of `make image` for a board (the ImageBuilder). `FILES` and `BIN_DIR` are
/// paths inside the container and are added there (`build.sh`).
pub fn make_args(boards: &Boards, board: &Board) -> Vec<String> {
    vec![
        format!("PROFILE={}", board.profile),
        format!("PACKAGES={}", boards.packages(board)),
        format!("ROOTFS_PARTSIZE={}", board.rootfs_partsize_mb),
    ]
}

/// The directories of one build, as the container sees them mounted.
pub struct Mounts<'a> {
    /// ImageBuilder archives, read and written.
    pub cache: &'a Path,
    /// The files of the image, read only.
    pub overlay: &'a Path,
    /// What the build leaves.
    pub out: &'a Path,
    /// `build.sh`, read only.
    pub script: &'a Path,
}

/// The arguments of the container runtime for a build: the pinned image, the mounts, no
/// capability, and `build.sh` with the archive, the image to take and the arguments of
/// `make image`. The image's own entry point (it starts a build worker as root) is replaced
/// by the shell. `user` is `uid:gid` of whoever owns the output.
pub fn container_args(
    boards: &Boards,
    board: &Board,
    archive: &ImageBuilder,
    mounts: &Mounts<'_>,
    user: Option<&str>,
) -> Result<Vec<OsString>> {
    let mount = |path: &Path, at: &str, mode: &str| -> Result<OsString> {
        // the runtime splits `-v` at `:`
        match path.to_str() {
            Some(text) if !text.contains(':') && path.is_absolute() => {
                Ok(format!("{text}:{at}{mode}").into())
            }
            _ => Err(BaseError::NoMount(path.to_owned())),
        }
    };
    let mut args: Vec<OsString> = Vec::new();
    let mut push = |arg: &str| args.push(arg.into());
    push("run");
    push("--rm");
    push("--platform");
    push(BUILD_PLATFORM);
    // the build needs no capability and gains none
    push("--cap-drop");
    push("ALL");
    push("--security-opt");
    push("no-new-privileges");
    push("--entrypoint");
    push("sh");
    if let Some(user) = user {
        push("--user");
        push(user);
    }
    for volume in [
        mount(mounts.cache, "/cache", "")?,
        mount(mounts.overlay, "/work/overlay", ":ro")?,
        mount(mounts.out, "/work/out", "")?,
        mount(mounts.script, "/work/build.sh", ":ro")?,
    ] {
        args.push("-v".into());
        args.push(volume);
    }
    let mut push = |arg: &str| args.push(arg.into());
    push(&boards.container);
    push("/work/build.sh");
    push(&archive.url);
    push(&archive.sha256);
    push(&board.image);
    for arg in make_args(boards, board) {
        args.push(arg.into());
    }
    Ok(args)
}

/// `/etc/wyrm/image.json`: what is on a device (ADR 0051 §4, "Record").
#[derive(Debug, Serialize)]
struct ImageJson<'a> {
    format: &'a str,
    board: &'a str,
    openwrt: &'a str,
    wyrmd: &'a str,
    /// When the image was built, in seconds since 1970 (UTC).
    built: u64,
    config_dev: &'a str,
    data_dev: &'a str,
}

#[cfg(unix)]
mod modes {
    use std::fs::{File, Metadata, Permissions};
    use std::io;
    use std::os::unix::fs::{MetadataExt as _, PermissionsExt as _};
    use std::path::Path;

    /// 0755 for a file its owner may execute, 0644 for another: what a checkout keeps of
    /// a mode, and nothing else of it.
    pub fn of_file(from: &Metadata) -> u32 {
        if from.permissions().mode() & 0o100 == 0 {
            0o644
        } else {
            0o755
        }
    }

    pub fn set(file: &File, mode: u32) -> io::Result<()> {
        file.set_permissions(Permissions::from_mode(mode))
    }

    pub fn set_path(path: &Path, mode: u32) -> io::Result<()> {
        std::fs::set_permissions(path, Permissions::from_mode(mode))
    }

    /// `uid:gid` of the owner of a directory: the build writes there as that user.
    pub fn owner(dir: &Path) -> io::Result<String> {
        let meta = std::fs::metadata(dir)?;
        Ok(format!("{}:{}", meta.uid(), meta.gid()))
    }
}

/// Makes a directory of the image and what is above it, 0755.
#[cfg(unix)]
fn image_dir(path: &Path) -> Result<()> {
    std::fs::create_dir_all(path).map_err(io_err("create", path))?;
    modes::set_path(path, 0o755).map_err(io_err("set the mode of", path))
}

/// Copies one regular file into the image with `mode`.
#[cfg(unix)]
fn image_file(from: &Path, to: &Path, mode: u32) -> Result<()> {
    let mut input = File::open(from).map_err(io_err("read", from))?;
    let mut output = File::create(to).map_err(io_err("create", to))?;
    io::copy(&mut input, &mut output).map_err(io_err("write", to))?;
    modes::set(&output, mode).map_err(io_err("set the mode of", to))
}

/// Copies a tree of files into the image: directories and regular files only, by plain
/// names. A link, a device or a name that is not text is refused, not followed.
#[cfg(unix)]
fn image_tree(from: &Path, to: &Path) -> Result<()> {
    image_dir(to)?;
    let mut entries = std::fs::read_dir(from)
        .map_err(io_err("read", from))?
        .collect::<io::Result<Vec<_>>>()
        .map_err(io_err("read", from))?;
    entries.sort_by_key(std::fs::DirEntry::file_name);
    for entry in entries {
        let path = entry.path();
        // of the entry itself: a link is not followed
        let meta = std::fs::symlink_metadata(&path).map_err(io_err("read", &path))?;
        let name = entry.file_name();
        let plain = name
            .to_str()
            .is_some_and(|n| !n.contains(['\n', '\\']) && n != "." && n != "..");
        if !plain {
            return Err(BaseError::NotPlain(path));
        }
        let target = to.join(&name);
        if meta.is_dir() {
            image_tree(&path, &target)?;
        } else if meta.is_file() {
            image_file(&path, &target, modes::of_file(&meta))?;
        } else {
            return Err(BaseError::NotPlain(path));
        }
    }
    Ok(())
}

/// The path of the image where an absolute path of the device is staged.
fn staged(overlay: &Path, on_device: &str) -> PathBuf {
    overlay.join(on_device.trim_start_matches('/'))
}

/// The binary is an ELF file for a 64-bit little-endian ARM: the mistake this catches is
/// the host's own `wyrmd` in an image.
fn for_board(binary: &Path) -> Result<()> {
    let mut head = [0u8; 20];
    let mut file = File::open(binary).map_err(io_err("read", binary))?;
    let got = read_full(&mut file, &mut head).map_err(io_err("read", binary))?;
    // ELF magic, 64-bit, little-endian, and `e_machine` 183 (EM_AARCH64) at byte 18
    let right = got == head.len() && matches!(head, [0x7f, b'E', b'L', b'F', 2, 1, .., 183, 0]);
    if right {
        Ok(())
    } else {
        Err(BaseError::NotForBoard(binary.to_owned()))
    }
}

/// Stages the files of the image below `overlay`: the package `wyrmd` as files, the files
/// of `packaging/images/files`, the binary, the seed packages and `/etc/wyrm/image.json`.
#[cfg(unix)]
fn stage(
    args: &BaseArgs,
    boards: &Boards,
    board: &Board,
    overlay: &Path,
    built: u64,
) -> Result<()> {
    image_tree(&args.packaging.join("openwrt/wyrmd/files"), overlay)?;
    image_tree(&args.packaging.join("images/files"), overlay)?;

    let bin = staged(overlay, "/usr/bin");
    image_dir(&bin)?;
    image_file(&args.wyrmd, &bin.join("wyrmd"), 0o755)?;

    // the mount point of the data partition and the seed directory are there in every
    // image, as the package makes them
    image_dir(&staged(overlay, "/srv/wyrm"))?;
    let seed = staged(overlay, SEED_DIR);
    image_dir(&seed)?;
    if let Some(dir) = &args.seed_dir {
        let mut entries = std::fs::read_dir(dir)
            .map_err(io_err("read", dir))?
            .collect::<io::Result<Vec<_>>>()
            .map_err(io_err("read", dir))?;
        entries.sort_by_key(std::fs::DirEntry::file_name);
        for entry in entries {
            let path = entry.path();
            let meta = std::fs::symlink_metadata(&path).map_err(io_err("read", &path))?;
            let name = entry.file_name();
            if name == "seed.json" {
                return Err(BaseError::SeedList(path));
            }
            let plain = name.to_str().is_some_and(|n| !n.contains(['\n', '\\']));
            if !meta.is_file() || !plain {
                return Err(BaseError::NotPlain(path));
            }
            image_file(&path, &seed.join(&name), 0o644)?;
        }
    }

    let record = ImageJson {
        format: IMAGE_JSON_FORMAT,
        board: &board.id,
        openwrt: &boards.openwrt,
        wyrmd: &args.wyrmd_version,
        built,
        config_dev: &board.config_dev,
        data_dev: &board.data_dev,
    };
    let mut text = serde_json::to_string_pretty(&record)
        .map_err(|e| BaseError::Result(format!("image.json cannot be written: {e}")))?;
    text.push('\n');
    let etc = staged(overlay, "/etc/wyrm");
    image_dir(&etc)?;
    let path = etc.join("image.json");
    std::fs::write(&path, text).map_err(io_err("write", &path))?;
    modes::set_path(&path, 0o644).map_err(io_err("set the mode of", &path))
}

/// The size and the SHA-256 of a file that is published.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
struct FileSum {
    size: u64,
    sha256: [u8; 32],
}

/// The raw image as it is published and its gzip, written beside it: the sums of the two
/// files, the raw one first.
fn publish(raw: &Path, gz: &Path) -> Result<(FileSum, FileSum)> {
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
    let read = || io_err("read", raw);
    let write = || io_err("write", gz);
    let mut input = File::open(raw).map_err(read())?;
    let file = File::create(gz).map_err(write())?;
    let sum = Sum {
        to: io::BufWriter::new(file),
        hash: Sha256Stream::new(),
        size: 0,
    };
    // no name and no time in the header: the same image is the same file
    let mut encoder = flate2::GzBuilder::new()
        .mtime(0)
        .write(sum, flate2::Compression::best());
    let mut hash = Sha256Stream::new();
    let mut size = 0u64;
    let mut buf = vec![0u8; 1 << 20];
    loop {
        let n = read_full(&mut input, &mut buf).map_err(read())?;
        let Some(part) = buf.get(..n).filter(|part| !part.is_empty()) else {
            break;
        };
        hash.update(part);
        size = size.saturating_add(u64::try_from(n).unwrap_or(u64::MAX));
        encoder.write_all(part).map_err(write())?;
    }
    let mut sum = encoder.finish().map_err(write())?;
    sum.flush().map_err(write())?;
    let raw = FileSum {
        size,
        sha256: hash.finish(),
    };
    let gz = FileSum {
        size: sum.size,
        sha256: sum.hash.finish(),
    };
    Ok((raw, gz))
}

/// The config region of the image is the empty one, where the entry of the index will say,
/// and it is the partition the board's `config_dev` names.
fn check_result(raw: &Path, layout: &Appended, board: &Board) -> Result<()> {
    let refuse = |why: String| Err(BaseError::Result(why));
    if part_number(&board.config_dev) != Some(layout.config_part) {
        return refuse(format!(
            "the config region is partition {} of the image, and boards.json says `{}` for board `{}`",
            layout.config_part, board.config_dev, board.id
        ));
    }
    let Ok(len) = usize::try_from(CONFIG_SIZE) else {
        return Err(ImageError::TooLarge.into());
    };
    let read = || io_err("read", raw);
    let mut file = File::open(raw).map_err(read())?;
    let size = file.metadata().map_err(read())?.len();
    let inside = layout
        .config_offset
        .checked_add(CONFIG_SIZE)
        .is_some_and(|end| end <= size);
    if size != layout.size || !inside {
        return refuse(format!(
            "the image has {size} bytes; it was left with {} bytes and the config region at {}",
            layout.size, layout.config_offset
        ));
    }
    let mut region = vec![0u8; len];
    file.seek(SeekFrom::Start(layout.config_offset))
        .map_err(read())?;
    if read_full(&mut file, &mut region).map_err(read())? != len {
        return refuse("the config region cannot be read".to_owned());
    }
    // neither magic and a damaged region are errors of the format; a configuration in a
    // base image is one of the build
    if read_region(&region)?.is_some() {
        return refuse("the config region of a base image holds a configuration".to_owned());
    }
    Ok(())
}

/// The partitions of an image as text, for whoever looks at what was published.
fn partitions_text(layout: &Appended) -> String {
    let mut text = format!(
        "sector-size: {SECTOR}\nsize: {} bytes\nnumber start sectors type name\n",
        layout.size
    );
    for part in &layout.partitions {
        let line = format!(
            "{} {} {} {} {}",
            part.number, part.start, part.sectors, part.kind, part.name
        );
        text.push_str(line.trim_end());
        text.push('\n');
    }
    text
}

/// Writes the entry of the board into `index.json`, beside the entries of other boards
/// that are there.
fn write_index(path: &Path, entry: ImageEntry) -> Result<()> {
    let mut index = match std::fs::read_to_string(path) {
        Ok(text) => Index::parse(&text)?,
        Err(e) if e.kind() == io::ErrorKind::NotFound => Index {
            format: wyrm_image::FORMAT.to_owned(),
            images: Vec::new(),
        },
        Err(e) => return Err(io_err("read", path)(e)),
    };
    index.images.retain(|image| image.board != entry.board);
    index.images.push(entry);
    index.images.sort_by(|a, b| a.board.cmp(&b.board));
    index.check()?;
    let mut text = serde_json::to_string_pretty(&index)
        .map_err(|e| BaseError::Result(format!("the index cannot be written: {e}")))?;
    text.push('\n');
    // beside its place, then one rename: a reader never meets half an index
    let tmp = path.with_extension(format!("json.{}.tmp", std::process::id()));
    std::fs::write(&tmp, text).map_err(io_err("write", &tmp))?;
    std::fs::rename(&tmp, path).map_err(io_err("write", path))
}

/// A version as a part of a file name.
fn version_ok(version: &str) -> bool {
    !version.is_empty()
        && version
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || ['.', '-', '+'].contains(&c))
}

#[cfg(not(unix))]
pub fn run(_args: &BaseArgs) -> Result<()> {
    Err(BaseError::NoModes)
}

#[cfg(unix)]
pub fn run(args: &BaseArgs) -> Result<()> {
    let list = args.packaging.join("images/boards.json");
    let text = std::fs::read_to_string(&list).map_err(io_err("read", &list))?;
    let boards = Boards::parse(&text).map_err(|source| BaseError::Boards {
        path: list.clone(),
        source,
    })?;
    let Some(board) = boards.board(&args.board) else {
        return Err(BaseError::NoBoard {
            board: args.board.clone(),
            known: boards
                .boards
                .iter()
                .map(|board| board.id.as_str())
                .collect::<Vec<_>>()
                .join(", "),
        });
    };
    if let Some(why) = &board.unavailable {
        return Err(BaseError::Unavailable {
            board: board.id.clone(),
            why: why.clone(),
        });
    }
    // checked by `Boards::check`: every board has the archive of its target
    let Some(archive) = boards.archive(&board.target) else {
        return Err(BaseError::Boards {
            path: list,
            source: BoardsError::NoArchive {
                board: board.id.clone(),
                target: board.target.clone(),
            },
        });
    };
    if !version_ok(&args.wyrmd_version) {
        return Err(BaseError::BadVersion(args.wyrmd_version.clone()));
    }
    for_board(&args.wyrmd)?;

    std::fs::create_dir_all(&args.out).map_err(io_err("create", &args.out))?;
    let out = args.out.canonicalize().map_err(io_err("find", &args.out))?;
    let cache = args.cache.clone().unwrap_or_else(|| out.join(".cache"));
    std::fs::create_dir_all(&cache).map_err(io_err("create", &cache))?;
    let cache = cache.canonicalize().map_err(io_err("find", &cache))?;
    let work = out.join(format!(".work-{}", board.id));
    match std::fs::remove_dir_all(&work) {
        Err(e) if e.kind() != io::ErrorKind::NotFound => {
            return Err(io_err("remove", &work)(e));
        }
        _ => {}
    }
    let overlay = work.join("overlay");
    let result = work.join("out");
    std::fs::create_dir_all(&result).map_err(io_err("create", &result))?;
    stage(args, &boards, board, &overlay, wyrm_core::clock::now_s())?;
    let script_from = args.packaging.join("images/build.sh");
    let script = work.join("build.sh");
    std::fs::copy(&script_from, &script).map_err(io_err("read", &script_from))?;

    let user = modes::owner(&out).map_err(io_err("read", &out))?;
    let mounts = Mounts {
        cache: &cache,
        overlay: &overlay,
        out: &result,
        script: &script,
    };
    let container = container_args(&boards, board, archive, &mounts, Some(&user))?;
    let program = args.runtime.program();
    out!(
        "building board {} with OpenWrt {} in {}",
        board.id,
        boards.openwrt,
        boards.container
    );
    let status = Command::new(program)
        .args(&container)
        .status()
        .map_err(|source| BaseError::Runtime { program, source })?;
    if !status.success() {
        return Err(BaseError::Build(status));
    }

    let made = result.join("base.img");
    let mut image = File::options()
        .read(true)
        .write(true)
        .open(&made)
        .map_err(io_err("read", &made))?;
    let layout =
        append_config(&mut image, board.table == Table::Gpt).map_err(|source| BaseError::Part {
            path: made.clone(),
            source,
        })?;
    drop(image);
    check_result(&made, &layout, board)?;

    let stem = format!(
        "wyrm-{}-{}-openwrt-{}",
        board.id, args.wyrmd_version, boards.openwrt
    );
    let raw_name = format!("{stem}.img");
    let gz_name = format!("{raw_name}.gz");
    let raw = out.join(&raw_name);
    let gz = out.join(&gz_name);
    std::fs::rename(&made, &raw).map_err(io_err("write", &raw))?;
    let (raw_sum, gz_sum) = publish(&raw, &gz)?;
    let manifest = out.join(format!("{stem}.manifest"));
    std::fs::rename(result.join("manifest"), &manifest).map_err(io_err("write", &manifest))?;
    let listing = out.join(format!("{stem}.partitions.txt"));
    std::fs::write(&listing, partitions_text(&layout)).map_err(io_err("write", &listing))?;
    let entry = ImageEntry {
        board: board.id.clone(),
        file: raw_name,
        size: raw_sum.size,
        sha256: hex::encode(raw_sum.sha256),
        config_offset: layout.config_offset,
        openwrt: boards.openwrt.clone(),
        wyrmd: args.wyrmd_version.clone(),
        download: Some(Download {
            file: gz_name,
            size: gz_sum.size,
            sha256: hex::encode(gz_sum.sha256),
        }),
    };
    let index = out.join("index.json");
    write_index(&index, entry)?;
    if !args.keep_work {
        std::fs::remove_dir_all(&work).map_err(io_err("remove", &work))?;
    }

    out!("{}", raw.display());
    out!("{}", gz.display());
    out!("{}", index.display());
    out!(
        "config region: partition {} ({}), {} bytes at byte {}",
        layout.config_part,
        board.config_dev,
        CONFIG_SIZE,
        layout.config_offset
    );
    out!(
        "root partition: {} MiB. This size is fixed for board {}: a later image with another \
         size moves every partition after the root, and the data of a device is lost when \
         that image is written over it",
        board.rootfs_partsize_mb,
        board.id
    );
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    const BOARDS_JSON: &str = include_str!("../../../packaging/images/boards.json");

    fn boards() -> Boards {
        Boards::parse(BOARDS_JSON).unwrap()
    }

    #[test]
    fn the_command_line_is_built_right() {
        let boards = boards();
        let board = boards.board("rpi4").unwrap();
        let archive = boards.archive(&board.target).unwrap();
        assert_eq!(
            make_args(&boards, board),
            [
                "PROFILE=rpi-4",
                "PACKAGES=-dnsmasq -odhcpd-ipv6only -ppp -ppp-mod-pppoe zoneinfo-all \
                 kmod-usb-acm kmod-usb-serial-ch341 kmod-usb-serial-cp210x \
                 kmod-usb-serial-ftdi kmod-usb-serial-pl2303",
                "ROOTFS_PARTSIZE=256",
            ]
        );
        let mounts = Mounts {
            cache: Path::new("/b/cache"),
            overlay: Path::new("/b/work/overlay"),
            out: Path::new("/b/work/out"),
            script: Path::new("/b/work/build.sh"),
        };
        let args = container_args(&boards, board, archive, &mounts, Some("501:20")).unwrap();
        let args: Vec<&str> = args.iter().map(|a| a.to_str().unwrap()).collect();
        let at = args.iter().position(|a| *a == "/work/build.sh").unwrap();
        let (runtime, build) = args.split_at(at);
        assert_eq!(
            runtime,
            [
                "run",
                "--rm",
                "--platform",
                "linux/amd64",
                "--cap-drop",
                "ALL",
                "--security-opt",
                "no-new-privileges",
                "--entrypoint",
                "sh",
                "--user",
                "501:20",
                "-v",
                "/b/cache:/cache",
                "-v",
                "/b/work/overlay:/work/overlay:ro",
                "-v",
                "/b/work/out:/work/out",
                "-v",
                "/b/work/build.sh:/work/build.sh:ro",
                boards.container.as_str(),
            ]
        );
        // the container is named by digest, never by a tag alone
        let (_, digest) = boards.container.rsplit_once("@sha256:").unwrap();
        assert!(hex::is_lower_hex(digest, 32));
        assert_eq!(
            build.get(..4).unwrap(),
            [
                "/work/build.sh",
                "https://downloads.openwrt.org/releases/25.12.6/targets/bcm27xx/bcm2711/\
                 openwrt-imagebuilder-25.12.6-bcm27xx-bcm2711.Linux-x86_64.tar.zst",
                "78191c1909358925bd92fc2200da29c1e4a0a8a949a4af77bd97650471604d2a",
                "openwrt-25.12.6-bcm27xx-bcm2711-rpi-4-squashfs-factory.img.gz",
            ]
        );
        assert_eq!(build.get(4..).unwrap(), make_args(&boards, board));
        // no privilege and no device is asked of the runtime
        for refused in ["--privileged", "--device", "--cap-add", "--network"] {
            assert!(!args.contains(&refused), "{refused}");
        }
    }

    #[test]
    fn a_path_the_runtime_would_split_is_refused() {
        let boards = boards();
        let board = boards.board("rpi4").unwrap();
        let archive = boards.archive(&board.target).unwrap();
        for bad in ["/b/ca:che", "relative/cache"] {
            let mounts = Mounts {
                cache: Path::new(bad),
                overlay: Path::new("/b/overlay"),
                out: Path::new("/b/out"),
                script: Path::new("/b/build.sh"),
            };
            assert!(matches!(
                container_args(&boards, board, archive, &mounts, None),
                Err(BaseError::NoMount(_))
            ));
        }
    }

    #[test]
    fn the_boards_of_the_repository_are_read() {
        let boards = boards();
        let ids: Vec<&str> = boards.boards.iter().map(|b| b.id.as_str()).collect();
        assert_eq!(ids, ["rpi4", "rpi5", "bpi-r4", "bpi-r4-8g", "qemu-armsr"]);
        // the board of the tests is never on the page
        assert!(!boards.board("qemu-armsr").unwrap().listed);
        // MBR on the Raspberry Pi, GPT on the others; the config region is the partition
        // after the root
        assert_eq!(boards.board("rpi4").unwrap().table, Table::Mbr);
        assert_eq!(boards.board("bpi-r4").unwrap().table, Table::Gpt);
        assert_eq!(part_number("/dev/mmcblk0p3"), Some(3));
        assert_eq!(part_number("/dev/vda3"), Some(3));
        assert_eq!(part_number("/dev/sda12"), Some(12));
        for bad in [
            "/dev/vda",
            "/dev/3",
            "vda3",
            "/dev/vd a3",
            "/dev/../vda3",
            "/dev/vda0",
        ] {
            assert_eq!(part_number(bad), None, "{bad}");
        }
    }

    /// One change of the repository's list, as JSON.
    fn changed(change: impl FnOnce(&mut serde_json::Value)) -> Result<Boards, BoardsError> {
        let mut json: serde_json::Value = serde_json::from_str(BOARDS_JSON).unwrap();
        change(&mut json);
        Boards::parse(&json.to_string())
    }

    #[test]
    fn a_list_that_cannot_be_right_is_refused() {
        assert!(changed(|_| ()).is_ok());
        assert!(matches!(
            changed(|j| j["format"] = "wyrm-boards/2".into()),
            Err(BoardsError::Format(_))
        ));
        // a tag is no pin
        for container in ["ghcr.io/openwrt/imagebuilder:latest", "debian@sha256:abc"] {
            assert!(matches!(
                changed(|j| j["container"] = container.into()),
                Err(BoardsError::NotPinned(_))
            ));
        }
        // an archive from elsewhere, or of another release
        assert!(matches!(
            changed(|j| j["imagebuilders"][0]["url"] =
                "https://example.org/openwrt-imagebuilder.tar.zst".into()),
            Err(BoardsError::OtherArchive { .. })
        ));
        assert!(matches!(
            changed(|j| j["openwrt"] = "25.12.5".into()),
            Err(BoardsError::OtherArchive { .. })
        ));
        assert!(matches!(
            changed(|j| j["imagebuilders"][0]["sha256"] = "78191C".into()),
            Err(BoardsError::BadHash(_))
        ));
        assert!(matches!(
            changed(|j| j["boards"][1]["id"] = "rpi4".into()),
            Err(BoardsError::Twice(_))
        ));
        assert!(matches!(
            changed(|j| j["boards"][0]["target"] = "x86/64".into()),
            Err(BoardsError::NoArchive { .. })
        ));
        // what would reach the command line of `make` as more than one word
        for (field, value) in [
            ("profile", "rpi-4 FILES=/"),
            ("image", "../x.img.gz"),
            ("config_dev", "/dev/mmcblk0p3; reboot"),
            ("data_dev", "/dev/mmcblk0p3"),
        ] {
            assert!(
                matches!(
                    changed(|j| j["boards"][0][field] = value.into()),
                    Err(BoardsError::Board { .. })
                ),
                "{field}"
            );
        }
        assert!(matches!(
            changed(|j| j["boards"][0]["rootfs_partsize_mb"] = 0.into()),
            Err(BoardsError::Board { .. })
        ));
        assert!(matches!(
            changed(|j| j["packages"][0] = "luci $(reboot)".into()),
            Err(BoardsError::BadName { .. })
        ));
        assert!(matches!(
            changed(|j| j["boards"][0]["id"] = "Rpi 4".into()),
            Err(BoardsError::BadName { .. })
        ));
        // a field this build does not know is a mistake in the list
        assert!(matches!(
            changed(|j| j["boards"][0]["rootfs_partsize"] = 512.into()),
            Err(BoardsError::Json(_))
        ));
    }

    #[test]
    fn only_a_binary_for_arm64_goes_into_an_image() {
        let dir = std::env::temp_dir().join(format!("wyr-image-base-elf-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let path = dir.join("wyrmd");
        let mut elf = vec![0u8; 64];
        elf[..6].copy_from_slice(&[0x7f, b'E', b'L', b'F', 2, 1]);
        elf[18] = 183;
        std::fs::write(&path, &elf).unwrap();
        assert!(for_board(&path).is_ok());
        // x86-64, a script, a short file
        elf[18] = 62;
        std::fs::write(&path, &elf).unwrap();
        assert!(matches!(for_board(&path), Err(BaseError::NotForBoard(_))));
        std::fs::write(&path, "#!/bin/sh\nexec true\n").unwrap();
        assert!(matches!(for_board(&path), Err(BaseError::NotForBoard(_))));
        std::fs::write(&path, [0x7f, b'E']).unwrap();
        assert!(matches!(for_board(&path), Err(BaseError::NotForBoard(_))));
        std::fs::remove_dir_all(&dir).unwrap();
    }

    #[cfg(unix)]
    #[test]
    fn the_files_of_an_image_are_staged_with_their_modes() {
        use std::os::unix::fs::PermissionsExt as _;
        let dir = std::env::temp_dir().join(format!("wyr-image-base-stage-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        let seeds = dir.join("seeds");
        std::fs::create_dir_all(&seeds).unwrap();
        std::fs::write(seeds.join("telegram.wyrm-link"), b"zip").unwrap();
        let wyrmd = dir.join("wyrmd");
        std::fs::write(&wyrmd, b"binary").unwrap();
        let packaging = Path::new(env!("CARGO_MANIFEST_DIR")).join("../../packaging");
        let args = BaseArgs {
            board: "qemu-armsr".to_owned(),
            wyrmd,
            wyrmd_version: "0.9.0".to_owned(),
            seed_dir: Some(seeds.clone()),
            out: dir.join("out"),
            packaging,
            cache: None,
            runtime: Runtime::Docker,
            keep_work: false,
        };
        let boards = boards();
        let board = boards.board("qemu-armsr").unwrap();
        let overlay = dir.join("overlay");
        stage(&args, &boards, board, &overlay, 1_795_000_000).unwrap();
        let mode = |path: &str| {
            std::fs::metadata(overlay.join(path))
                .unwrap_or_else(|e| panic!("{path}: {e}"))
                .permissions()
                .mode()
                & 0o7777
        };
        // the package's files, the image's own, the binary and the seed packages
        assert_eq!(mode("usr/bin/wyrmd"), 0o755);
        assert_eq!(mode("etc/init.d/wyrmd"), 0o755);
        assert_eq!(mode("usr/libexec/wyrm/first-boot.sh"), 0o755);
        assert_eq!(mode("etc/uci-defaults/80-wyrm-user"), 0o755);
        assert_eq!(mode("etc/uci-defaults/90-wyrm-host"), 0o755);
        assert_eq!(mode("etc/wyrm/wyrmd.json5"), 0o644);
        assert_eq!(mode("usr/share/wyrm/seed/telegram.wyrm-link"), 0o644);
        assert_eq!(mode("srv/wyrm"), 0o755);
        let record: serde_json::Value = serde_json::from_str(
            &std::fs::read_to_string(overlay.join("etc/wyrm/image.json")).unwrap(),
        )
        .unwrap();
        assert_eq!(
            record,
            serde_json::json!({
                "format": "wyrm-image/1",
                "board": "qemu-armsr",
                "openwrt": "25.12.6",
                "wyrmd": "0.9.0",
                "built": 1_795_000_000u64,
                "config_dev": "/dev/vda3",
                "data_dev": "/dev/vda4",
            })
        );
        // the list of what is installed is the person's, never the image's
        std::fs::write(seeds.join("seed.json"), "{}").unwrap();
        let again = dir.join("overlay2");
        assert!(matches!(
            stage(&args, &boards, board, &again, 0),
            Err(BaseError::SeedList(_))
        ));
        std::fs::remove_file(seeds.join("seed.json")).unwrap();
        // a link in a directory of files is refused, not followed
        std::os::unix::fs::symlink("/etc/passwd", seeds.join("passwd")).unwrap();
        let again = dir.join("overlay3");
        assert!(matches!(
            stage(&args, &boards, board, &again, 0),
            Err(BaseError::NotPlain(_))
        ));
        std::fs::remove_dir_all(&dir).unwrap();
    }

    #[test]
    fn the_published_gzip_is_the_image() {
        let dir = std::env::temp_dir().join(format!("wyr-image-base-gz-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        let image: Vec<u8> = (0..3_000_000usize)
            .map(|i| u8::try_from(i % 7).unwrap())
            .collect();
        let raw = dir.join("base.img");
        let gz = dir.join("base.img.gz");
        std::fs::write(&raw, &image).unwrap();
        let (raw_sum, gz_sum) = publish(&raw, &gz).unwrap();
        assert_eq!(raw_sum.size, 3_000_000);
        assert_eq!(raw_sum.sha256, hex::sha256(&image));
        let packed = std::fs::read(&gz).unwrap();
        assert_eq!(gz_sum.size, u64::try_from(packed.len()).unwrap());
        assert_eq!(gz_sum.sha256, hex::sha256(&packed));
        let mut unpacked = Vec::new();
        io::Read::read_to_end(
            &mut flate2::read::GzDecoder::new(packed.as_slice()),
            &mut unpacked,
        )
        .unwrap();
        assert_eq!(unpacked, image);
        // the same image is the same file
        let again = dir.join("again.img.gz");
        publish(&raw, &again).unwrap();
        assert_eq!(std::fs::read(&again).unwrap(), packed);
        std::fs::remove_dir_all(&dir).unwrap();
    }

    #[test]
    fn a_result_of_the_container_is_checked() {
        let dir = std::env::temp_dir().join(format!("wyr-image-base-res-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        let boards = boards();
        let board = boards.board("qemu-armsr").unwrap();
        let region = usize::try_from(CONFIG_SIZE).unwrap();
        let offset = 1 << 20;
        let mut image = vec![7u8; offset + region + (1 << 20)];
        image[offset..offset + region].fill(0);
        image[offset..offset + 8].copy_from_slice(wyrm_image::MAGIC_EMPTY);
        let raw = dir.join("base.img");
        std::fs::write(&raw, &image).unwrap();
        let size = u64::try_from(image.len()).unwrap();
        let layout = Appended {
            config_offset: u64::try_from(offset).unwrap(),
            config_part: 3,
            size,
            partitions: Vec::new(),
        };
        check_result(&raw, &layout, board).unwrap();
        // another partition than `config_dev` names
        let other = Appended {
            config_part: 4,
            ..layout.clone()
        };
        assert!(matches!(
            check_result(&raw, &other, board),
            Err(BaseError::Result(_))
        ));
        // a wrong offset: no magic there
        let other = Appended {
            config_offset: 512,
            ..layout.clone()
        };
        assert!(matches!(
            check_result(&raw, &other, board),
            Err(BaseError::Image(ImageError::NoRegion))
        ));
        // a region that runs past the image, a size that is not the file's
        for other in [
            Appended {
                config_offset: size - 4096,
                ..layout.clone()
            },
            Appended {
                size: size + 1,
                ..layout.clone()
            },
        ] {
            assert!(matches!(
                check_result(&raw, &other, board),
                Err(BaseError::Result(_))
            ));
        }
        // bytes after the magic: not an empty region
        image[offset + 100] = 1;
        std::fs::write(&raw, &image).unwrap();
        assert!(matches!(
            check_result(&raw, &layout, board),
            Err(BaseError::Image(ImageError::Damaged))
        ));
        std::fs::remove_dir_all(&dir).unwrap();
    }

    #[test]
    fn the_index_keeps_its_other_boards() {
        let dir = std::env::temp_dir().join(format!("wyr-image-base-idx-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        let path = dir.join("index.json");
        let entry = |board: &str, size: u64| ImageEntry {
            board: board.to_owned(),
            file: format!("wyrm-{board}.img"),
            size,
            sha256: "ab".repeat(32),
            config_offset: 1 << 20,
            openwrt: "25.12.6".to_owned(),
            wyrmd: "0.9.0".to_owned(),
            download: None,
        };
        write_index(&path, entry("rpi4", 64 << 20)).unwrap();
        write_index(&path, entry("qemu-armsr", 64 << 20)).unwrap();
        write_index(&path, entry("rpi4", 128 << 20)).unwrap();
        let index = Index::parse(&std::fs::read_to_string(&path).unwrap()).unwrap();
        let boards: Vec<(&str, u64)> = index
            .images
            .iter()
            .map(|image| (image.board.as_str(), image.size))
            .collect();
        assert_eq!(boards, [("qemu-armsr", 64 << 20), ("rpi4", 128 << 20)]);
        // an entry the format refuses is not written, and the index stays as it was
        assert!(write_index(&path, entry("rpi5", 1)).is_err());
        assert!(Index::parse(&std::fs::read_to_string(&path).unwrap())
            .unwrap()
            .image("rpi5")
            .is_none());
        std::fs::remove_dir_all(&dir).unwrap();
    }
}
