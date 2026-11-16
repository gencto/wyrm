//! One parser for the URLs a broker or a link is configured with (review S4):
//! `scheme://host[:port][/path][?query][#fragment]`.
//!
//! Every place that takes an endpoint (an HTTP target, a file store, a history
//! sync target, an uplink, the gateway's origins and public URL, a release
//! channel, a repository) parses it here and then applies its own policy to
//! the typed parts: which schemes, plain HTTP only to loopback, a path or none,
//! a query or none. The parser is strict on what it reads and normalizes
//! nothing it passes on:
//!
//! * the URL is ASCII, without spaces, control characters or `\` anywhere (a
//!   WHATWG parser reads `\` as `/`; two readings of one URL are refused, not
//!   chosen between);
//! * `://` follows the scheme (`[A-Za-z][A-Za-z0-9+.-]*`), and the authority
//!   ends at the first `/`, `?` or `#`;
//! * no user or password before the host (`@` in the authority): a credential
//!   in a URL is shown wherever the URL is;
//! * the host is a name of `[A-Za-z0-9._-]` (at most 253 bytes, kept in lower
//!   case), an IPv4 address, or an IPv6 address in brackets that parses as one
//!   (no zone);
//! * a port is 1 to 5 digits, 1 to 65535; `host:` without one is refused;
//! * path, query and fragment are kept as written (no `..` resolved, no
//!   percent-decoding).
//!
//! Errors name what is wrong and never repeat the URL (a query may hold a
//! token).

use core::fmt;
use std::net::{IpAddr, Ipv4Addr, Ipv6Addr};

/// Longest host name.
const MAX_NAME: usize = 253;

/// Why a URL is refused. The message never holds the URL.
#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
pub enum UrlError {
    #[error("not scheme://host: no scheme")]
    NoScheme,
    #[error("a scheme this place does not take")]
    Scheme,
    #[error("no host")]
    NoHost,
    #[error("no user or password in the URL")]
    Credentials,
    #[error("bad host")]
    Host,
    /// No `]`, or text after it that is no port.
    #[error("bad IPv6 host")]
    Ipv6,
    /// Between the brackets: no IPv6 address.
    #[error("bad IPv6 host: {0}")]
    Ipv6Address(#[source] std::net::AddrParseError),
    #[error("bad port")]
    Port,
    #[error("spaces, control or non-ASCII characters, or `\\`, in the URL")]
    Chars,
}

/// The host of a URL.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Host {
    /// A DNS name, in lower case.
    Name(String),
    Ip(IpAddr),
}

impl Host {
    /// As a name or an address, IPv6 without brackets (what a resolver and TLS take).
    pub fn text(&self) -> String {
        match self {
            Host::Name(n) => n.clone(),
            Host::Ip(ip) => ip.to_string(),
        }
    }

    /// As in a URL or a `Host` header: IPv6 in brackets.
    pub fn url_form(&self) -> String {
        match self {
            Host::Ip(IpAddr::V6(a)) => format!("[{a}]"),
            h => h.text(),
        }
    }

    pub fn is_ipv6(&self) -> bool {
        matches!(self, Host::Ip(IpAddr::V6(_)))
    }
}

impl fmt::Display for Host {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(&self.url_form())
    }
}

/// A parsed URL: its parts as written (the host in lower case).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Url {
    /// As written (a place that takes `HTTPS` too compares without case).
    pub scheme: String,
    pub host: Host,
    /// `None`: none written.
    pub port: Option<u16>,
    /// `host[:port]` as written.
    pub authority: String,
    /// The host as written (its case kept), IPv6 without brackets.
    pub host_as_written: String,
    /// Empty or from `/`, without query and fragment.
    pub path: String,
    /// After `?`, without the `?`.
    pub query: Option<String>,
    /// After `#`, without the `#`.
    pub fragment: Option<String>,
}

fn scheme_ok(s: &str) -> bool {
    let mut b = s.bytes();
    b.next().is_some_and(|c| c.is_ascii_alphabetic())
        && b.all(|c| c.is_ascii_alphanumeric() || matches!(c, b'+' | b'-' | b'.'))
}

fn port_of(p: &str) -> Result<u16, UrlError> {
    if p.is_empty() || p.len() > 5 || !p.bytes().all(|b| b.is_ascii_digit()) {
        return Err(UrlError::Port);
    }
    p.parse::<u16>()
        .ok()
        .filter(|p| *p > 0)
        .ok_or(UrlError::Port)
}

