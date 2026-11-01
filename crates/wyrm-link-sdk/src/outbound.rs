//! Where a link's own HTTP, TLS and TCP clients may connect (security review LNK-1, FS-4,
//! AI-3, ADR 0031). A `config` user picks the URL; these addresses are never reached, whatever
//! the URL or what DNS answers for its host:
//!
//! - link-local (`169.254.0.0/16`, `fe80::/10`): cloud instance metadata lives there and hands
//!   out the host's credentials;
//! - cloud metadata in other ranges (`fd00:ec2::254`, Alibaba `100.100.100.200`, Azure
//!   `168.63.129.16`, Oracle Classic `192.0.0.192`);
//! - unspecified (`0.0.0.0/8`, `::`), multicast and broadcast.
//!
//! Loopback and private ranges stay reachable: devices, simulators and local stores live
//! there. The check runs on the resolved address that is connected, so a name cannot pass it
//! and then point elsewhere. An IPv6 address that carries an IPv4 one (IPv4-mapped and
//! -compatible, NAT64 `64:ff9b::/96` and `64:ff9b:1::/48`, 6to4 `2002::/16`) is judged by the
//! IPv4 address it carries; so is SIIT `::ffff:0:0/96`, and Teredo `2001::/32` is refused.

use std::net::{IpAddr, Ipv4Addr, Ipv6Addr, SocketAddr};

/// Cloud metadata endpoints outside link-local.
const METADATA_V4: [Ipv4Addr; 3] = [
    Ipv4Addr::new(100, 100, 100, 200),
    Ipv4Addr::new(168, 63, 129, 16),
    Ipv4Addr::new(192, 0, 0, 192),
];

/// The IPv4 address an IPv6 one carries, if it is of a form that carries one (review of
/// 9a366ec: such forms reach the IPv4 address through a translator).
fn embedded_v4(a: Ipv6Addr) -> Option<Ipv4Addr> {
    let s = a.segments();
    let tail = || Ipv4Addr::new((s[6] >> 8) as u8, s[6] as u8, (s[7] >> 8) as u8, s[7] as u8);
    if let Some(v4) = a.to_ipv4_mapped() {
        return Some(v4);
    }
    if s[..6] == [0, 0, 0, 0, 0xffff, 0] {
        return Some(tail()); // IPv4-translated (SIIT) ::ffff:0:a.b.c.d
    }
    if s[..6] == [0; 6] && !a.is_loopback() && !a.is_unspecified() {
        return Some(tail()); // IPv4-compatible ::a.b.c.d
    }
    if s[..6] == [0x64, 0xff9b, 0, 0, 0, 0] {
        return Some(tail()); // NAT64 well-known prefix
    }
    if s[..3] == [0x64, 0xff9b, 1] {
        // RFC 6052 /48: octets 1–2 in bits 48–63, octets 3–4 in bits 72–87 (after the u octet)
        return Some(Ipv4Addr::new(
            (s[3] >> 8) as u8,
            s[3] as u8,
            s[4] as u8,
            (s[5] >> 8) as u8,
        ));
    }
    if s[0] == 0x2002 {
        return Some(Ipv4Addr::new(
            (s[1] >> 8) as u8,
            s[1] as u8,
            (s[2] >> 8) as u8,
            s[2] as u8,
        )); // 6to4
    }
    None
}

/// `ip` is one a link may connect to.
pub fn reachable(ip: IpAddr) -> bool {
    let ip = match ip {
        IpAddr::V6(a) => embedded_v4(a).map_or(ip, IpAddr::V4),
        v4 => v4,
    };
    match ip {
        IpAddr::V4(a) => {
            !(a.is_link_local()
                || a.is_unspecified()
                || a.octets()[0] == 0
                || a.is_multicast()
                || a.is_broadcast()
                || METADATA_V4.contains(&a))
        }
        IpAddr::V6(a) => {
            let s = a.segments();
            !(a.is_unspecified()
                || a.is_multicast()
                || (s[0] & 0xffc0) == 0xfe80
                || s[..2] == [0xfd00, 0x0ec2]
                // Teredo 2001::/32 carries a (masked) IPv4 address of a relay; no link
                // needs it
                || s[..2] == [0x2001, 0])
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
            "100.100.100.200",
            "168.63.129.16",
            "192.0.0.192",
            // IPv6 forms that carry 169.254.169.254
            "::a9fe:a9fe",
            "64:ff9b::a9fe:a9fe",
            "64:ff9b:1:a9fe:a9:fe00::",
            "2002:a9fe:a9fe::1",
            "::ffff:0:a9fe:a9fe",
            "2001:0:4136:e378:8000:63bf:3fff:fdd2",
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
            "64:ff9b::808:808",
            "2002:808:808::1",
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
