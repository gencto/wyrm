//! The gateway announces itself by DNS-SD on the local network (ADR 0050 §2.1): service
//! `_wyrm._tcp`, instance name = site, a TXT record with no users and no secrets. Only the
//! broker that serves (the active one of a standby pair) announces; the announcement stops
//! when it stops (SIGTERM, a step down), with a goodbye packet.
//!
//! Finding a name never means trusting it: the `fp` code is for a person to compare (the
//! Trust screen, `wyrmd ca fingerprint`).

use crate::Config;
use mdns_sd::{IfKind, ServiceDaemon, ServiceInfo};
use std::net::IpAddr;

/// The DNS-SD service type.
pub const SERVICE: &str = "_wyrm._tcp.local.";

/// What one announcement says and where.
#[derive(Debug, Clone, PartialEq)]
pub struct Plan {
    pub instance: String,
    pub port: u16,
    /// `None`: every interface but loopback; else the one address the gateway listens on.
    pub addr: Option<IpAddr>,
    /// Interface names from `gateway.announce.interfaces` (empty: as `addr` says).
    pub interfaces: Vec<String>,
    pub txt: Vec<(String, String)>,
}

/// The TXT record (ADR 0050 §2.1): `v`, `site`, `tls`, `fp` (over TLS, when the CA is
/// known), `role`, `pair` and `up` when there are such.
pub fn txt(
    site: &str,
    tls: bool,
    ca: Option<&[u8]>,
    pair: Option<&str>,
    up: &[String],
) -> Vec<(String, String)> {
    let mut t = vec![
        ("v".to_owned(), env!("CARGO_PKG_VERSION").to_owned()),
        ("site".to_owned(), site.to_owned()),
        ("tls".to_owned(), if tls { "1" } else { "0" }.to_owned()),
    ];
    if let Some(ca) = ca.filter(|_| tls) {
        t.push(("fp".to_owned(), wyrm_gateway::devices::ca_fingerprint(ca)));
    }
    t.push(("role".to_owned(), "active".to_owned()));
    if let Some(p) = pair {
        t.push(("pair".to_owned(), p.to_owned()));
    }
    if !up.is_empty() {
        t.push(("up".to_owned(), up.join(",")));
    }
    t
}

/// The other host of a standby pair as a client reaches its gateway: `announce.pair`, else
/// the host of `standby.peer` with this gateway's port.
pub fn pair_of(cfg: &Config) -> Option<String> {
    let g = cfg.gateway.as_ref()?;
    if let Some(p) = g.announce.as_ref().and_then(|a| a.pair.clone()) {
        return Some(p);
    }
    let peer = &cfg.standby.as_ref()?.peer;
    let hostport = peer.split_once('/').map_or(peer.as_str(), |(_, r)| r);
    let hostport = hostport.split(['#', '?']).next()?;
    let host = match hostport.rsplit_once(':') {
        Some((h, p)) if p.parse::<u16>().is_ok() => h,
        _ => hostport,
    };
    (!host.is_empty()).then(|| format!("{host}:{}", g.listen.port()))
}

/// What to announce, or `None`: no gateway, `announce.enabled: false`, or a gateway on
/// loopback (nothing off this host could reach it).
pub fn plan(cfg: &Config, up: &[String]) -> Option<Plan> {
    let g = cfg.gateway.as_ref()?;
    let enabled = g.announce.as_ref().is_none_or(|a| a.enabled);
    if !enabled || g.listen.ip().is_loopback() {
        return None;
    }
    let ca = crate::gateway_ca(cfg);
    Some(Plan {
        instance: cfg.site.clone(),
        port: g.listen.port(),
        addr: (!g.listen.ip().is_unspecified()).then(|| g.listen.ip()),
        interfaces: g
            .announce
            .as_ref()
            .map(|a| a.interfaces.clone())
            .unwrap_or_default(),
        txt: txt(
            &cfg.site,
            g.tls_cert.is_some(),
            ca.as_deref(),
            pair_of(cfg).as_deref(),
            up,
        ),
    })
}

/// A running announcement; dropping it says goodbye and stops the responder.
pub struct Announcer {
    daemon: ServiceDaemon,
    fullname: String,
}

impl Announcer {
    /// Start announcing `plan`. A failure (no multicast, no interface) is logged: the
    /// broker runs without it.
    pub fn start(plan: &Plan) -> Option<Self> {
        match Self::try_start(plan) {
            Ok(a) => {
                tracing::info!(instance = %plan.instance, port = plan.port, "gateway: announced on the local network");
                Some(a)
            }
            Err(e) => {
                tracing::warn!("gateway: no DNS-SD announce: {e}");
                None
            }
        }
    }

