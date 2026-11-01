//! Network allowlist of a link (ADR 0012), shared by every host. `core::net` only, so it builds for wasm32.

use core::net::IpAddr;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
struct Allow {
    net: IpAddr,
    prefix: u8,
    port: u16,
}

/// A host name entry: `db.example.com:5432`, or `*.example.com:443` for
/// every name below `example.com` (ADR 0026).
#[derive(Debug, Clone, PartialEq, Eq)]
struct NameAllow {
    /// Lowercase, without the `*.` of a wildcard.
    name: String,
    wildcard: bool,
    port: u16,
}

impl NameAllow {
    fn matches(&self, host: &str, port: u16) -> bool {
        if self.port != port {
            return false;
        }
        let host = host.trim_end_matches('.').to_ascii_lowercase();
        if self.wildcard {
            // `name` keeps its leading dot: `a.example.com`, never `example.com`
            host.strip_suffix(self.name.as_str())
                .is_some_and(|rest| !rest.is_empty())
        } else {
            host == self.name
        }
    }
}

/// Where a `driver` instance may connect: `<ip>/<prefix>:<port>` entries
/// (ADR 0012) and host names for TLS connections (`<name>:<port>`,
/// `*.<domain>:<port>`, ADR 0026). Empty: no network.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct NetPolicy {
    ips: Vec<Allow>,
    names: Vec<NameAllow>,
}

/// A DNS name: labels of letters, digits and `-`, 1–63 bytes each, 253 in all.
fn host_name(s: &str) -> bool {
    !s.is_empty()
        && s.len() <= 253
        && s.split('.').all(|l| {
            !l.is_empty()
                && l.len() <= 63
                && !l.starts_with('-')
                && !l.ends_with('-')
                && l.bytes().all(|b| b.is_ascii_alphanumeric() || b == b'-')
        })
        // not an IPv4 literal written as a name
        && !s.split('.').all(|l| l.bytes().all(|b| b.is_ascii_digit()))
}

/// An IPv4-mapped IPv6 address is its IPv4 address.
fn plain(ip: IpAddr) -> IpAddr {
    match ip {
        IpAddr::V6(a) => a.to_ipv4_mapped().map_or(ip, IpAddr::V4),
        v4 => v4,
    }
}

/// The special class of an address and the prefix length of that class:
/// loopback 1, link-local (and IPv6 site-local) 2, multicast 3, broadcast
/// 4, "this network" 5, IPv6 that carries an IPv4 address (IPv4-compatible,
/// NAT64, 6to4) 6, cloud metadata 7. Everything else, private ranges
/// included, is ordinary.
fn class(ip: IpAddr) -> Option<(u8, u8)> {
    match ip {
        IpAddr::V4(a) if a.is_loopback() => Some((1, 8)),
        IpAddr::V4(a) if a.is_link_local() => Some((2, 16)),
        IpAddr::V4(a) if a.is_multicast() => Some((3, 4)),
        IpAddr::V4(a) if a.is_broadcast() => Some((4, 32)),
        IpAddr::V4(a) if a.octets()[0] == 0 => Some((5, 8)),
        IpAddr::V6(a) => {
            let s = a.segments();
            if a.is_loopback() {
                Some((1, 128))
            } else if a.is_unspecified() {
                Some((5, 128))
            } else if (s[0] & 0xffc0) == 0xfe80 || (s[0] & 0xffc0) == 0xfec0 {
                Some((2, 10))
            } else if a.is_multicast() {
                Some((3, 8))
            } else if s[..6] == [0; 6] || s[..6] == [0x64, 0xff9b, 0, 0, 0, 0] {
                Some((6, 96)) // ::a.b.c.d, NAT64
            } else if s[..3] == [0x64, 0xff9b, 1] {
                Some((6, 48)) // local-use NAT64
            } else if s[0] == 0x2002 {
                Some((6, 16)) // 6to4
            } else if s[..2] == [0xfd00, 0x0ec2] {
                Some((7, 32)) // cloud metadata
            } else {
                None
            }
        }
        _ => None,
    }
}

/// A private address: RFC 1918, shared address space (`100.64.0.0/10`), IPv6 unique local
/// (`fc00::/7`). An IP entry reaches it; a name entry does not (security review NET-1).
fn private(ip: IpAddr) -> bool {
    match ip {
        IpAddr::V4(a) => {
            let o = a.octets();
            a.is_private() || (o[0] == 100 && (o[1] & 0xc0) == 64)
        }
        IpAddr::V6(a) => (a.segments()[0] & 0xfe00) == 0xfc00,
    }
}

