//! A person's choices as the files of a config region (ADR 0051 §4): what the image builder
//! page asks (a site, the network, the links, the time zone, NTP, SSH keys) and what
//! `wyr image build --choices` reads, turned into [`ConfigFiles`] the device takes.
//!
//! The page and `wyr` call the same [`Choices::files`], so the same choices and the same
//! setup hash give the same region, byte for byte. What a person typed reaches a file only
//! as a JSON string literal (`wyrmd.json5`, `seed.json`), as a parsed IPv4 address (the
//! UCI text of `network`) or as a file of its own that the device checks (`timezone`,
//! `ntp`, `authorized_keys`); the result has passed [`ConfigFiles::check`].

use std::collections::BTreeSet;
use std::net::Ipv4Addr;

use serde::{Deserialize, Serialize};
use wyrm_core::hex;

use crate::index::{ImageEntry, IndexError, Lan};
use crate::region::{ConfigFiles, SEED_DIR, SETUP_FILE};
use crate::{ImageError, DATA_DIR};

/// The format name of a choices file.
pub const CHOICES_FORMAT: &str = "wyrm-choices/1";
/// Where the gateway of a board listens: every address, on the port the device's firewall
/// opens (`allow wyrm_gateway tcp 8445` of `90-wyrm-host`). The device reads no port from
/// the configuration, so another port would never be reached.
pub const GATEWAY_LISTEN: &str = "0.0.0.0:8445";
/// The format name of the seed list the device's broker reads.
const SEED_FORMAT: &str = "wyrm-seed/1";

wyrm_core::name_enum! {
    /// The broker's own links: each is a section `<id>: { enabled }` of `wyrmd.json5`.
    enum Service as "broker service" without codec {
        Scheduler => "scheduler",
        Alarm => "alarm",
        Dql => "dql",
        Uplink => "uplink",
    }
}

/// The id of the broker's storage link: no link of `links` may take it.
const STORAGE_LINK: &str = "storage";

/// What a person chose for one board image (`wyrm-choices/1`).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(try_from = "ChoicesFile", into = "ChoicesFile")]
pub struct Choices {
    /// The site name.
    pub site: String,
    /// The network of the interface `lan`.
    pub network: Network,
    /// The ids of the chosen links, from the catalog. The order does not matter, and an id
    /// twice is one.
    pub links: Vec<String>,
    /// The IANA name of the time zone. Without it (or empty): UTC.
    pub timezone: Option<String>,
    /// NTP servers. Without them: those of DHCP, then OpenWrt's pool.
    pub ntp: Vec<String>,
    /// SSH public keys for `root`, as the text of `authorized_keys`. Without them (or
    /// blank): no SSH login.
    pub ssh_keys: Option<String>,
}

/// The JSON of [`Choices`], with its format name.
#[derive(Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct ChoicesFile {
    format: String,
    site: String,
    network: Network,
    #[serde(default)]
    links: Vec<String>,
    #[serde(default)]
    timezone: Option<String>,
    #[serde(default)]
    ntp: Vec<String>,
    #[serde(default)]
    ssh_keys: Option<String>,
}

/// A choices file of another format (the text is the format it names). Its message is the
/// cause alone: [`Choices::parse`] puts it into [`ChoicesError::Format`].
#[derive(Debug, thiserror::Error)]
#[error("the format is `{0}`, this build reads `{CHOICES_FORMAT}`")]
struct OtherFormat(String);

impl TryFrom<ChoicesFile> for Choices {
    type Error = OtherFormat;

    fn try_from(file: ChoicesFile) -> Result<Self, OtherFormat> {
        if file.format != CHOICES_FORMAT {
            return Err(OtherFormat(file.format));
        }
        Ok(Self {
            site: file.site,
            network: file.network,
            links: file.links,
            timezone: file.timezone,
            ntp: file.ntp,
            ssh_keys: file.ssh_keys,
        })
    }
}

impl From<Choices> for ChoicesFile {
    fn from(c: Choices) -> Self {
        Self {
            format: CHOICES_FORMAT.to_owned(),
            site: c.site,
            network: c.network,
            links: c.links,
            timezone: c.timezone,
            ntp: c.ntp,
            ssh_keys: c.ssh_keys,
        }
    }
}

