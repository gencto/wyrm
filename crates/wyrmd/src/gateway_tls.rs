//! The gateway's certificate from the site CA (`gateway.tls: "site_ca"`, ADR 0051 §3).
//!
//! At each start the broker asks its site CA (`data_dir/pki`) for a server certificate
//! with CN `gateway:<site>` in `data_dir/gateway/tls.{pem,key}`. The CA keeps the one there
//! while it names exactly the same names and has more than 30 days left, so a restart on
//! the same host serves the same certificate and a client that pinned the CA needs nothing
//! new. While the gateway serves, [`watch`] reads the host's addresses every 30 s and, when
//! the names differ from the ones of the certificate served, or that certificate has less
//! than 30 days left, issues one for the names and serves it from the next connection on,
//! without a restart.

use std::collections::BTreeSet;
use std::net::{IpAddr, SocketAddr};
use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::time::Duration;

use wyrm_admin::secret::Pki;
use wyrm_gateway::Gateway;
use zeroize::Zeroizing;

use crate::announce::host_label;
use crate::Config;

/// How often [`watch`] reads the host's addresses.
pub const WATCH_EVERY: Duration = Duration::from_secs(30);

/// The directory (under `data_dir`) and the file stem of the site-CA certificate.
const DIR: &str = "gateway";
const STEM: &str = "tls";

/// The certificate and key files of `gateway.tls: "site_ca"` under `data_dir`:
/// `data_dir/gateway/tls.{pem,key}`. The one place the paths are made
/// ([`crate::GatewaySection::tls_files`], [`issue`]).
pub fn files(data_dir: &Path) -> (PathBuf, PathBuf) {
    let dir = data_dir.join(DIR);
    (
        dir.join(format!("{STEM}.pem")),
        dir.join(format!("{STEM}.key")),
    )
}

/// The names the gateway's certificate carries: `<hostname>.local`, `wyrm-<site>.local`
/// (the host name the DNS-SD announce gives) and the listen address, or every usable
/// address in `addrs` when the gateway listens on an unspecified address. Loopback,
/// unspecified, multicast and link-local IPv6 addresses of `addrs` are left out. The
/// host name is cut at its first dot and made a DNS label. Sorted, no duplicates.
pub fn names(site: &str, hostname: &str, listen: SocketAddr, addrs: &[IpAddr]) -> Vec<String> {
    let mut out = BTreeSet::new();
    let host = host_label(hostname.split('.').next().unwrap_or_default());
    let host = host.trim_matches('-');
    if !host.is_empty() {
        out.insert(format!("{host}.local"));
    }
    out.insert(format!("wyrm-{}.local", host_label(site)));
    if listen.ip().is_unspecified() {
        out.extend(addrs.iter().filter(|a| usable(a)).map(IpAddr::to_string));
    } else {
        out.insert(listen.ip().to_string());
    }
    out.into_iter().collect()
}

/// An address a client off this host may reach the gateway on.
fn usable(a: &IpAddr) -> bool {
    match a {
        IpAddr::V4(v4) => !(v4.is_loopback() || v4.is_unspecified() || v4.is_multicast()),
        // fe80::/10: valid on one link only, never in a certificate
        IpAddr::V6(v6) => {
            !(v6.is_loopback()
                || v6.is_unspecified()
                || v6.is_multicast()
                || v6.is_unicast_link_local())
        }
    }
}

/// The addresses of this host a client may reach the gateway on: IPv4 and IPv6, never
/// loopback, unspecified, multicast or link-local IPv6, and on Linux never an IPv6
/// address that is temporary (RFC 8981 privacy), deprecated, tentative or failed its
/// duplicate check ([`unstable_v6`]): a privacy address changes every day or so, and each
/// one in the certificate would issue it again. Empty when the interfaces cannot be read:
/// the certificate then names the host names only.
pub fn host_addrs() -> Vec<IpAddr> {
    match if_addrs::get_if_addrs() {
        Ok(list) => {
            let unstable = unstable_v6();
            list.iter()
                .map(if_addrs::Interface::ip)
                .filter(usable)
                .filter(|a| !matches!(a, IpAddr::V6(v6) if unstable.contains(v6)))
                .collect()
        }
        Err(e) => {
            tracing::warn!(error = %e, "gateway certificate: the host's addresses cannot be read");
            Vec::new()
        }
    }
}