    fn try_start(plan: &Plan) -> Result<Self, mdns_sd::Error> {
        let daemon = ServiceDaemon::new()?;
        daemon.disable_interface(vec![IfKind::LoopbackV4, IfKind::LoopbackV6])?;
        if !plan.interfaces.is_empty() || plan.addr.is_some() {
            daemon.disable_interface(IfKind::All)?;
            for n in &plan.interfaces {
                daemon.enable_interface(IfKind::Name(n.clone()))?;
            }
            if let Some(a) = plan.addr {
                daemon.enable_interface(IfKind::Addr(a))?;
            }
        }
        let host = format!("wyrm-{}.local.", host_label(&plan.instance));
        let props: Vec<(&str, &str)> = plan
            .txt
            .iter()
            .map(|(k, v)| (k.as_str(), v.as_str()))
            .collect();
        let info = match plan.addr {
            Some(a) => ServiceInfo::new(SERVICE, &plan.instance, &host, a, plan.port, &props[..])?,
            None => ServiceInfo::new(SERVICE, &plan.instance, &host, (), plan.port, &props[..])?
                .enable_addr_auto(),
        };
        let fullname = info.get_fullname().to_owned();
        daemon.register(info)?;
        Ok(Self { daemon, fullname })
    }
}

impl Drop for Announcer {
    fn drop(&mut self) {
        if let Ok(rx) = self.daemon.unregister(&self.fullname) {
            let _ = rx.recv_timeout(std::time::Duration::from_secs(1));
        }
        if let Ok(rx) = self.daemon.shutdown() {
            let _ = rx.recv_timeout(std::time::Duration::from_secs(1));
        }
    }
}

/// A DNS label from a site name (`[a-z0-9-]`).
fn host_label(site: &str) -> String {
    site.chars()
        .map(|c| {
            if c.is_ascii_alphanumeric() {
                c.to_ascii_lowercase()
            } else {
                '-'
            }
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn cfg(gateway: &str) -> Config {
        Config::from_json5(&format!(
            r#"{{ site: "plant", data_dir: "/tmp/wyrm-announce-test", insecure_plaintext: true,
                  listen: ["tcp/127.0.0.1:0"], {gateway} }}"#
        ))
        .unwrap()
    }

    /// Consequences: the TXT content, with no user, key or secret in it.
    #[test]
    fn txt_says_what_the_adr_lists() {
        let t = txt(
            "plant",
            true,
            Some(b"ca der"),
            Some("10.0.0.2:8443"),
            &["central".into()],
        );
        let keys: Vec<&str> = t.iter().map(|(k, _)| k.as_str()).collect();
        assert_eq!(keys, ["v", "site", "tls", "fp", "role", "pair", "up"]);
        let get = |k: &str| t.iter().find(|(a, _)| a == k).map(|(_, v)| v.as_str());
        assert_eq!(get("site"), Some("plant"));
        assert_eq!(get("tls"), Some("1"));
        assert_eq!(get("role"), Some("active"));
        assert_eq!(
            get("fp"),
            Some(wyrm_gateway::devices::ca_fingerprint(b"ca der").as_str())
        );
        assert_eq!(get("fp").unwrap().len(), 32);
        // no TLS: no code to compare
        let t = txt("plant", false, Some(b"ca der"), None, &[]);
        let keys: Vec<&str> = t.iter().map(|(k, _)| k.as_str()).collect();
        assert_eq!(keys, ["v", "site", "tls", "role"]);
    }

    /// Consequences: no announce with `enabled: false`, nor for a gateway on loopback; one
    /// for a gateway on the network by default.
    #[test]
    fn announce_follows_the_config() {
        assert_eq!(plan(&cfg(""), &[]), None, "no gateway");
        assert_eq!(
            plan(&cfg(r#"gateway: { listen: "127.0.0.1:8443" }"#), &[]),
            None,
            "loopback"
        );
        let on = r#"gateway: { listen: "0.0.0.0:8443", tls_cert: "/x.pem", tls_key: "/x.key" }"#;
        let p = plan(&cfg(on), &["central".into()]).expect("on by default");
        assert_eq!((p.instance.as_str(), p.port, p.addr), ("plant", 8443, None));
        assert!(p.txt.iter().any(|(k, v)| k == "up" && v == "central"));
        let off = r#"gateway: { listen: "0.0.0.0:8443", tls_cert: "/x.pem", tls_key: "/x.key",
                               announce: { enabled: false } }"#;
        assert_eq!(plan(&cfg(off), &[]), None, "enabled: false");
        let one = r#"gateway: { listen: "10.1.2.3:8443", tls_cert: "/x.pem", tls_key: "/x.key",
                               announce: { interfaces: ["eth1"] } }"#;
        let p = plan(&cfg(one), &[]).unwrap();
        assert_eq!(p.addr, Some("10.1.2.3".parse().unwrap()));
        assert_eq!(p.interfaces, ["eth1"]);
    }

    #[test]
    fn the_pair_comes_from_the_standby_peer() {
        let c = cfg(
            r#"gateway: { listen: "0.0.0.0:8443", tls_cert: "/x.pem", tls_key: "/x.key" },
                       peers: { listen: "quic/0.0.0.0:7448" },
                       standby: { peer: "quic/10.0.0.2:7448", witness: ["10.0.0.9:22"] }"#,
        );
        assert_eq!(pair_of(&c).as_deref(), Some("10.0.0.2:8443"));
        let c = cfg(
            r#"gateway: { listen: "0.0.0.0:8443", tls_cert: "/x.pem", tls_key: "/x.key",
                                  announce: { pair: "gw-b.plant.example:9443" } }"#,
        );
        assert_eq!(pair_of(&c).as_deref(), Some("gw-b.plant.example:9443"));
        assert_eq!(host_label("Plant_1"), "plant-1");
    }
}