/// The network of the device: a DHCP client, or a static IPv4 address on `lan`.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "mode", rename_all = "lowercase", deny_unknown_fields)]
pub enum Network {
    /// The device asks DHCP for its address (OpenWrt's `lan` as the image has it). Fields
    /// beside `mode` are passed over (serde reads no more of a unit variant).
    Dhcp,
    /// A fixed address.
    Static {
        /// The device's IPv4 address, `192.168.1.20`.
        address: String,
        /// The length of the network prefix, 1 to 32 (24 is `255.255.255.0`).
        prefix: u8,
        /// The default gateway, in the device's network.
        #[serde(default, skip_serializing_if = "Option::is_none")]
        gateway: Option<String>,
        /// DNS servers, IPv4 addresses.
        #[serde(default, skip_serializing_if = "Vec::is_empty")]
        dns: Vec<String>,
    },
}

/// The links an image offers: built from `links/official.json` and the packages the image
/// carries in its seed directory. Fields this build does not know are passed over.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Catalog {
    /// The links, in the order they are written.
    pub links: Vec<CatalogLink>,
}

/// One link of a [`Catalog`].
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct CatalogLink {
    /// The link id.
    pub id: String,
    /// How the image runs it.
    pub form: LinkForm,
    /// The driver of a [`LinkForm::Builtin`] link.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub driver: Option<String>,
    /// The package zip of a [`LinkForm::Seed`] link, a plain name in the seed directory.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub file: Option<String>,
}

/// How an image runs a link.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum LinkForm {
    /// A driver built into `wyrmd`: an entry of `links`.
    Builtin,
    /// One of the broker's own links, switched on or off by its section.
    Service,
    /// A package the image carries, installed at the first start (`seed.json`).
    Seed,
}

/// Why choices are refused. Each message is a sentence for the person who chose.
#[derive(Debug, thiserror::Error)]
pub enum ChoicesError {
    /// The choices are not a `wyrm-choices/1` JSON (the text says what is wrong).
    #[error("the choices cannot be read: {0}")]
    Format(String),
    /// A chosen link is not in the catalog, or its entry is one the broker refuses.
    #[error("the link `{0}` is not one this image offers")]
    UnknownLink(String),
    /// A static address on a board whose entry names no network ports.
    #[error("this board's image does not say which network ports it has: choose DHCP")]
    NoLan,
    /// An address that is no IPv4 address the device can take.
    #[error("`{0}` is refused: write an IPv4 address as four numbers 0 to 255 (192.168.1.20); the device's address is no network, broadcast, loopback or multicast address, and the gateway is another address in the device's network")]
    BadAddress(String),
    /// A prefix outside 1 to 32.
    #[error("the prefix /{0} is refused: it is 1 to 32 (24 is 255.255.255.0)")]
    BadPrefix(u8),
    /// The files are refused by the device's rules (a site, a time zone, NTP servers).
    #[error("{0}")]
    Device(ImageError),
}

/// A text as a JSON string literal: quotes, backslashes and control characters escaped.
fn literal(text: &str) -> String {
    serde_json::Value::String(text.to_owned()).to_string()
}

/// A package file name the broker opens in the seed directory: not empty, no separator,
/// not starting with `.`.
fn plain_file(name: &str) -> bool {
    !name.is_empty() && !name.starts_with('.') && !name.contains(['/', '\\'])
}

/// A link id the broker takes for a new link: a key segment that is not one of its own.
fn link_id(id: &str) -> bool {
    wyrm_core::keyspace::validate_segment(id).is_ok()
        && id != STORAGE_LINK
        && Service::from_name(id).is_none()
}

/// The chosen links of the catalog, in the catalog's order, each id once.
struct Picked<'a> {
    builtin: Vec<(&'a str, &'a str)>,
    seed: Vec<(&'a str, &'a str)>,
    /// Every service of the catalog, with whether it was chosen.
    services: Vec<(Service, bool)>,
}

/// The chosen links of `catalog`. A chosen id the catalog lacks, or whose entry the broker
/// would refuse (a built-in link without a driver or with a broker's id, a seed without a
/// plain file, a service the broker has no section for), is [`ChoicesError::UnknownLink`].
fn pick<'a>(chosen: &BTreeSet<&str>, catalog: &'a Catalog) -> Result<Picked<'a>, ChoicesError> {
    let mut seen = BTreeSet::new();
    let mut picked = Picked {
        builtin: Vec::new(),
        seed: Vec::new(),
        services: Vec::new(),
    };
    for link in &catalog.links {
        let id = link.id.as_str();
        if !seen.insert(id) {
            continue;
        }
        let on = chosen.contains(id);
        let unknown = || ChoicesError::UnknownLink(id.to_owned());
        match link.form {
            LinkForm::Service => match Service::from_name(id) {
                Some(service) => picked.services.push((service, on)),
                None if on => return Err(unknown()),
                None => {}
            },
            _ if !on => {}
            LinkForm::Builtin => match link.driver.as_deref() {
                Some(driver) if link_id(id) => picked.builtin.push((id, driver)),
                _ => return Err(unknown()),
            },
            LinkForm::Seed => match link.file.as_deref() {
                Some(file) if link_id(id) && plain_file(file) => picked.seed.push((id, file)),
                _ => return Err(unknown()),
            },
        }
    }
    if let Some(id) = chosen.iter().find(|id| !seen.contains(*id)) {
        return Err(ChoicesError::UnknownLink((*id).to_owned()));
    }
    Ok(picked)
}