/// The IPv6 address flags of `/proc/net/if_inet6` (its fifth column, the low byte of the
/// kernel's `IFA_F_*`) that keep an address out of the certificate: `TEMPORARY` 0x01,
/// `DADFAILED` 0x08, `DEPRECATED` 0x20, `TENTATIVE` 0x40.
#[cfg(any(target_os = "linux", test))]
const UNSTABLE_V6_FLAGS: u8 = 0x01 | 0x08 | 0x20 | 0x40;

/// The IPv6 addresses of this host that are temporary, deprecated, tentative or failed
/// their duplicate check. Linux only (`/proc/net/if_inet6`); `if-addrs` gives no address
/// flags, so elsewhere (macOS, BSD) the set is empty and every global address is named.
/// A file that cannot be read gives an empty set too.
fn unstable_v6() -> BTreeSet<std::net::Ipv6Addr> {
    #[cfg(target_os = "linux")]
    {
        let Ok(text) = std::fs::read_to_string("/proc/net/if_inet6") else {
            return BTreeSet::new();
        };
        unstable_in(&text)
    }
    #[cfg(not(target_os = "linux"))]
    {
        BTreeSet::new()
    }
}

/// [`unstable_v6`] of the text of `/proc/net/if_inet6`: per line the address as 32 hex
/// digits, the interface index, the prefix length, the scope and the flags (hex), then the
/// interface name. A line that does not read so is left out.
#[cfg(any(target_os = "linux", test))]
fn unstable_in(text: &str) -> BTreeSet<std::net::Ipv6Addr> {
    text.lines()
        .filter_map(|line| {
            let mut cols = line.split_whitespace();
            let addr = wyrm_core::hex::decode_array::<16>(cols.next()?)?;
            let [flags] = wyrm_core::hex::decode_array::<1>(cols.nth(3)?)?;
            (flags & UNSTABLE_V6_FLAGS != 0).then(|| std::net::Ipv6Addr::from(addr))
        })
        .collect()
}

/// This host's name, `None` where it cannot be read or is not UTF-8.
pub fn hostname() -> Option<String> {
    #[cfg(unix)]
    {
        let u = rustix::system::uname();
        let name = u.nodename().to_str().ok()?.trim();
        (!name.is_empty()).then(|| name.to_owned())
    }
    #[cfg(not(unix))]
    {
        None
    }
}

/// The names for `cfg`'s gateway on this host as it is now: [`names`] of [`hostname`]
/// (else `wyrm-<site>`) and [`host_addrs`].
pub fn names_now(cfg: &Config, listen: SocketAddr) -> Vec<String> {
    names_from(cfg, listen, &host_addrs)
}

/// [`names_now`] with the addresses from `addrs` (read only for an unspecified listen).
fn names_from(cfg: &Config, listen: SocketAddr, addrs: &dyn Fn() -> Vec<IpAddr>) -> Vec<String> {
    let host = hostname().unwrap_or_else(|| format!("wyrm-{}", cfg.site));
    let addrs = if listen.ip().is_unspecified() {
        addrs()
    } else {
        Vec::new()
    };
    names(&cfg.site, &host, listen, &addrs)
}

/// The site CA could not give the gateway its certificate.
#[derive(Debug, thiserror::Error)]
pub enum GatewayTlsError {
    #[error("gateway.tls site_ca: the site CA in {dir}: {source}")]
    Ca {
        dir: PathBuf,
        #[source]
        source: wyrm_admin::secret::Error,
    },
    #[error("gateway.tls site_ca: the certificate in {dir}: {source}")]
    Issue {
        dir: PathBuf,
        #[source]
        source: wyrm_admin::secret::Error,
    },
    #[error("gateway.tls site_ca: {path}: {source}")]
    Read {
        path: PathBuf,
        #[source]
        source: std::io::Error,
    },
}

