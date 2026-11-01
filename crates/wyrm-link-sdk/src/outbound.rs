//! Where a link's own HTTP, TLS and TCP clients may connect (security review LNK-1, FS-4,
//! AI-3, ADR 0031). A `config` user picks the URL; these addresses are never reached, whatever
//! the URL or what DNS answers for its host:
//!
//! - link-local (`169.254.0.0/16`, `fe80::/10`): cloud instance metadata lives there and hands
//!   out the host's credentials;
//! - cloud metadata in other ranges (`fd00:ec2::254`);
//! - unspecified (`0.0.0.0/8`, `::`), multicast and broadcast.
//!
//! Loopback and private ranges stay reachable: devices, simulators and local stores live
//! there. The check runs on the resolved address that is connected, so a name cannot pass it
//! and then point elsewhere.

use std::net::{IpAddr, SocketAddr};

/// `ip` is one a link may connect to.
pub fn reachable(ip: IpAddr) -> bool {
    let ip = match ip {
        IpAddr::V6(a) => a.to_ipv4_mapped().map_or(ip, IpAddr::V4),
        v4 => v4,
    };
    match ip {
        IpAddr::V4(a) => {
            !(a.is_link_local()
                || a.is_unspecified()
                || a.octets()[0] == 0
                || a.is_multicast()
                || a.is_broadcast())
        }
        IpAddr::V6(a) => {
            let s = a.segments();
            !(a.is_unspecified()
                || a.is_multicast()
                || (s[0] & 0xffc0) == 0xfe80
                || s[..2] == [0xfd00, 0x0ec2])
        }
    }
}

/// Resolve `host:port` and keep the addresses a link may reach; an error names the host when
/// none is left.
pub async fn resolve(host: &str, port: u16) -> Result<Vec<SocketAddr>, String> {
    let all: Vec<SocketAddr> = tokio::net::lookup_host((host, port))
        .await
        .map_err(|e| format!("resolve {host}: {e}"))?
        .collect();
    let ok: Vec<SocketAddr> = all.iter().copied().filter(|a| reachable(a.ip())).collect();
    if ok.is_empty() && !all.is_empty() {
        return Err(format!(
            "{host}: links do not connect to link-local, metadata, multicast or unspecified \
             addresses"
        ));
    }
    Ok(ok)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn metadata_and_link_local_are_never_reached() {
        let ip = |s: &str| s.parse::<IpAddr>().unwrap();
        for bad in [
            "169.254.169.254",
            "169.254.0.1",
            "0.0.0.0",
            "0.1.2.3",
            "224.0.0.1",
            "255.255.255.255",
            "::",
            "fe80::1",
            "ff02::1",
            "fd00:ec2::254",
            "::ffff:169.254.169.254",
        ] {
            assert!(!reachable(ip(bad)), "{bad}");
        }
        for good in [
            "127.0.0.1",
            "10.0.5.7",
            "192.168.1.2",
            "8.8.8.8",
            "::1",
            "fd12::5",
        ] {
            assert!(reachable(ip(good)), "{good}");
        }
    }

    #[tokio::test]
    async fn a_name_that_resolves_only_to_metadata_is_refused() {
        let e = resolve("169.254.169.254", 80).await.unwrap_err();
        assert!(e.contains("link-local"), "{e}");
        assert!(!resolve("127.0.0.1", 80).await.unwrap().is_empty());
    }
}