/// `wyrmd.json5` of the image: every string a JSON literal.
fn wyrmd_json5(site: &str, picked: &Picked<'_>) -> String {
    let mut out = String::from("// wyrmd.json5, made by the WYRM image builder\n{\n");
    let mut line = |text: String| {
        out.push_str("  ");
        out.push_str(&text);
        out.push('\n');
    };
    line(format!("site: {},", literal(site)));
    line(format!("data_dir: {},", literal(DATA_DIR)));
    line(
        "// the certificate comes from the site CA; the first admin from the setup code".to_owned(),
    );
    line(format!(
        "gateway: {{ listen: {}, tls: \"site_ca\", setup_file: {} }},",
        literal(GATEWAY_LISTEN),
        literal(SETUP_FILE)
    ));
    line("updates: { mode: \"off\" },".to_owned());
    let seed_dir = if picked.seed.is_empty() {
        String::new()
    } else {
        format!(", seed_dir: {}", literal(SEED_DIR))
    };
    line(format!(
        "packages: {{ repository: \"official\"{seed_dir} }},"
    ));
    for (service, on) in &picked.services {
        line(format!("{}: {{ enabled: {on} }},", service.name()));
    }
    if picked.builtin.is_empty() {
        line("links: {},".to_owned());
    } else {
        line("links: {".to_owned());
        for (id, driver) in &picked.builtin {
            line(format!(
                "  {}: {{ driver: {} }},",
                literal(id),
                literal(driver)
            ));
        }
        line("},".to_owned());
    }
    out.push_str("}\n");
    out
}

/// `seed.json`: the chosen packages, none accepted on the person's behalf.
fn seed_json(seed: &[(&str, &str)]) -> String {
    let mut out = format!(
        "{{\n  \"format\": {},\n  \"links\": [\n",
        literal(SEED_FORMAT)
    );
    for (i, (id, file)) in seed.iter().enumerate() {
        let comma = if i + 1 < seed.len() { "," } else { "" };
        out.push_str(&format!(
            "    {{ \"link\": {}, \"file\": {}, \"accept\": false }}{comma}\n",
            literal(id),
            literal(file)
        ));
    }
    out.push_str("  ]\n}\n");
    out
}

/// An IPv4 address as written; anything else is [`ChoicesError::BadAddress`].
fn ipv4(text: &str) -> Result<Ipv4Addr, ChoicesError> {
    text.parse()
        .map_err(|_e: std::net::AddrParseError| ChoicesError::BadAddress(text.to_owned()))
}

/// The UCI text of `network` for a static address: OpenWrt's loopback, the bridge of the
/// board's ports when it has one, and `lan` on it.
fn network(
    lan: &Lan,
    address: &str,
    prefix: u8,
    gateway: Option<&str>,
    dns: &[String],
) -> Result<String, ChoicesError> {
    if !(1..=32).contains(&prefix) {
        return Err(ChoicesError::BadPrefix(prefix));
    }
    let shift = 32 - u32::from(prefix);
    let mask = u32::MAX.checked_shl(shift).unwrap_or(0);
    let addr = ipv4(address)?;
    let host = u32::from(addr) & !mask;
    // on a /31 and a /32 every address is a host's
    let edge = prefix <= 30 && (host == 0 || host == !mask);
    if addr.is_unspecified()
        || addr.is_loopback()
        || addr.is_multicast()
        || addr.is_broadcast()
        || edge
    {
        return Err(ChoicesError::BadAddress(address.to_owned()));
    }
    let gateway = gateway
        .map(|text| {
            let gw = ipv4(text)?;
            let same_net = u32::from(gw) & mask == u32::from(addr) & mask;
            if gw == addr || !same_net {
                return Err(ChoicesError::BadAddress(text.to_owned()));
            }
            Ok(gw)
        })
        .transpose()?;
    let dns = dns.iter().map(|d| ipv4(d)).collect::<Result<Vec<_>, _>>()?;

    let mut out = String::from(
        "config interface 'loopback'\n\toption device 'lo'\n\toption proto 'static'\n\
         \toption ipaddr '127.0.0.1'\n\toption netmask '255.0.0.0'\n\n",
    );
    let device = match lan {
        Lan::Device { device } => device,
        Lan::Bridge { bridge, ports } => {
            out.push_str(&format!(
                "config device\n\toption name '{bridge}'\n\toption type 'bridge'\n"
            ));
            for port in ports {
                out.push_str(&format!("\tlist ports '{port}'\n"));
            }
            out.push('\n');
            bridge
        }
    };
    out.push_str(&format!(
        "config interface 'lan'\n\toption device '{device}'\n\toption proto 'static'\n\
         \toption ipaddr '{addr}'\n\toption netmask '{}'\n",
        Ipv4Addr::from(mask)
    ));
    if let Some(gw) = gateway {
        out.push_str(&format!("\toption gateway '{gw}'\n"));
    }
    for d in dns {
        out.push_str(&format!("\tlist dns '{d}'\n"));
    }
    Ok(out)
}

