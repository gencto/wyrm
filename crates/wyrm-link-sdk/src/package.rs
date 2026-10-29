//! Link packages (ADR 0011, 0021): the `wyrm-link.json` manifest, the
//! repository index and a reproducible zip writer. One format for the
//! broker, which installs packages, and for `wyr`, which builds them.

use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::collections::{BTreeMap, HashSet};
use std::io::{Cursor, Read, Write};

/// The manifest at the root of a package zip.
pub const MANIFEST: &str = "wyrm-link.json";
/// Largest package zip.
pub const MAX_ZIP: usize = 64 << 20;
/// Largest repository index.
pub const MAX_INDEX: usize = 4 << 20;
/// Most packages in one index.
pub const MAX_INDEX_ENTRIES: usize = 1000;
const MAX_MANIFEST: u64 = 1 << 20;

/// `wyrm-link.json`. Unknown fields are refused, so a typo does not pass.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Manifest {
    pub name: String,
    pub version: String,
    #[serde(default, skip_serializing_if = "String::is_empty")]
    pub description: String,
    /// [`crate::LINK_PROTOCOL`] the package was built for.
    pub wyrm_link: u32,
    /// `process` or `wasm`.
    pub kind: String,
    /// `process`: the executable per host (`<os>-<arch>`, see [`platform`]).
    #[serde(default, skip_serializing_if = "BTreeMap::is_empty")]
    pub entries: BTreeMap<String, String>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub args: Vec<String>,
    /// `wasm`: the component file.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub entry: Option<String>,
    /// Grants the link needs as a requester (ADR 0013).
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub requester: Vec<Grant>,
    /// `wasm`: the component's world, `app` (`wyrm:app`, ADR 0023), `driver` or `point`.
    /// Informational: the broker reads the world from the component and refuses a package
    /// whose `world` says otherwise.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub world: Option<String>,
    /// A portable app (`wasm` app component or `process`): what its link may use, granted at
    /// install as link params (ADR 0023).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub capabilities: Option<Capabilities>,
}

/// Default store of an app link, MiB (ADR 0023).
pub const DEFAULT_STORE_MB: u32 = 1;
/// Largest store of an app link, MiB.
pub const MAX_STORE_MB: u32 = 64;
/// Default linear memory of an app instance, MiB.
pub const DEFAULT_MEMORY_MB: u32 = 64;
/// Largest linear memory of an app instance, MiB.
pub const MAX_MEMORY_MB: u32 = 512;
/// Default time of one app call, ms.
pub const DEFAULT_CALL_MS: u32 = 2000;
/// Longest time of one app call, ms.
pub const MAX_CALL_MS: u32 = 10_000;
/// Worlds a `wasm` package may name.
pub const WORLDS: [&str; 3] = ["app", "driver", "point"];

/// What an app link may use (ADR 0023 "Capabilities, granted at install"); absent fields take
/// the defaults. `requester` grants stay [`Manifest::requester`].
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Capabilities {
    /// TCP allowlist entries, `<ip>[/<prefix>]:<port>` (ADR 0012); none: no network.
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub net: Vec<String>,
    /// Store size, MiB (default 1, at most 64; 0 refuses every write).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub store_mb: Option<u32>,
    /// Linear memory of an instance, MiB (default 64, 1 to 512).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub memory_mb: Option<u32>,
    /// Time of one call, ms (default 2000, 1 to 10000).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub call_ms: Option<u32>,
}

impl Capabilities {
    /// The bounds of each field, as `Err` naming the field.
    pub fn check(&self) -> Result<(), String> {
        for e in &self.net {
            if e.is_empty() || e.contains([',', ' ', '\n', '\r', '\t']) || !e.contains(':') {
                return Err(format!(
                    "capabilities.net {e:?}: one <ip>[/<prefix>]:<port> entry"
                ));
            }
        }
        let bound = |name: &str, v: Option<u32>, min: u32, max: u32| match v {
            Some(n) if n < min || n > max => {
                Err(format!("capabilities.{name} {n}: from {min} to {max}"))
            }
            _ => Ok(()),
        };
        bound("store_mb", self.store_mb, 0, MAX_STORE_MB)?;
        bound("memory_mb", self.memory_mb, 1, MAX_MEMORY_MB)?;
        bound("call_ms", self.call_ms, 1, MAX_CALL_MS)
    }