/// `(host, host as written without brackets, port)` of an authority (no `@` in it).
fn host_port(authority: &str) -> Result<(Host, &str, Option<u16>), UrlError> {
    if authority.is_empty() {
        return Err(UrlError::NoHost);
    }
    if let Some(v6) = authority.strip_prefix('[') {
        let (h, after) = v6.split_once(']').ok_or(UrlError::Ipv6)?;
        let ip = h.parse::<Ipv6Addr>().map_err(UrlError::Ipv6Address)?;
        let port = match after {
            "" => None,
            p => Some(port_of(p.strip_prefix(':').ok_or(UrlError::Port)?)?),
        };
        return Ok((Host::Ip(IpAddr::V6(ip)), h, port));
    }
    let (h, port) = match authority.split_once(':') {
        Some((h, p)) => (h, Some(port_of(p)?)),
        None => (authority, None),
    };
    if h.is_empty() {
        return Err(UrlError::NoHost);
    }
    if h.len() > MAX_NAME
        || !h
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || matches!(b, b'.' | b'-' | b'_'))
    {
        return Err(UrlError::Host);
    }
    let host = match h.parse::<Ipv4Addr>() {
        Ok(ip) => Host::Ip(IpAddr::V4(ip)),
        Err(_) => Host::Name(h.to_ascii_lowercase()),
    };
    Ok((host, h, port))
}

impl Url {
    /// Parse `text` (not trimmed: a place that trims does so first).
    pub fn parse(text: &str) -> Result<Self, UrlError> {
        if !text.bytes().all(|b| b.is_ascii_graphic() && b != b'\\') {
            return Err(UrlError::Chars);
        }
        let (scheme, rest) = text.split_once("://").ok_or(UrlError::NoScheme)?;
        if !scheme_ok(scheme) {
            return Err(UrlError::NoScheme);
        }
        let end = rest.find(['/', '?', '#']).unwrap_or(rest.len());
        let (authority, tail) = rest.split_at(end);
        if authority.contains('@') {
            return Err(UrlError::Credentials);
        }
        let (host, host_as_written, port) = host_port(authority)?;
        let (tail, fragment) = match tail.split_once('#') {
            Some((t, f)) => (t, Some(f.to_owned())),
            None => (tail, None),
        };
        let (path, query) = match tail.split_once('?') {
            Some((p, q)) => (p, Some(q.to_owned())),
            None => (tail, None),
        };
        Ok(Url {
            scheme: scheme.to_owned(),
            host,
            port,
            authority: authority.to_owned(),
            host_as_written: host_as_written.to_owned(),
            path: path.to_owned(),
            query,
            fragment,
        })
    }

    /// The path and the query, as an HTTP request target (`/` at least).
    pub fn target(&self) -> String {
        let mut t = if self.path.is_empty() {
            "/".to_owned()
        } else {
            self.path.clone()
        };
        if let Some(q) = &self.query {
            t.push('?');
            t.push_str(q);
        }
        t
    }
}

/// How a place compares the scheme of an HTTP URL.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SchemeCase {
    /// `http` and `https` only as written so.
    Lower,
    /// In any case (`HTTPS://` too; RFC 3986 §3.1).
    Any,
}

/// An `http://` or `https://` URL with its port (the scheme's when none is written).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct HttpUrl {
    pub tls: bool,
    pub port: u16,
    pub url: Url,
}

impl HttpUrl {
    pub fn parse(text: &str, case: SchemeCase) -> Result<Self, UrlError> {
        let url = Url::parse(text)?;
        let is = |s: &str| match case {
            SchemeCase::Lower => url.scheme == s,
            SchemeCase::Any => url.scheme.eq_ignore_ascii_case(s),
        };
        let tls = if is("https") {
            true
        } else if is("http") {
            false
        } else {
            return Err(UrlError::Scheme);
        };
        let port = url.port.unwrap_or(if tls { 443 } else { 80 });
        Ok(Self { tls, port, url })
    }