/// Issue the gateway's certificate from the site CA (`data_dir/pki`, made on the first
/// start) into [`files`]: CN `gateway:<site>`, server auth, `names` as its subject
/// alternative names. A certificate there for exactly these names with more than 30 days
/// left is kept as it is; one that names more (an address the host lost) is issued again.
/// Returns the certificate and key paths.
pub fn issue(cfg: &Config, names: &[String]) -> Result<(PathBuf, PathBuf), GatewayTlsError> {
    let pki_dir = cfg.data_dir.join("pki");
    let pki = Pki::open_or_create(&pki_dir).map_err(|source| GatewayTlsError::Ca {
        dir: pki_dir,
        source,
    })?;
    let out = cfg.data_dir.join(DIR);
    let issued = pki
        .issue_exact(&format!("gateway:{}", cfg.site), names, true, &out, STEM)
        .map_err(|source| GatewayTlsError::Issue { dir: out, source })?;
    Ok((issued.cert, issued.key))
}

/// Follow the host's addresses while the gateway serves (`gateway.tls: "site_ca"` only;
/// `wyrmd` runs it in the gateway's serve task, so it ends with it): every `every` the
/// names are made again ([`names_now`]) and, when they differ from the names of the
/// certificate the gateway serves or that certificate has less than 30 days left, a
/// certificate is issued for them ([`issue`]) and served from the next connection on
/// ([`Gateway::reload_tls`]). The issue is awaited before the next check. A failure is
/// logged and tried again at the next check. Never returns.
pub async fn watch(cfg: Arc<Config>, gw: Arc<Gateway>, every: Duration) {
    watch_with(cfg, &gw, every, host_addrs).await;
}

/// [`watch`] with the host's addresses from `addrs` (tests give their own).
async fn watch_with(
    cfg: Arc<Config>,
    gw: &Gateway,
    every: Duration,
    addrs: impl Fn() -> Vec<IpAddr>,
) {
    let Some(listen) = cfg.gateway.as_ref().map(|g| g.listen) else {
        return std::future::pending().await;
    };
    let mut tick = tokio::time::interval(every);
    tick.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Delay);
    loop {
        tick.tick().await;
        let names = names_from(&cfg, listen, &addrs);
        let served: BTreeSet<String> = gw.tls_names().into_iter().collect();
        // security review D-1: renewed with less than 30 days left, as at a start
        let due = gw.tls_not_after().is_none_or(|t| {
            t.saturating_sub(wyrm_core::clock::now_s_signed()) < wyrm_admin::secret::RENEW_BEFORE_S
        });
        if !due && names.iter().cloned().collect::<BTreeSet<_>>() == served {
            continue;
        }
        let job = {
            let (cfg, names) = (cfg.clone(), names.clone());
            // key generation and fsync: off the runtime's threads
            tokio::task::spawn_blocking(move || issue_and_read(&cfg, &names))
        };
        let pair = match job.await {
            Ok(Ok(pair)) => pair,
            Ok(Err(e)) => {
                tracing::warn!(error = %e, "gateway: the certificate for the new names");
                continue;
            }
            Err(e) => {
                tracing::warn!(error = %e, "gateway: the certificate task ended");
                continue;
            }
        };
        let (cert, mut key) = pair;
        match gw.reload_tls(cert, std::mem::take(&mut *key)) {
            Ok(()) => tracing::info!(
                ?names,
                "gateway: certificate issued for {} names",
                names.len()
            ),
            Err(e) => tracing::warn!(error = %e, "gateway: the new certificate is not served"),
        }
    }
}