    /// The store size in MiB, the default when unset.
    pub fn store_mb(&self) -> u32 {
        self.store_mb.unwrap_or(DEFAULT_STORE_MB)
    }

    /// The memory of an instance in MiB, the default when unset.
    pub fn memory_mb(&self) -> u32 {
        self.memory_mb.unwrap_or(DEFAULT_MEMORY_MB)
    }

    /// The time of one call in ms, the default when unset.
    pub fn call_ms(&self) -> u32 {
        self.call_ms.unwrap_or(DEFAULT_CALL_MS)
    }

    /// One line for an install result: `net none, store 1 MiB, memory 64 MiB, call 2000 ms`.
    pub fn describe(&self) -> String {
        let net = if self.net.is_empty() {
            "none".to_owned()
        } else {
            self.net.join(" ")
        };
        format!(
            "net {net}, store {} MiB, memory {} MiB, call {} ms",
            self.store_mb(),
            self.memory_mb(),
            self.call_ms()
        )
    }
}

/// A requested grant: `{"path": "wy/{site}/downstream/mock", "level": "read"}`.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Grant {
    pub path: String,
    pub level: String,
}

impl Manifest {
    /// What every package must hold, wherever it is checked: a valid name
    /// and version, this link protocol, and an entry for its kind.
    pub fn check(&self) -> Result<(), String> {
        valid_name(&self.name).map_err(|e| format!("name: {e}"))?;
        if !valid_version(&self.version) {
            return Err(format!(
                "version {:?}: 1-32 of [A-Za-z0-9._+-]",
                self.version
            ));
        }
        if self.wyrm_link != crate::LINK_PROTOCOL {
            return Err(format!(
                "built for link protocol {}, this broker speaks {}",
                self.wyrm_link,
                crate::LINK_PROTOCOL
            ));
        }
        match self.kind.as_str() {
            "process" if self.entries.is_empty() => {
                return Err("a process package needs `entries`".into())
            }
            "wasm" if self.entry.is_none() => return Err("a wasm package needs `entry`".into()),
            "process" | "wasm" => {}
            k => return Err(format!("kind {k:?}: process or wasm")),
        }
        if let Some(w) = &self.world {
            if self.kind != "wasm" {
                return Err("world: only a wasm package has one".into());
            }
            if !WORLDS.contains(&w.as_str()) {
                return Err(format!("world {w:?}: app, driver or point"));
            }
        }
        // a process package may carry them too: a portable app run as a process takes the
        // same params as its WASM twin (ADR 0023, one source for all modes)
        if let Some(c) = &self.capabilities {
            if let Some(w) = self.world.as_deref().filter(|w| *w != "app") {
                return Err(format!(
                    "capabilities: only an app component has them, world is {w:?}"
                ));
            }
            c.check()?;
        }
        Ok(())
    }
}

/// A package name: a key segment that cannot start with `.`.
pub fn valid_name(name: &str) -> Result<(), String> {
    wyrm_core::keyspace::validate_segment(name).map_err(|e| e.to_string())?;
    if name.starts_with('.') {
        return Err(format!("{name:?} may not start with '.'"));
    }
    Ok(())
}

/// 1–32 of `A–Z a–z 0–9 . _ - +`, not starting with `.`.
pub fn valid_version(v: &str) -> bool {
    !v.is_empty()
        && v.len() <= 32
        && !v.starts_with('.')
        && v.bytes()
            .all(|b| b.is_ascii_alphanumeric() || matches!(b, b'.' | b'_' | b'-' | b'+'))
}