    pub fn host(&self) -> &Host {
        &self.url.host
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parts() {
        let u = Url::parse("https://Meter.Local:8443/api/v1?x=1&y=%20#top").unwrap();
        assert_eq!(u.scheme, "https");
        assert_eq!(u.host, Host::Name("meter.local".into()));
        assert_eq!(
            (u.port, u.authority.as_str()),
            (Some(8443), "Meter.Local:8443")
        );
        assert_eq!(
            (u.path.as_str(), u.query.as_deref(), u.fragment.as_deref()),
            ("/api/v1", Some("x=1&y=%20"), Some("top"))
        );
        assert_eq!(u.target(), "/api/v1?x=1&y=%20");
        let u = Url::parse("http://[::1]:8080").unwrap();
        assert_eq!(u.host, Host::Ip("::1".parse().unwrap()));
        assert_eq!(
            (u.host.text(), u.host.url_form()),
            ("::1".into(), "[::1]".into())
        );
        assert_eq!(
            (u.port, u.path.as_str(), u.target()),
            (Some(8080), "", "/".into())
        );
        let u = Url::parse("http://10.0.0.5?x").unwrap();
        assert_eq!(u.host, Host::Ip("10.0.0.5".parse().unwrap()));
        assert_eq!((u.path.as_str(), u.query.as_deref()), ("", Some("x")));
        let u = Url::parse("mqtts://broker_1.example:8883").unwrap();
        assert_eq!(
            (u.scheme.as_str(), u.host.text()),
            ("mqtts", "broker_1.example".into())
        );
        // the path is not resolved or decoded
        assert_eq!(
            Url::parse("https://h/a/../b%2F").unwrap().path,
            "/a/../b%2F"
        );
    }

    #[test]
    fn http_urls() {
        let u = HttpUrl::parse("https://h", SchemeCase::Lower).unwrap();
        assert_eq!((u.tls, u.port), (true, 443));
        let u = HttpUrl::parse("http://h:8080/x", SchemeCase::Lower).unwrap();
        assert_eq!((u.tls, u.port), (false, 8080));
        assert_eq!(
            HttpUrl::parse("HTTPS://h", SchemeCase::Lower),
            Err(UrlError::Scheme)
        );
        assert!(HttpUrl::parse("HTTPS://h", SchemeCase::Any).unwrap().tls);
        for s in ["ftp://h", "file:///x", "ws://h", "httpx://h"] {
            assert_eq!(
                HttpUrl::parse(s, SchemeCase::Any).err(),
                Some(if s.starts_with("file") {
                    UrlError::NoHost
                } else {
                    UrlError::Scheme
                }),
                "{s}"
            );
        }
    }

    /// Malformed inputs, by the class each old parser handled differently (review S4).
    #[test]
    fn refusals() {
        use UrlError::*;
        let addr = Ipv6Address("x".parse::<Ipv6Addr>().unwrap_err());
        for (s, e) in [
            // userinfo, in every spelling
            ("https://u:p@host/", Credentials),
            ("https://token@host", Credentials),
            ("https://@host", Credentials),
            ("https://host@evil.example/", Credentials),
            ("http://[::1]@evil/", Credentials),
            // IPv6 literals
            ("http://[::1/", Ipv6),
            ("http://[::1", Ipv6),
            ("http://[fe80::1%25eth0]/", addr.clone()),
            ("http://[g::1]/", addr.clone()),
            ("http://[::1]x/", Port),
            ("http://[::1]:/", Port),
            ("http://::1/", Port),
            ("http://[]/", addr.clone()),
            // ports
            ("http://host:0/", Port),
            ("http://host:65536/", Port),
            ("http://host:99999/", Port),
            ("http://host:+80/", Port),
            ("http://host:080080/", Port),
            ("http://host:/", Port),
            ("http://host:8a/", Port),
            ("http://host:80:81/", Port),
            ("http://[::1]:65536/", Port),
            // schemes and the separator
            ("host:80", NoScheme),
            ("//host/", NoScheme),
            ("https:host", NoScheme),
            ("https:/host", NoScheme),
            ("1http://host", NoScheme),
            ("ht tp://host", Chars),
            ("://host", NoScheme),
            // hosts
            ("http://", NoHost),
            ("http:///path", NoHost),
            ("http://:80/", NoHost),
            ("http://ho%73t/", Host),
            ("http://exa*mple/", Host),
            ("http://xn--über.example/", Chars),
            // characters anywhere
            ("http://host/a b", Chars),
            ("http://host/a\tb", Chars),
            ("http://host/a\r\nHost: evil", Chars),
            ("http://host\\@evil/", Chars),
            ("http://host/a\\b", Chars),
            ("https://host/é", Chars),
            (" https://host", Chars),
            ("https://host ", Chars),
        ] {
            assert_eq!(Url::parse(s), Err(e.clone()), "{s:?}");
        }
        let long = format!("http://{}.example/", "a".repeat(250));
        assert_eq!(Url::parse(&long), Err(Host));
        // the error never repeats the URL
        let e = Url::parse("https://user:secret-token@h/")
            .unwrap_err()
            .to_string();
        assert!(!e.contains("secret"), "{e}");
    }

    /// No text panics the parser (it slices only at ASCII it found).
    #[test]
    fn arbitrary_text_never_panics() {
        let pieces = [
            "http", "https", "://", ":", "[", "]", "::1", "@", "/", "?", "#", "%", "é", "\\", "80",
            "65536", "h", ".", " ", "\u{0}", "x",
        ];
        let mut seed: u64 = 0x5eed;
        for _ in 0..50_000 {
            let mut s = String::new();
            for _ in 0..(seed % 9) {
                seed = seed
                    .wrapping_mul(6364136223846793005)
                    .wrapping_add(1442695040888963407);
                let i = usize::try_from((seed >> 33) % pieces.len() as u64).unwrap_or(0);
                s.push_str(pieces[i]);
            }
            let _ = Url::parse(&s);
            let _ = HttpUrl::parse(&s, SchemeCase::Any);
        }
    }
}