/// [`issue`] and read the certificate and key it gives (PEM).
fn issue_and_read(
    cfg: &Config,
    names: &[String],
) -> Result<(Vec<u8>, Zeroizing<Vec<u8>>), GatewayTlsError> {
    let (cert, key) = issue(cfg, names)?;
    let read = |path: PathBuf| {
        std::fs::read(&path).map_err(|source| GatewayTlsError::Read { path, source })
    };
    Ok((read(cert)?, Zeroizing::new(read(key)?)))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn ips(list: &[&str]) -> Vec<IpAddr> {
        list.iter().map(|a| a.parse().unwrap()).collect()
    }

    #[test]
    fn names_of_an_unspecified_listen() {
        let addrs = ips(&["10.0.0.5", "fe80::1", "2001:db8::5"]);
        assert_eq!(
            names("plant", "bpi", "0.0.0.0:8445".parse().unwrap(), &addrs),
            ["10.0.0.5", "2001:db8::5", "bpi.local", "wyrm-plant.local"]
        );
    }

    #[test]
    fn names_of_a_bound_listen() {
        let addrs = ips(&["10.0.0.5", "fe80::1", "2001:db8::5"]);
        assert_eq!(
            names("plant", "bpi", "10.0.0.5:8445".parse().unwrap(), &addrs),
            ["10.0.0.5", "bpi.local", "wyrm-plant.local"]
        );
    }

    /// A host name with a domain (macOS gives `Name.local`) or characters a DNS label
    /// has not is cut and folded as the announce folds the site; loopback and an
    /// unspecified address never go into the certificate.
    #[test]
    fn names_are_dns_labels() {
        let addrs = ips(&["127.0.0.1", "::1", "0.0.0.0", "ff02::1", "fd00::7"]);
        assert_eq!(
            names(
                "Plant_1",
                "My_BPI.lan",
                "[::]:8445".parse().unwrap(),
                &addrs
            ),
            ["fd00::7", "my-bpi.local", "wyrm-plant-1.local"]
        );
        assert_eq!(
            names("plant", "", "127.0.0.1:0".parse().unwrap(), &[]),
            ["127.0.0.1", "wyrm-plant.local"]
        );
    }

    /// The lines of `/proc/net/if_inet6`: a stable global address (0x00), a permanent one
    /// (0x80), a privacy address (0x01), a deprecated one (0x20), a tentative one (0x40)
    /// and a broken line; only the four unstable ones are found.
    #[test]
    fn unstable_v6_addresses_are_read_from_their_flags() {
        let text = "\
20010db8000000000000000000000005 02 40 00 00     eth0
20010db8000000000000000000000006 02 40 00 80     eth0
20010db800000000a1b2c3d4e5f60718 02 40 00 01     eth0
20010db8000000000000000000000020 02 40 00 20     eth0
fd000000000000000000000000000040 02 40 00 40     eth0
fd000000000000000000000000000008 02 40 00 88     eth0
not an address line
fe800000000000000a0027fffe4e4c7b 02 40 20 80     eth0
";
        let found: Vec<String> = unstable_in(text).iter().map(|a| a.to_string()).collect();
        assert_eq!(
            found,
            [
                "2001:db8::20",
                "2001:db8::a1b2:c3d4:e5f6:718",
                "fd00::8",
                "fd00::40"
            ]
        );
    }

    /// A zenoh session that reaches nothing (the gateway's serve needs one).
    async fn isolated_session() -> zenoh::Session {
        let mut zc = zenoh::Config::default();
        for (k, v) in [
            ("mode", r#""peer""#),
            ("listen/endpoints", "[]"),
            ("connect/endpoints", "[]"),
            ("scouting/multicast/enabled", "false"),
            ("scouting/gossip/enabled", "false"),
        ] {
            zc.insert_json5(k, v).unwrap();
        }
        zenoh::open(zc).await.unwrap()
    }

    /// The names of the certificate a new TLS connection to `port` on loopback is served,
    /// checked against the site CA in `data_dir` for the name `wyrm-plant.local`.
    async fn served_names(port: u16, data_dir: &Path) -> Vec<String> {
        let der = served_cert(port, data_dir).await;
        let (_, cert) = x509_parser::parse_x509_certificate(&der).unwrap();
        let san = cert.subject_alternative_name().unwrap().unwrap();
        san.value
            .general_names
            .iter()
            .map(|g| match g {
                x509_parser::extensions::GeneralName::DNSName(d) => (*d).to_owned(),
                x509_parser::extensions::GeneralName::IPAddress(b) => {
                    IpAddr::from(<[u8; 4]>::try_from(*b).unwrap()).to_string()
                }
                other => panic!("{other:?}"),
            })
            .collect()
    }

    /// The DER of the certificate a new TLS connection to `port` on loopback is served,
    /// checked against the site CA in `data_dir` for the name `wyrm-plant.local`.
    async fn served_cert(port: u16, data_dir: &Path) -> Vec<u8> {
        use rustls_pki_types::pem::PemObject;
        let ca =
            rustls_pki_types::CertificateDer::from_pem_file(data_dir.join("pki/ca.pem")).unwrap();
        let mut roots = rustls::RootCertStore::empty();
        roots.add(ca).unwrap();
        let client = rustls::ClientConfig::builder_with_provider(Arc::new(
            rustls::crypto::ring::default_provider(),
        ))
        .with_safe_default_protocol_versions()
        .unwrap()
        .with_root_certificates(roots)
        .with_no_client_auth();
        let tcp = tokio::net::TcpStream::connect(("127.0.0.1", port))
            .await
            .unwrap();
        let name = rustls_pki_types::ServerName::try_from("wyrm-plant.local").unwrap();
        let tls = tokio_rustls::TlsConnector::from(Arc::new(client))
            .connect(name, tcp)
            .await
            .unwrap();
        tls.get_ref().1.peer_certificates().unwrap()[0].to_vec()
    }

    /// Wait (≤ 10 s) until `ok` holds.
    async fn until(what: &str, mut ok: impl FnMut() -> bool) {
        let end = tokio::time::Instant::now() + Duration::from_secs(10);
        while !ok() {
            assert!(tokio::time::Instant::now() < end, "never: {what}");
            tokio::time::sleep(Duration::from_millis(20)).await;
        }
    }

    /// Review focus 4: an address that comes late (DHCP after the start) is in the
    /// certificate the gateway serves within one check, without a restart; one the host
    /// loses leaves it.
    #[tokio::test(flavor = "multi_thread")]
    async fn certificate_follows_the_addresses() {
        use std::sync::atomic::{AtomicUsize, Ordering};
        let dir = std::env::temp_dir().join(format!("wyrmd-gwtls-follow-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        let data = dir.join("data");
        let cfg = Config::from_json5(&format!(
            r#"{{ site: "plant", data_dir: {data:?},
                  gateway: {{ listen: "0.0.0.0:0", tls: "site_ca" }} }}"#
        ))
        .unwrap();
        let gw = crate::open_gateway(&cfg, cfg.gateway.as_ref().unwrap(), false).unwrap();
        let session = isolated_session().await;
        let (stop, rx) = tokio::sync::oneshot::channel::<()>();
        let server = tokio::spawn(gw.clone().serve(session, async {
            let _ = rx.await;
        }));
        let port = gw.local_addr().await.port();

        // the address source: none at first (DHCP not yet), then 10.0.0.7, then none again
        let step = Arc::new(AtomicUsize::new(0));
        let calls = Arc::new(AtomicUsize::new(0));
        let addrs = {
            let (step, calls) = (step.clone(), calls.clone());
            move || {
                calls.fetch_add(1, Ordering::SeqCst);
                match step.load(Ordering::SeqCst) {
                    1 => vec!["10.0.0.7".parse().unwrap()],
                    _ => Vec::new(),
                }
            }
        };
        let watch = {
            let (cfg, gw) = (Arc::new(cfg.clone()), gw.clone());
            tokio::spawn(async move {
                watch_with(cfg, &gw, Duration::from_millis(20), addrs).await;
            })
        };
        let no_ip = |names: &[String]| names.iter().all(|n| n.parse::<IpAddr>().is_err());
        until("a check without addresses", || {
            calls.load(Ordering::SeqCst) >= 2 && no_ip(&gw.tls_names())
        })
        .await;
        let first = served_names(port, &data).await;
        assert!(no_ip(&first), "{first:?}");
        assert!(first.contains(&"wyrm-plant.local".to_owned()));

        step.store(1, Ordering::SeqCst);
        until("the new address", || {
            gw.tls_names().contains(&"10.0.0.7".to_owned())
        })
        .await;
        let second = served_names(port, &data).await;
        assert!(second.contains(&"10.0.0.7".to_owned()), "{second:?}");
        assert_eq!(second, gw.tls_names(), "served and told the same names");
        let file = std::fs::read(files(&data).0).unwrap();
        assert!(String::from_utf8_lossy(&file).contains("BEGIN CERTIFICATE"));

        // the address is lost: a certificate without it (never one that still names it)
        step.store(2, Ordering::SeqCst);
        until("the address lost", || no_ip(&gw.tls_names())).await;
        assert!(no_ip(&served_names(port, &data).await));

        watch.abort();
        let _ = stop.send(());
        tokio::time::timeout(Duration::from_secs(10), server)
            .await
            .unwrap()
            .unwrap()
            .unwrap();
        let _ = std::fs::remove_dir_all(&dir);
    }

    /// Security review D-1: a certificate in force with less than 30 days left is issued
    /// again while the gateway serves, its names unchanged (a board that runs for a year
    /// without a restart). The due certificate comes from `Pki::issue_lasting` with 10 days.
    #[tokio::test(flavor = "multi_thread")]
    async fn a_due_certificate_is_renewed() {
        use wyrm_admin::secret::{cert_due, RENEW_BEFORE_S};
        let dir = std::env::temp_dir().join(format!("wyrmd-gwtls-renew-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        let data = dir.join("data");
        let cfg = Config::from_json5(&format!(
            r#"{{ site: "plant", data_dir: {data:?},
                  gateway: {{ listen: "127.0.0.1:0", tls: "site_ca" }} }}"#
        ))
        .unwrap();
        let gw = crate::open_gateway(&cfg, cfg.gateway.as_ref().unwrap(), false).unwrap();
        let (stop, rx) = tokio::sync::oneshot::channel::<()>();
        let server = tokio::spawn(gw.clone().serve(isolated_session().await, async {
            let _ = rx.await;
        }));
        let port = gw.local_addr().await.port();
        let names = gw.tls_names();

        // a year on: the certificate in force and its files have 10 days left
        let (cert, key) = files(&data);
        std::fs::remove_file(&cert).unwrap();
        std::fs::remove_file(&key).unwrap();
        Pki::open_or_create(&data.join("pki"))
            .unwrap()
            .issue_lasting("gateway:plant", &names, true, &data.join(DIR), STEM, 10)
            .unwrap();
        gw.reload_tls(std::fs::read(&cert).unwrap(), std::fs::read(&key).unwrap())
            .unwrap();
        let now = wyrm_core::clock::now_s_signed();
        assert!(gw.tls_not_after().unwrap() - now < RENEW_BEFORE_S);

        let watch = {
            let (cfg, gw) = (Arc::new(cfg.clone()), gw.clone());
            tokio::spawn(async move {
                watch_with(cfg, &gw, Duration::from_millis(20), Vec::new).await;
            })
        };
        until("a renewed certificate", || {
            gw.tls_not_after().is_some_and(|t| t - now > 300 * 86_400)
        })
        .await;
        assert_eq!(gw.tls_names(), names, "the same names");
        let der = served_cert(port, &data).await;
        let (_, c) = x509_parser::parse_x509_certificate(&der).unwrap();
        assert_eq!(Some(c.validity().not_after.timestamp()), gw.tls_not_after());
        assert!(!cert_due(&std::fs::read_to_string(&cert).unwrap()));

        watch.abort();
        let _ = stop.send(());
        tokio::time::timeout(Duration::from_secs(10), server)
            .await
            .unwrap()
            .unwrap()
            .unwrap();
        let _ = std::fs::remove_dir_all(&dir);
    }

    /// `wyrmd user …` opens the gateway without bootstrap: it reads the certificate a
    /// running broker owns and never issues one in its place (the broker's watch would race
    /// it from another process); it issues only when there is none.
    #[test]
    fn a_user_command_leaves_the_certificate_alone() {
        let dir = std::env::temp_dir().join(format!("wyrmd-gwtls-user-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        let data = dir.join("data");
        let cfg = Config::from_json5(&format!(
            r#"{{ site: "plant", data_dir: {data:?},
                  gateway: {{ listen: "127.0.0.1:0", tls: "site_ca" }} }}"#
        ))
        .unwrap();
        // names other than the ones of this host now: a bootstrap would issue again
        let (cert, key) = issue(&cfg, &["elsewhere.local".to_owned()]).unwrap();
        let (pem, key_pem) = (std::fs::read(&cert).unwrap(), std::fs::read(&key).unwrap());
        let gw = crate::open_gateway(&cfg, cfg.gateway.as_ref().unwrap(), false).unwrap();
        assert_eq!(gw.tls_names(), ["elsewhere.local"]);
        drop(gw);
        assert_eq!(std::fs::read(&cert).unwrap(), pem, "not issued again");
        assert_eq!(std::fs::read(&key).unwrap(), key_pem);
        // nothing there: issued, as the gateway cannot open without it
        std::fs::remove_file(&key).unwrap();
        let gw = crate::open_gateway(&cfg, cfg.gateway.as_ref().unwrap(), false).unwrap();
        assert!(gw.tls_names().contains(&"wyrm-plant.local".to_owned()));
        drop(gw);
        assert_ne!(std::fs::read(&cert).unwrap(), pem);
        let _ = std::fs::remove_dir_all(&dir);
    }

    /// The certificate from the site CA: kept while its names stay, issued again when
    /// they change; one CA all along.
    #[test]
    fn issue_keeps_the_certificate_while_its_names_stay() {
        let dir = std::env::temp_dir().join(format!("wyrmd-gwtls-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        let cfg = Config::from_json5(&format!(
            r#"{{ site: "plant", data_dir: {:?},
                  gateway: {{ listen: "127.0.0.1:0", tls: "site_ca" }} }}"#,
            dir.join("data")
        ))
        .unwrap();
        let first = ["127.0.0.1".to_owned(), "wyrm-plant.local".to_owned()];
        let (cert, key) = issue(&cfg, &first).unwrap();
        assert_eq!(cert, dir.join("data/gateway/tls.pem"));
        assert_eq!(key, dir.join("data/gateway/tls.key"));
        let ca = std::fs::read(dir.join("data/pki/ca.pem")).unwrap();
        let pem = std::fs::read(&cert).unwrap();
        issue(&cfg, &first).unwrap();
        assert_eq!(std::fs::read(&cert).unwrap(), pem, "same names: kept");
        let moved = ["10.0.0.9".to_owned(), "wyrm-plant.local".to_owned()];
        issue(&cfg, &moved).unwrap();
        let again = std::fs::read(&cert).unwrap();
        assert_ne!(again, pem, "a new address: issued again");
        assert_eq!(std::fs::read(dir.join("data/pki/ca.pem")).unwrap(), ca);
        let (_, block) = x509_parser::pem::parse_x509_pem(&again).unwrap();
        let c = block.parse_x509().unwrap();
        let cn = c.subject().iter_common_name().next().unwrap();
        assert_eq!(cn.as_str().unwrap(), "gateway:plant");
        let _ = std::fs::remove_dir_all(&dir);
    }
}