/// This host as a manifest and index key: `<os>-<arch>` (`linux-aarch64`,
/// `macos-aarch64`, `linux-x86_64`).
pub fn platform() -> String {
    format!("{}-{}", std::env::consts::OS, std::env::consts::ARCH)
}

/// The host key of a Rust target triple, for the hosts a broker runs on.
pub fn host_of_triple(triple: &str) -> Option<&'static str> {
    let arch = match triple.split('-').next()? {
        "x86_64" => "x86_64",
        "aarch64" => "aarch64",
        _ => return None,
    };
    let os = if triple.contains("-apple-darwin") {
        "macos"
    } else if triple.contains("-linux-") {
        "linux"
    } else {
        return None;
    };
    Some(match (os, arch) {
        ("macos", "x86_64") => "macos-x86_64",
        ("macos", _) => "macos-aarch64",
        ("linux", "x86_64") => "linux-x86_64",
        _ => "linux-aarch64",
    })
}

/// Lower-case hex SHA-256.
pub fn sha256_hex(bytes: &[u8]) -> String {
    hex::encode(Sha256::digest(bytes))
}

fn is_sha256(s: &str) -> bool {
    s.len() == 64 && s.bytes().all(|b| b.is_ascii_hexdigit())
}

/// One package of a repository index (`packages.repository`, as DSA's
/// `linkRepositoryUrl`). A process package has a file per host in
/// `assets`; one that runs anywhere (WASM) has `url` and `sha256`.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct RepoEntry {
    pub name: String,
    pub version: String,
    #[serde(default, skip_serializing_if = "String::is_empty")]
    pub description: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub url: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub sha256: Option<String>,
    #[serde(default, skip_serializing_if = "BTreeMap::is_empty")]
    pub assets: BTreeMap<String, Asset>,
}

/// One file of a package: where it is and its SHA-256.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Asset {
    pub url: String,
    pub sha256: String,
}

impl RepoEntry {
    /// The file for `host`: its own asset, else the entry's `url`.
    pub fn asset(&self, host: &str) -> Option<Asset> {
        if let Some(a) = self.assets.get(host) {
            return Some(a.clone());
        }
        Some(Asset {
            url: self.url.clone()?,
            sha256: self.sha256.clone()?,
        })
    }
}

/// Parse and check a repository index: at most [`MAX_INDEX_ENTRIES`]
/// packages, unique valid names, a valid version, and for each a file
/// (`assets`, or `url` with `sha256`) with a 64-hex SHA-256.
pub fn parse_index(bytes: &[u8]) -> Result<Vec<RepoEntry>, String> {
    let list: Vec<RepoEntry> = serde_json::from_slice(bytes).map_err(|e| format!("index: {e}"))?;
    if list.len() > MAX_INDEX_ENTRIES {
        return Err(format!("index: more than {MAX_INDEX_ENTRIES} packages"));
    }
    let mut seen = HashSet::new();
    for e in &list {
        let bad = |what: &str| format!("index: {}: {what}", e.name);
        valid_name(&e.name).map_err(|x| format!("index: {x}"))?;
        if !seen.insert(e.name.as_str()) {
            return Err(format!("index: {} twice", e.name));
        }
        if !valid_version(&e.version) {
            return Err(bad("version: 1-32 of [A-Za-z0-9._+-]"));
        }
        match (&e.url, &e.sha256) {
            (Some(_), Some(s)) if !is_sha256(s) => return Err(bad("sha256 must be 64 hex digits")),
            (Some(_), Some(_)) => {}
            (None, None) if !e.assets.is_empty() => {}
            (None, None) => return Err(bad("no assets and no url")),
            _ => return Err(bad("url and sha256 go together")),
        }
        for (host, a) in &e.assets {
            if host.is_empty() || a.url.is_empty() {
                return Err(bad("an asset needs a host and a url"));
            }
            if !is_sha256(&a.sha256) {
                return Err(bad("sha256 must be 64 hex digits"));
            }
        }
    }
    Ok(list)
}

