//! The gateway's certificate from the site CA (`gateway.tls: "site_ca"`, ADR 0051 §3).
//!
//! At each start the broker asks its site CA (`data_dir/pki`) for a server certificate
//! with CN `gateway:<site>` in `data_dir/gateway/tls.{pem,key}`. The CA keeps the one there
//! while it names the same names and has time left, so a restart on the same host serves
//! the same certificate and a client that pinned the CA needs nothing new.

use std::collections::BTreeSet;
use std::net::{IpAddr, SocketAddr};
use std::path::PathBuf;

use wyrm_admin::secret::Pki;

use crate::announce::host_label;
use crate::Config;

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
/// loopback, unspecified, multicast or link-local IPv6. Empty when the interfaces cannot
/// be read: the certificate then names the host names only.
pub fn host_addrs() -> Vec<IpAddr> {
    match if_addrs::get_if_addrs() {
        Ok(list) => list
            .iter()
            .map(if_addrs::Interface::ip)
            .filter(usable)
            .collect(),
        Err(e) => {
            tracing::warn!(error = %e, "gateway certificate: the host's addresses cannot be read");
            Vec::new()
        }
    }
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
    let host = hostname().unwrap_or_else(|| format!("wyrm-{}", cfg.site));
    let addrs = if listen.ip().is_unspecified() {
        host_addrs()
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
}

/// Issue the gateway's certificate from the site CA (`data_dir/pki`, made on the first
/// start) into `data_dir/gateway/tls.{pem,key}`: CN `gateway:<site>`, server auth,
/// `names` as its subject alternative names. A certificate there for the same names with
/// time left is kept as it is. Returns the certificate and key paths.
pub fn issue(cfg: &Config, names: &[String]) -> Result<(PathBuf, PathBuf), GatewayTlsError> {
    let pki_dir = cfg.data_dir.join("pki");
    let pki = Pki::open_or_create(&pki_dir).map_err(|source| GatewayTlsError::Ca {
        dir: pki_dir,
        source,
    })?;
    let out = cfg.data_dir.join("gateway");
    let files = pki
        .issue(&format!("gateway:{}", cfg.site), names, true, &out, "tls")
        .map_err(|source| GatewayTlsError::Issue { dir: out, source })?;
    Ok((files.cert, files.key))
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