impl Choices {
    /// Reads choices from their JSON (`wyrm-choices/1`): an unknown field, a missing one or
    /// another format is [`ChoicesError::Format`].
    pub fn parse(text: &str) -> Result<Self, ChoicesError> {
        serde_json::from_str(text).map_err(|e| ChoicesError::Format(e.to_string()))
    }

    /// The files of the config region for these choices on the board of `entry`, with the
    /// links of `catalog` and the SHA-256 of a setup code. The result has passed
    /// [`ConfigFiles::check`]: what the device refuses is [`ChoicesError::Device`].
    pub fn files(
        &self,
        entry: &ImageEntry,
        catalog: &Catalog,
        setup_hash: &[u8; 32],
    ) -> Result<ConfigFiles, ChoicesError> {
        let chosen: BTreeSet<&str> = self.links.iter().map(String::as_str).collect();
        let picked = pick(&chosen, catalog)?;
        let network = match &self.network {
            Network::Dhcp => None,
            Network::Static {
                address,
                prefix,
                gateway,
                dns,
            } => {
                let lan = entry.lan.as_ref().ok_or(ChoicesError::NoLan)?;
                if !lan.is_plain() {
                    let bad = IndexError::BadLan(entry.board.clone());
                    return Err(ChoicesError::Device(bad.into()));
                }
                Some(network(lan, address, *prefix, gateway.as_deref(), dns)?)
            }
        };
        let timezone = self
            .timezone
            .as_deref()
            .map(str::trim)
            .filter(|tz| !tz.is_empty())
            .map(|tz| format!("{tz}\n"));
        let ntp: String = self
            .ntp
            .iter()
            .map(|s| s.trim())
            .filter(|s| !s.is_empty())
            .map(|s| format!("{s}\n"))
            .collect();
        let authorized_keys = self
            .ssh_keys
            .as_deref()
            .filter(|keys| !keys.trim().is_empty())
            .map(|keys| {
                if keys.ends_with('\n') {
                    keys.to_owned()
                } else {
                    format!("{keys}\n")
                }
            });
        let files = ConfigFiles {
            wyrmd_json5: wyrmd_json5(&self.site, &picked),
            network,
            seed_json: (!picked.seed.is_empty()).then(|| seed_json(&picked.seed)),
            setup: Some(hex::encode(setup_hash)),
            authorized_keys,
            timezone,
            ntp: (!ntp.is_empty()).then_some(ntp),
        };
        files.check().map_err(ChoicesError::Device)?;
        Ok(files)
    }
}