/// `url` of an index entry as fetched: absolute as it is, otherwise
/// relative to the index's directory (a repository moves as a whole). A
/// relative URL may not leave that directory.
pub fn resolve(index_url: &str, url: &str) -> Result<String, String> {
    if url.contains("://") {
        return Ok(url.to_owned());
    }
    if url.starts_with('/')
        || url.contains('\\')
        || url.contains('?')
        || url
            .split('/')
            .any(|s| s.is_empty() || s == "." || s == "..")
    {
        return Err(format!("{url:?}: a relative url inside the repository"));
    }
    let base = match index_url.rfind('/') {
        Some(i) if i > index_url.find("://").map_or(0, |s| s + 2) => &index_url[..=i],
        _ => {
            return Err(format!(
                "{index_url}: no directory to resolve {url:?} against"
            ))
        }
    };
    Ok(format!("{base}{url}"))
}

/// A file of a package: its path in the zip, contents and unix mode.
#[derive(Debug, Clone)]
pub struct PackFile {
    pub path: String,
    pub data: Vec<u8>,
    pub mode: u32,
}

/// A package zip: `manifest` (checked) at the root, then `files` in path
/// order, every entry dated 1980-01-01, so the same input gives the same
/// bytes (and SHA-256).
pub fn pack(manifest: &Manifest, files: &[PackFile]) -> Result<Vec<u8>, String> {
    use zip::write::SimpleFileOptions;
    manifest.check()?;
    let mut sorted: Vec<&PackFile> = files.iter().collect();
    sorted.sort_by(|a, b| a.path.cmp(&b.path));
    if sorted.windows(2).any(|w| w[0].path == w[1].path)
        || sorted.iter().any(|f| f.path == MANIFEST)
    {
        return Err("a file twice in the package".into());
    }
    let json = serde_json::to_string_pretty(manifest).map_err(|e| e.to_string())? + "\n";
    let mut w = zip::ZipWriter::new(Cursor::new(Vec::new()));
    let opt = |mode: u32| {
        SimpleFileOptions::default()
            .compression_method(zip::CompressionMethod::Deflated)
            .last_modified_time(zip::DateTime::default())
            .unix_permissions(mode)
    };
    let mut put = |path: &str, data: &[u8], mode: u32| -> Result<(), String> {
        w.start_file(path, opt(mode)).map_err(|e| e.to_string())?;
        w.write_all(data).map_err(|e| e.to_string())
    };
    put(MANIFEST, json.as_bytes(), 0o644)?;
    for f in sorted {
        put(&f.path, &f.data, f.mode)?;
    }
    let bytes = w.finish().map_err(|e| e.to_string())?.into_inner();
    if bytes.len() > MAX_ZIP {
        return Err(format!("package larger than {} MiB", MAX_ZIP >> 20));
    }
    Ok(bytes)
}