fn bits(ip: IpAddr) -> (u128, u8) {
    match ip {
        IpAddr::V4(a) => (u32::from(a) as u128, 32),
        IpAddr::V6(a) => (u128::from(a), 128),
    }
}

impl NetPolicy {
    /// Entries separated by commas, spaces or new lines:
    /// `10.0.5.0/24:502`, `192.168.1.20:502` (one address), `[fd00::]/64:502`,
    /// and host names for TLS: `db.example.com:5432`, `*.example.com:443`.
    pub fn parse(text: &str) -> Result<Self, String> {
        let mut out = Vec::new();
        let mut names = Vec::new();
        for e in text
            .split([',', ' ', '\n', '\r', '\t'])
            .filter(|e| !e.is_empty())
        {
            let (addr, port) = e
                .rsplit_once(':')
                .ok_or_else(|| format!("{e}: <ip>[/<prefix>]:<port> or <host>:<port>"))?;
            let port: u16 = port.parse().map_err(|_| format!("{e}: bad port"))?;
            let (wildcard, name) = match addr.strip_prefix("*.") {
                Some(n) => (true, n),
                None => (false, addr),
            };
            if host_name(name) {
                names.push(NameAllow {
                    name: if wildcard {
                        format!(".{}", name.to_ascii_lowercase())
                    } else {
                        name.to_ascii_lowercase()
                    },
                    wildcard,
                    port,
                });
                continue;
            }
            if wildcard {
                return Err(format!("{e}: *. goes before a host name"));
            }
            let (ip, prefix) = match addr.split_once('/') {
                Some((ip, p)) => (ip, Some(p)),
                None => (addr, None),
            };
            let ip: IpAddr = ip
                .trim_start_matches('[')
                .trim_end_matches(']')
                .parse()
                .map_err(|_| format!("{e}: an IP literal or a host name"))?;
            let ip = plain(ip);
            let max = bits(ip).1;
            let prefix = match prefix {
                Some(p) => p
                    .trim_end_matches(']')
                    .parse::<u8>()
                    .ok()
                    .filter(|p| *p <= max)
                    .ok_or_else(|| format!("{e}: bad prefix"))?,
                None => max,
            };
            out.push(Allow {
                net: ip,
                prefix,
                port,
            });
        }
        Ok(Self { ips: out, names })
    }

    pub fn is_empty(&self) -> bool {
        self.ips.is_empty() && self.names.is_empty()
    }

    /// `host` (a name the link asked for), resolved to `ip`, may be reached
    /// on `port` (plain TCP or TLS): `ip` is inside an IP entry, or `host`
    /// matches a name entry and `ip` is a public address. A name never opens
    /// a special address (loopback, link-local, metadata, …) nor a private
    /// one (RFC 1918, `100.64/10`, `fc00::/7`): a name that resolves there
    /// needs an IP entry for that address, so whoever answers for the name in
    /// DNS cannot point a link at the host or its LAN (security review NET-1).
    pub fn allows_named(&self, host: &str, ip: IpAddr, port: u16) -> bool {
        let ip = plain(ip);
        self.allows(ip, port)
            || (class(ip).is_none()
                && !private(ip)
                && self.names.iter().any(|n| n.matches(host, port)))
    }