#[cfg(test)]
mod tests {
    #![allow(
        clippy::unwrap_used,
        clippy::panic,
        reason = "test code: a failed step fails the test"
    )]

    use super::*;
    use crate::{region, ImageEntry};

    const HASH: [u8; 32] = [0xab; 32];

    fn entry(lan: Option<Lan>) -> ImageEntry {
        ImageEntry {
            board: "bpi-r4".to_owned(),
            file: "wyrm-bpi-r4.img".to_owned(),
            size: 1 << 30,
            sha256: "cd".repeat(32),
            config_offset: 1 << 28,
            openwrt: "25.12.6".to_owned(),
            wyrmd: "0.9.0".to_owned(),
            wyrmd_sha256: None,
            manifest_sha256: None,
            download: None,
            title: None,
            notes: None,
            lan,
        }
    }

    fn bridge() -> Lan {
        Lan::Bridge {
            bridge: "br-lan".to_owned(),
            ports: ["lan1", "lan2", "lan3", "sfp-lan"]
                .map(str::to_owned)
                .to_vec(),
        }
    }

    fn link(id: &str, form: LinkForm, driver: Option<&str>, file: Option<&str>) -> CatalogLink {
        CatalogLink {
            id: id.to_owned(),
            form,
            driver: driver.map(str::to_owned),
            file: file.map(str::to_owned),
        }
    }

    fn catalog() -> Catalog {
        Catalog {
            links: vec![
                link("modbus", LinkForm::Builtin, Some("modbus"), None),
                link("opcua", LinkForm::Builtin, Some("opcua"), None),
                link("scheduler", LinkForm::Service, None, None),
                link("alarm", LinkForm::Service, None, None),
                link("dql", LinkForm::Service, None, None),
                link("uplink", LinkForm::Service, None, None),
                link("mqtt", LinkForm::Seed, None, Some("mqtt-0.1.0.zip")),
                link("telegram", LinkForm::Seed, None, Some("telegram-0.1.0.zip")),
            ],
        }
    }

    fn choices(links: &[&str]) -> Choices {
        Choices {
            site: "plant".to_owned(),
            network: Network::Dhcp,
            links: links.iter().map(|l| (*l).to_owned()).collect(),
            timezone: Some("Europe/Kyiv".to_owned()),
            ntp: vec!["pool.ntp.org".to_owned(), "2001:db8::1".to_owned()],
            ssh_keys: None,
        }
    }

    fn files(choices: &Choices) -> Result<ConfigFiles, ChoicesError> {
        choices.files(&entry(Some(bridge())), &catalog(), &HASH)
    }

    fn static_net() -> Network {
        Network::Static {
            address: "192.168.10.5".to_owned(),
            prefix: 24,
            gateway: Some("192.168.10.1".to_owned()),
            dns: vec!["192.168.10.1".to_owned(), "9.9.9.9".to_owned()],
        }
    }

    #[test]
    fn dhcp_writes_no_network_file() {
        let files = files(&choices(&[])).unwrap();
        assert_eq!(files.network, None);
        let config = &files.wyrmd_json5;
        assert_eq!(crate::site_of(config).as_deref(), Some("plant"));
        assert!(config.contains("data_dir: \"/srv/wyrm\""), "{config}");
        assert!(
            config.contains(&format!("listen: \"{GATEWAY_LISTEN}\"")),
            "{config}"
        );
        assert!(config.contains("tls: \"site_ca\""), "{config}");
        assert!(config.contains("updates: { mode: \"off\" }"), "{config}");
        assert!(config.contains("repository: \"official\""), "{config}");
        // no seed link chosen: no seed directory named, no seed file
        assert!(!config.contains("seed_dir"), "{config}");
        assert_eq!(files.seed_json, None);
        assert_eq!(files.timezone.as_deref(), Some("Europe/Kyiv\n"));
        assert_eq!(files.ntp.as_deref(), Some("pool.ntp.org\n2001:db8::1\n"));
        assert_eq!(files.authorized_keys, None);
    }

    #[test]
    fn static_on_a_bridge_board_writes_the_bridge() {
        let mut c = choices(&[]);
        c.network = static_net();
        let network = files(&c).unwrap().network.unwrap();
        assert!(
            network.starts_with("config interface 'loopback'\n"),
            "{network}"
        );
        assert!(network.contains("\toption device 'lo'\n"), "{network}");
        assert!(network.contains("config device\n"), "{network}");
        assert!(network.contains("\toption name 'br-lan'\n"), "{network}");
        assert!(network.contains("\toption type 'bridge'\n"), "{network}");
        for port in ["lan1", "lan2", "lan3", "sfp-lan"] {
            assert!(
                network.contains(&format!("\tlist ports '{port}'\n")),
                "{network}"
            );
        }
        assert!(network.contains("config interface 'lan'\n"), "{network}");
        assert!(network.contains("\toption device 'br-lan'\n"), "{network}");
        assert!(network.contains("\toption proto 'static'\n"), "{network}");
        assert!(
            network.contains("\toption ipaddr '192.168.10.5'\n"),
            "{network}"
        );
        assert!(
            network.contains("\toption netmask '255.255.255.0'\n"),
            "{network}"
        );
        assert!(
            network.contains("\toption gateway '192.168.10.1'\n"),
            "{network}"
        );
        assert!(network.contains("\tlist dns '192.168.10.1'\n"), "{network}");
        assert!(network.contains("\tlist dns '9.9.9.9'\n"), "{network}");

        // one port without a bridge: the interface names the port itself
        let device = Lan::Device {
            device: "eth0".to_owned(),
        };
        let network = c
            .files(&entry(Some(device)), &catalog(), &HASH)
            .unwrap()
            .network
            .unwrap();
        assert!(!network.contains("config device"), "{network}");
        assert!(network.contains("\toption device 'eth0'\n"), "{network}");
    }

    #[test]
    fn the_netmask_follows_the_prefix() {
        for (prefix, mask) in [
            (8, "255.0.0.0"),
            (16, "255.255.0.0"),
            (23, "255.255.254.0"),
            (30, "255.255.255.252"),
            (32, "255.255.255.255"),
        ] {
            let mut c = choices(&[]);
            c.network = Network::Static {
                address: "10.1.2.5".to_owned(),
                prefix,
                gateway: None,
                dns: Vec::new(),
            };
            let network = files(&c).unwrap().network.unwrap();
            assert!(
                network.contains(&format!("\toption netmask '{mask}'\n")),
                "{prefix}"
            );
            assert!(!network.contains("gateway"), "{network}");
            assert!(!network.contains("dns"), "{network}");
        }
    }

    #[test]
    fn static_without_lan_is_refused() {
        let mut c = choices(&[]);
        c.network = static_net();
        let e = c.files(&entry(None), &catalog(), &HASH).unwrap_err();
        assert!(matches!(e, ChoicesError::NoLan), "{e}");
        // DHCP needs no ports
        assert!(choices(&[]).files(&entry(None), &catalog(), &HASH).is_ok());
    }

    #[test]
    fn a_bad_address_or_prefix_is_refused() {
        let with = |address: &str, prefix: u8, gateway: Option<&str>, dns: &[&str]| {
            let mut c = choices(&[]);
            c.network = Network::Static {
                address: address.to_owned(),
                prefix,
                gateway: gateway.map(str::to_owned),
                dns: dns.iter().map(|d| (*d).to_owned()).collect(),
            };
            files(&c)
        };
        for (address, gateway, dns) in [
            ("192.168.10", None, &[][..]),
            ("192.168.10.256", None, &[]),
            ("192.168.10.5 ", None, &[]),
            ("fe80::1", None, &[]),
            ("0.0.0.0", None, &[]),
            ("127.0.0.1", None, &[]),
            ("224.0.0.1", None, &[]),
            // the network and the broadcast address of the /24
            ("192.168.10.0", None, &[]),
            ("192.168.10.255", None, &[]),
            ("192.168.10.5", Some("192.168.11.1"), &[]),
            ("192.168.10.5", Some("192.168.10.5"), &[]),
            ("192.168.10.5", Some("x"), &[]),
            ("192.168.10.5", None, &["9.9.9"]),
            ("192.168.10.5", None, &["9.9.9.9'"]),
        ] {
            let e = with(address, 24, gateway, dns).unwrap_err();
            assert!(
                matches!(e, ChoicesError::BadAddress(_)),
                "{address} {gateway:?} {dns:?}: {e}"
            );
        }
        for prefix in [0, 33, 255] {
            let e = with("192.168.10.5", prefix, None, &[]).unwrap_err();
            assert!(
                matches!(e, ChoicesError::BadPrefix(p) if p == prefix),
                "{e}"
            );
        }
    }

    #[test]
    fn a_site_the_device_refuses_is_refused() {
        for site in [".plant", "", "pla nt", "a/b", &"s".repeat(65)] {
            let mut c = choices(&[]);
            c.site = site.to_owned();
            let e = files(&c).unwrap_err();
            assert!(
                matches!(e, ChoicesError::Device(ImageError::Site)),
                "{site:?}: {e}"
            );
        }
    }

    #[test]
    fn a_quote_in_the_site_cannot_break_the_config() {
        let mut c = choices(&[]);
        c.site = "pla\"nt".to_owned();
        let e = files(&c).unwrap_err();
        assert!(matches!(e, ChoicesError::Device(ImageError::Site)), "{e}");

        // every string of the config is a JSON string literal: what a person typed never
        // closes a string or adds a member, and the files of its own carry the rest
        let mut c = choices(&["modbus"]);
        c.timezone = Some("Europe/Kyiv\", data_dir: \"/tmp".to_owned());
        assert!(matches!(
            files(&c).unwrap_err(),
            ChoicesError::Device(ImageError::Timezone)
        ));
        let mut c = choices(&[]);
        c.ntp = vec!["pool.ntp.org\" }, x: { y: \"".to_owned()];
        assert!(matches!(
            files(&c).unwrap_err(),
            ChoicesError::Device(ImageError::Ntp)
        ));
        let config = files(&choices(&["modbus"])).unwrap().wyrmd_json5;
        assert!(!config.contains("Europe/Kyiv"), "{config}");
        assert!(!config.contains("pool.ntp.org"), "{config}");

        // a catalog's names reach the config as escaped literals only
        let mut odd = catalog();
        odd.links
            .push(link("odd", LinkForm::Builtin, Some("a\"b\\c\n"), None));
        let config = choices(&["odd"])
            .files(&entry(None), &odd, &HASH)
            .unwrap()
            .wyrmd_json5;
        assert!(
            config.contains(r#""odd": { driver: "a\"b\\c\n" }"#),
            "{config}"
        );
    }

    #[test]
    fn seed_lists_only_seed_links() {
        let files = files(&choices(&[
            "telegram",
            "modbus",
            "scheduler",
            "mqtt",
            "mqtt",
        ]))
        .unwrap();
        let seed: serde_json::Value =
            serde_json::from_str(files.seed_json.as_deref().unwrap()).unwrap();
        // catalog order, each once, never accepted on the person's behalf
        assert_eq!(
            seed,
            serde_json::json!({
                "format": "wyrm-seed/1",
                "links": [
                    {"link": "mqtt", "file": "mqtt-0.1.0.zip", "accept": false},
                    {"link": "telegram", "file": "telegram-0.1.0.zip", "accept": false},
                ]
            })
        );
        assert!(files
            .wyrmd_json5
            .contains(&format!("seed_dir: \"{SEED_DIR}\"")));
        // the built-in link goes into `links`, the seed links do not
        assert!(files
            .wyrmd_json5
            .contains(r#""modbus": { driver: "modbus" }"#));
        assert!(!files.wyrmd_json5.contains("\"mqtt\""));
    }

    #[test]
    fn service_links_are_switched() {
        let config = files(&choices(&["dql", "scheduler"])).unwrap().wyrmd_json5;
        for (id, on) in [
            ("scheduler", true),
            ("alarm", false),
            ("dql", true),
            ("uplink", false),
        ] {
            assert!(
                config.contains(&format!("\n  {id}: {{ enabled: {on} }},\n")),
                "{id}: {config}"
            );
        }
        assert!(config.contains("links: {},"), "{config}");
    }

    #[test]
    fn unknown_link_is_refused() {
        let e = files(&choices(&["modbus", "nope"])).unwrap_err();
        assert!(
            matches!(&e, ChoicesError::UnknownLink(id) if id == "nope"),
            "{e}"
        );
        // a catalog entry the broker would refuse is no link the image offers
        let mut bad = catalog();
        bad.links.extend([
            link("cron", LinkForm::Service, None, None),
            link("storage", LinkForm::Builtin, Some("storage"), None),
            link("x y", LinkForm::Builtin, Some("x"), None),
            link("nodriver", LinkForm::Builtin, None, None),
            link("nofile", LinkForm::Seed, None, None),
            link("dots", LinkForm::Seed, None, Some("../x.zip")),
        ]);
        for id in ["cron", "storage", "x y", "nodriver", "nofile", "dots"] {
            let e = choices(&[id]).files(&entry(None), &bad, &HASH).unwrap_err();
            assert!(
                matches!(&e, ChoicesError::UnknownLink(i) if i == id),
                "{id}: {e}"
            );
        }
        // an entry of the catalog that is not chosen is not read
        assert!(choices(&["modbus"])
            .files(&entry(None), &bad, &HASH)
            .is_ok());
    }

    #[test]
    fn the_setup_file_is_the_hash() {
        let hash: [u8; 32] = std::array::from_fn(|i| u8::try_from(i * 7).unwrap());
        let files = choices(&[]).files(&entry(None), &catalog(), &hash).unwrap();
        assert_eq!(
            files.setup.as_deref(),
            Some(wyrm_core::hex::encode(hash).as_str())
        );
        assert!(files
            .wyrmd_json5
            .contains(&format!("setup_file: \"{SETUP_FILE}\"")));
    }

    #[test]
    fn ssh_keys_become_authorized_keys() {
        let mut c = choices(&[]);
        c.ssh_keys = Some("ssh-ed25519 AAAA person@host".to_owned());
        assert_eq!(
            files(&c).unwrap().authorized_keys.as_deref(),
            Some("ssh-ed25519 AAAA person@host\n")
        );
        c.ssh_keys = Some(" \n".to_owned());
        assert_eq!(files(&c).unwrap().authorized_keys, None);
        c.timezone = Some(String::new());
        c.ntp = vec![String::new()];
        let f = files(&c).unwrap();
        assert_eq!((f.timezone, f.ntp), (None, None));
    }

    #[test]
    fn the_same_choices_give_the_same_region() {
        let mut c = choices(&["mqtt", "modbus", "alarm"]);
        c.network = static_net();
        let a = region(&files(&c).unwrap()).unwrap();
        let b = region(&files(&c).unwrap()).unwrap();
        assert_eq!(a, b);
        // the order a person clicked in changes nothing
        c.links.reverse();
        assert_eq!(region(&files(&c).unwrap()).unwrap(), a);
    }

    #[test]
    fn choices_are_read_from_their_json() {
        let text = r#"{"format": "wyrm-choices/1", "site": "plant",
            "network": {"mode": "static", "address": "10.0.0.5", "prefix": 24,
                        "gateway": "10.0.0.1", "dns": ["10.0.0.1"]},
            "links": ["modbus"], "timezone": "UTC", "ntp": [], "ssh_keys": null}"#;
        let c = Choices::parse(text).unwrap();
        assert_eq!(c.site, "plant");
        assert!(matches!(&c.network, Network::Static { prefix: 24, .. }));
        // and written back the same way
        let back = serde_json::to_string(&c).unwrap();
        assert_eq!(Choices::parse(&back).unwrap(), c);
        assert!(back.contains("\"format\":\"wyrm-choices/1\""), "{back}");
        let dhcp = Choices::parse(
            r#"{"format": "wyrm-choices/1", "site": "p", "network": {"mode": "dhcp"}}"#,
        )
        .unwrap();
        assert_eq!(dhcp.network, Network::Dhcp);
        assert!(dhcp.links.is_empty() && dhcp.ntp.is_empty());
        // the cause once, after one prefix
        let e = Choices::parse(
            r#"{"format": "wyrm-choices/9", "site": "p", "network": {"mode": "dhcp"}}"#,
        )
        .unwrap_err()
        .to_string();
        assert_eq!(e.matches("cannot be read").count(), 1, "{e}");
        assert!(
            e.contains("the format is `wyrm-choices/9`, this build reads `wyrm-choices/1`"),
            "{e}"
        );
        for bad in [
            r#"{"format": "wyrm-choices/2", "site": "p", "network": {"mode": "dhcp"}}"#,
            r#"{"site": "p", "network": {"mode": "dhcp"}}"#,
            r#"{"format": "wyrm-choices/1", "site": "p", "network": {"mode": "dhcp"}, "x": 1}"#,
            r#"{"format": "wyrm-choices/1", "site": "p", "network": {"mode": "wifi"}}"#,
            r#"{"format": "wyrm-choices/1", "site": "p", "network": {"mode": "static", "address": "1.2.3.4", "prefix": 24, "x": 1}}"#,
            "not json",
        ] {
            assert!(
                matches!(Choices::parse(bad), Err(ChoicesError::Format(_))),
                "{bad}"
            );
        }
    }

    #[test]
    fn a_catalog_takes_fields_it_does_not_know() {
        let c: Catalog = serde_json::from_str(
            r#"{"links": [{"id": "modbus", "form": "builtin", "driver": "modbus",
                "title": "Modbus", "category": "Equipment"},
                {"id": "mqtt", "form": "seed", "file": "mqtt.zip"},
                {"id": "dql", "form": "service"}], "more": 1}"#,
        )
        .unwrap();
        assert_eq!(c.links.len(), 3);
        assert_eq!(c.links[2].form, LinkForm::Service);
    }

    /// The port of the gateway is the one the device's firewall opens (`90-wyrm-host`).
    #[test]
    fn the_gateway_port_is_the_one_the_device_opens() {
        let script =
            include_str!("../../../packaging/openwrt/wyrmd/files/etc/uci-defaults/90-wyrm-host");
        let ports: Vec<&str> = script
            .lines()
            .filter_map(|line| line.trim().strip_prefix("allow wyrm_gateway tcp "))
            .map(|rest| rest.split_whitespace().next().unwrap())
            .collect();
        assert_eq!(ports.len(), 1, "one `allow wyrm_gateway tcp` line");
        let (host, port) = GATEWAY_LISTEN.rsplit_once(':').unwrap();
        assert_eq!(host, "0.0.0.0");
        assert_eq!(port, ports[0]);
    }
}