/// The manifest of a package zip, checked.
pub fn read_manifest(zip: &[u8]) -> Result<Manifest, String> {
    let mut a = zip::ZipArchive::new(Cursor::new(zip)).map_err(|e| format!("zip: {e}"))?;
    let f = a
        .by_name(MANIFEST)
        .map_err(|_| format!("no {MANIFEST} at the zip root"))?;
    let mut text = String::new();
    f.take(MAX_MANIFEST)
        .read_to_string(&mut text)
        .map_err(|e| format!("{MANIFEST}: {e}"))?;
    let m: Manifest = serde_json::from_str(&text).map_err(|e| format!("{MANIFEST}: {e}"))?;
    m.check()?;
    Ok(m)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn process(name: &str) -> Manifest {
        Manifest {
            name: name.into(),
            version: "1.2.0".into(),
            description: "a link".into(),
            wyrm_link: crate::LINK_PROTOCOL,
            kind: "process".into(),
            entries: [("linux-x86_64".to_owned(), "bin/linux-x86_64/run".to_owned())].into(),
            args: vec![],
            entry: None,
            requester: vec![Grant {
                path: "wy/{site}/downstream/mock".into(),
                level: "read".into(),
            }],
            world: None,
            capabilities: None,
        }
    }

    fn app(caps: Capabilities) -> Manifest {
        Manifest {
            name: "acme".into(),
            version: "1.0.0".into(),
            description: String::new(),
            wyrm_link: crate::LINK_PROTOCOL,
            kind: "wasm".into(),
            entries: BTreeMap::new(),
            args: vec![],
            entry: Some("acme.wasm".into()),
            requester: vec![],
            world: Some("app".into()),
            capabilities: Some(caps),
        }
    }

    #[test]
    fn capabilities_bounds_and_kinds() {
        let ok = Capabilities {
            net: vec!["10.0.0.0/8:502".into()],
            store_mb: Some(64),
            memory_mb: Some(512),
            call_ms: Some(10_000),
        };
        assert!(app(ok.clone()).check().is_ok());
        assert!(app(Capabilities::default()).check().is_ok());
        assert_eq!(
            Capabilities::default().describe(),
            "net none, store 1 MiB, memory 64 MiB, call 2000 ms"
        );
        for (caps, field) in [
            (
                Capabilities {
                    store_mb: Some(65),
                    ..ok.clone()
                },
                "store_mb 65",
            ),
            (
                Capabilities {
                    memory_mb: Some(0),
                    ..ok.clone()
                },
                "memory_mb 0",
            ),
            (
                Capabilities {
                    memory_mb: Some(513),
                    ..ok.clone()
                },
                "memory_mb 513",
            ),
            (
                Capabilities {
                    call_ms: Some(0),
                    ..ok.clone()
                },
                "call_ms 0",
            ),
            (
                Capabilities {
                    call_ms: Some(10_001),
                    ..ok.clone()
                },
                "call_ms 10001",
            ),
            (
                Capabilities {
                    net: vec!["a:1,b:2".into()],
                    ..ok.clone()
                },
                "capabilities.net",
            ),
            (
                Capabilities {
                    net: vec!["host".into()],
                    ..ok.clone()
                },
                "capabilities.net",
            ),
        ] {
            let err = app(caps).check().unwrap_err();
            assert!(err.contains(field), "{field}: {err}");
        }
        // world belongs to wasm packages; capabilities to an app, WASM or process
        let mut m = process("acme");
        m.capabilities = Some(Capabilities {
            store_mb: Some(4),
            ..Capabilities::default()
        });
        assert!(m.check().is_ok());
        m.capabilities = Some(Capabilities {
            store_mb: Some(65),
            ..Capabilities::default()
        });
        assert!(m.check().unwrap_err().contains("store_mb"));
        let mut m = process("acme");
        m.world = Some("app".into());
        assert!(m.check().unwrap_err().contains("world"));
        let mut m = app(Capabilities::default());
        m.world = Some("driver".into());
        assert!(m.check().unwrap_err().contains("\"driver\""));
        m.capabilities = None;
        assert!(m.check().is_ok());
        m.world = Some("flow".into());
        assert!(m.check().unwrap_err().contains("app, driver or point"));
        // unknown capability fields are refused (`limits` is flat here)
        let text = r#"{"name":"a","version":"1","wyrm_link":1,"kind":"wasm","entry":"a.wasm",
            "capabilities":{"limits":{"call_ms":5}}}"#;
        assert!(serde_json::from_str::<Manifest>(text).is_err());
    }

    #[test]
    fn manifest_checks() {
        assert!(process("acme").check().is_ok());
        assert!(process(".sites").check().unwrap_err().contains("name"));
        let mut m = process("acme");
        m.version = "1 0".into();
        assert!(m.check().unwrap_err().contains("version"));
        let mut m = process("acme");
        m.wyrm_link += 1;
        assert!(m.check().unwrap_err().contains("protocol"));
        let mut m = process("acme");
        m.entries.clear();
        assert!(m.check().unwrap_err().contains("entries"));
        let mut m = process("acme");
        m.kind = "jar".into();
        assert!(m.check().unwrap_err().contains("process or wasm"));
        // unknown fields are refused
        let text = r#"{"name":"a","version":"1","wyrm_link":1,"kind":"wasm","entry":"a.wasm","entyr":"x"}"#;
        assert!(serde_json::from_str::<Manifest>(text).is_err());
    }

    #[test]
    fn pack_is_reproducible_and_reads_back() {
        let files = vec![
            PackFile {
                path: "bin/linux-x86_64/run".into(),
                data: b"#!".to_vec(),
                mode: 0o755,
            },
            PackFile {
                path: "README".into(),
                data: b"hi".to_vec(),
                mode: 0o644,
            },
        ];
        let a = pack(&process("acme"), &files).unwrap();
        let mut rev = files.clone();
        rev.reverse();
        let b = pack(&process("acme"), &rev).unwrap();
        assert_eq!(a, b, "same bytes whatever the order");
        assert_eq!(read_manifest(&a).unwrap(), process("acme"));
        let mut twice = files.clone();
        twice.push(files[0].clone());
        assert!(pack(&process("acme"), &twice).is_err());
        assert!(pack(&process(".x"), &files).is_err(), "checked first");
    }

    #[test]
    fn index_assets_and_legacy() {
        let sha = "a".repeat(64);
        let text = format!(
            r#"[{{"name":"acme","version":"1.0.0","assets":{{"linux-x86_64":{{"url":"acme/1.0.0/acme-linux.zip","sha256":"{sha}"}}}}}},
               {{"name":"reg","version":"1.0.0","url":"https://r/reg.zip","sha256":"{sha}"}}]"#
        );
        let list = parse_index(text.as_bytes()).unwrap();
        assert_eq!(
            list[0].asset("linux-x86_64").unwrap().url,
            "acme/1.0.0/acme-linux.zip"
        );
        assert_eq!(
            list[0].asset("macos-aarch64"),
            None,
            "no build for that host"
        );
        assert_eq!(
            list[1].asset("macos-aarch64").unwrap().url,
            "https://r/reg.zip"
        );
        for bad in [
            format!(
                r#"[{{"name":"a","version":"1","url":"u","sha256":"{sha}"}},{{"name":"a","version":"1","url":"u","sha256":"{sha}"}}]"#
            ),
            r#"[{"name":"a","version":"1"}]"#.to_owned(),
            r#"[{"name":"a","version":"1","url":"u"}]"#.to_owned(),
            r#"[{"name":"a","version":"1","assets":{"linux-x86_64":{"url":"u","sha256":"xx"}}}]"#
                .to_owned(),
        ] {
            assert!(parse_index(bad.as_bytes()).is_err(), "{bad}");
        }
    }

    #[test]
    fn relative_urls_stay_in_the_repository() {
        let idx = "https://repo.example/wyrm/index.json";
        assert_eq!(
            resolve(idx, "acme/1.0.0/acme.zip").unwrap(),
            "https://repo.example/wyrm/acme/1.0.0/acme.zip"
        );
        assert_eq!(
            resolve(idx, "https://cdn/x.zip").unwrap(),
            "https://cdn/x.zip"
        );
        for bad in ["/etc/x", "../x.zip", "a//b", "a/./b", "a?b"] {
            assert!(resolve(idx, bad).is_err(), "{bad}");
        }
        assert!(resolve("https://repo.example", "x.zip").is_err());
    }

    #[test]
    fn hosts() {
        assert_eq!(
            host_of_triple("aarch64-apple-darwin"),
            Some("macos-aarch64")
        );
        assert_eq!(
            host_of_triple("x86_64-unknown-linux-musl"),
            Some("linux-x86_64")
        );
        assert_eq!(
            host_of_triple("aarch64-unknown-linux-gnu"),
            Some("linux-aarch64")
        );
        assert_eq!(host_of_triple("wasm32-wasip2"), None);
        assert!(platform().contains('-'));
    }
}