    /// `ip:port` is inside an entry. A special address (loopback,
    /// link-local, …) only inside an entry of the same class that is no
    /// wider than the class: `0.0.0.0/0` does not reach `127.0.0.1`.
    pub fn allows(&self, ip: IpAddr, port: u16) -> bool {
        let ip = plain(ip);
        let (a, n) = bits(ip);
        let cls = class(ip);
        self.ips.iter().any(|e| {
            let (b, m) = bits(e.net);
            if n != m || e.port != port {
                return false;
            }
            if let Some((c, len)) = cls {
                if class(e.net).map(|x| x.0) != Some(c) || e.prefix < len {
                    return false;
                }
            }
            let shift = u32::from(n - e.prefix);
            shift >= 128 || (a >> shift) == (b >> shift)
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn net_policy() {
        let p = NetPolicy::parse("10.0.5.0/24:502, 192.168.1.20:1502\n[fd00::]/64:502 127.0.0.1:9")
            .unwrap();
        let ip = |s: &str| s.parse::<core::net::IpAddr>().unwrap();
        assert!(p.allows(ip("10.0.5.77"), 502));
        assert!(!p.allows(ip("10.0.6.1"), 502));
        assert!(!p.allows(ip("10.0.5.77"), 503));
        assert!(p.allows(ip("192.168.1.20"), 1502));
        assert!(!p.allows(ip("192.168.1.21"), 1502));
        assert!(p.allows(ip("fd00::1:2"), 502));
        assert!(p.allows(ip("127.0.0.1"), 9));
        assert!(p.allows(ip("::ffff:10.0.5.1"), 502), "v4-mapped is v4");
        let any = NetPolicy::parse("0.0.0.0/0:502, [::]/0:502").unwrap();
        assert!(any.allows(ip("8.8.8.8"), 502));
        for special in [
            "127.0.0.1",
            "169.254.169.254",
            "0.0.0.0",
            "0.1.2.3",
            "224.0.0.1",
            "::1",
            "fe80::1",
            "fec0::1",
            "::ffff:127.0.0.1",
            "::7f00:1",
            "64:ff9b::7f00:1",
            "64:ff9b:1::7f00:1",
            "2002:7f00:1::1",
            "fd00:ec2::254",
        ] {
            assert!(!any.allows(ip(special), 502), "{special}");
        }
        // private ranges are ordinary: devices live there
        for private in ["10.1.2.3", "192.168.1.5", "172.16.0.9", "fd12::5"] {
            assert!(any.allows(ip(private), 502), "{private}");
        }
        // a special address needs an entry of its class
        let nat64 = NetPolicy::parse("[64:ff9b::]/96:502").unwrap();
        assert!(nat64.allows(ip("64:ff9b::a00:5"), 502));
        for bad in [
            "10.0.0.1",
            "10.0.0.0/33:502",
            "10.0.0.1:99999",
            "*.10.0.0.1:443",
            "bad_name.example:443",
            "-x.example:443",
        ] {
            assert!(NetPolicy::parse(bad).is_err(), "{bad}");
        }
    }

    #[test]
    fn host_names_for_tls() {
        let ip = |s: &str| s.parse::<core::net::IpAddr>().unwrap();
        let p = NetPolicy::parse("DB.example.com:5432, *.influx.cloud:443").unwrap();
        assert!(!p.is_empty());
        // a listed name, resolved to a public address
        assert!(p.allows_named("db.example.com", ip("203.0.113.7"), 5432));
        assert!(p.allows_named("db.example.com.", ip("203.0.113.7"), 5432));
        // a name never opens a private address (review NET-1): DNS could point it at the LAN
        for lan in [
            "10.0.0.7",
            "172.16.4.1",
            "192.168.1.9",
            "100.64.0.1",
            "fd12::5",
            "::ffff:10.0.0.7",
        ] {
            assert!(!p.allows_named("db.example.com", ip(lan), 5432), "{lan}");
        }
        // an IP entry for it does
        let lan = NetPolicy::parse("db.example.com:5432, 10.0.0.0/24:5432").unwrap();
        assert!(lan.allows_named("db.example.com", ip("10.0.0.7"), 5432));
        assert!(!lan.allows_named("db.example.com", ip("10.0.1.7"), 5432));
        assert!(!p.allows_named("db.example.com", ip("203.0.113.7"), 5433));
        assert!(!p.allows_named("other.example.com", ip("203.0.113.7"), 5432));
        // a wildcard covers names below it, not the domain itself
        assert!(p.allows_named("eu.influx.cloud", ip("203.0.113.8"), 443));
        assert!(p.allows_named("a.b.influx.cloud", ip("203.0.113.8"), 443));
        assert!(!p.allows_named("influx.cloud", ip("203.0.113.8"), 443));
        assert!(!p.allows_named("evilinflux.cloud", ip("203.0.113.8"), 443));
        // a name never opens a special address (DNS rebinding)
        for special in ["127.0.0.1", "169.254.169.254", "::1", "fd00:ec2::254"] {
            assert!(
                !p.allows_named("db.example.com", ip(special), 5432),
                "{special}"
            );
        }
        // unless an IP entry of that class allows it
        let local = NetPolicy::parse("localhost:5432, 127.0.0.1:5432").unwrap();
        assert!(local.allows_named("localhost", ip("127.0.0.1"), 5432));
        // an IP entry still works for any name
        let by_ip = NetPolicy::parse("203.0.113.0/24:443").unwrap();
        assert!(by_ip.allows_named("anything.example", ip("203.0.113.9"), 443));
        // a name entry is no IP entry: the address alone, without the name, is not allowed
        assert!(!p.allows(ip("203.0.113.7"), 5432));
    }
}
