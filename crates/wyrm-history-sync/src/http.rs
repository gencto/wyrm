//! A small HTTP/1.1 client over a host connection (plain or TLS): one
//! request, one response, `Content-Length` or chunked bodies. Enough for
//! the HTTP targets (InfluxDB, DynamoDB); it never follows redirects.

use crate::TargetError;
use wyrm_link_api::{ConnId, Host};

/// The largest response head and body it reads.
const MAX_HEAD: usize = 16 << 10;
pub const MAX_BODY: usize = 1 << 20;
/// The host sends at most this much at a time.
const SEND_CHUNK: usize = 64 << 10;

/// One request. `path` includes the query; header values must not hold CR or LF.
pub struct Request<'a> {
    pub method: &'a str,
    pub path: &'a str,
    pub host: &'a str,
    pub headers: &'a [(&'a str, &'a str)],
    pub body: &'a [u8],
}

#[derive(Debug, Clone, PartialEq)]
pub struct Response {
    pub status: u16,
    pub body: Vec<u8>,
    /// The server closes the connection after it.
    pub close: bool,
}

impl Response {
    /// The body as text, cut to `max` bytes (for error messages).
    pub fn text(&self, max: usize) -> String {
        let b = &self.body[..self.body.len().min(max)];
        String::from_utf8_lossy(b).trim().to_owned()
    }
}

fn plain(s: &str) -> bool {
    !s.bytes().any(|b| b == b'\r' || b == b'\n' || b == 0)
}

fn lost(e: impl std::fmt::Display) -> TargetError {
    TargetError::Reconnect(format!("http: {e}"))
}

/// Send `req` on `conn` and read the response within `timeout_ms` per read.
pub fn send(
    net: &mut dyn Host,
    conn: ConnId,
    req: &Request<'_>,
    timeout_ms: u32,
) -> Result<Response, TargetError> {
    let fields = [req.method, req.path, req.host]
        .into_iter()
        .chain(req.headers.iter().flat_map(|(k, v)| [*k, *v]));
    if !fields.into_iter().all(plain) || req.path.contains(' ') {
        return Err(TargetError::Fatal(
            "http: a request field holds a line break or a space".into(),
        ));
    }
    let mut head = format!(
        "{} {} HTTP/1.1\r\nHost: {}\r\nContent-Length: {}\r\n",
        req.method,
        req.path,
        req.host,
        req.body.len()
    );
    for (k, v) in req.headers {
        head.push_str(k);
        head.push_str(": ");
        head.push_str(v);
        head.push_str("\r\n");
    }
    head.push_str("\r\n");
    let mut out = head.into_bytes();
    out.extend_from_slice(req.body);
    for chunk in out.chunks(SEND_CHUNK) {
        net.tcp_send(conn, chunk).map_err(|e| lost(e.msg))?;
    }
    read_response(net, conn, timeout_ms)
}

fn recv_more(
    net: &mut dyn Host,
    conn: ConnId,
    buf: &mut Vec<u8>,
    timeout_ms: u32,
) -> Result<(), TargetError> {
    let got = net
        .tcp_recv(conn, 64 << 10, timeout_ms)
        .map_err(|e| lost(e.msg))?;
    if got.is_empty() {
        return Err(lost("the server closed the connection"));
    }
    buf.extend_from_slice(&got);
    Ok(())
}

fn find(hay: &[u8], needle: &[u8]) -> Option<usize> {
    hay.windows(needle.len()).position(|w| w == needle)
}

fn read_response(
    net: &mut dyn Host,
    conn: ConnId,
    timeout_ms: u32,
) -> Result<Response, TargetError> {
    let mut buf = Vec::new();
    let end = loop {
        if let Some(i) = find(&buf, b"\r\n\r\n") {
            break i;
        }
        if buf.len() > MAX_HEAD {
            return Err(lost("response head too long"));
        }
        recv_more(net, conn, &mut buf, timeout_ms)?;
    };
    let head = String::from_utf8_lossy(&buf[..end]).into_owned();
    let mut rest = buf[end + 4..].to_vec();
    let mut lines = head.split("\r\n");
    let status = lines
        .next()
        .and_then(|l| l.split(' ').nth(1))
        .and_then(|s| s.parse::<u16>().ok())
        .ok_or_else(|| lost("no status line"))?;
    let (mut len, mut chunked, mut close) = (None, false, false);
    for l in lines {
        let Some((k, v)) = l.split_once(':') else {
            continue;
        };
        let (k, v) = (k.trim().to_ascii_lowercase(), v.trim().to_ascii_lowercase());
        match k.as_str() {
            "content-length" => len = v.parse::<usize>().ok(),
            "transfer-encoding" => chunked = v.contains("chunked"),
            "connection" => close = v == "close",
            _ => {}
        }
    }
    let body = if chunked {
        let mut body = Vec::new();
        loop {
            let i = loop {
                if let Some(i) = find(&rest, b"\r\n") {
                    break i;
                }
                recv_more(net, conn, &mut rest, timeout_ms)?;
            };
            let size = std::str::from_utf8(&rest[..i])
                .ok()
                .and_then(|s| usize::from_str_radix(s.split(';').next()?.trim(), 16).ok())
                .ok_or_else(|| lost("bad chunk size"))?;
            rest.drain(..i + 2);
            if size == 0 {
                break;
            }
            if body.len() + size > MAX_BODY {
                return Err(lost("response body too long"));
            }
            while rest.len() < size + 2 {
                recv_more(net, conn, &mut rest, timeout_ms)?;
            }
            body.extend_from_slice(&rest[..size]);
            rest.drain(..size + 2);
        }
        body
    } else {
        // no length on a response that has a body: it ends with the connection
        let n = match len {
            Some(n) => n,
            None if status == 204 || status == 304 => 0,
            None => return Err(lost("no Content-Length")),
        };
        if n > MAX_BODY {
            return Err(lost("response body too long"));
        }
        while rest.len() < n {
            recv_more(net, conn, &mut rest, timeout_ms)?;
        }
        rest.truncate(n);
        rest
    };
    Ok(Response {
        status,
        body,
        close,
    })
}

/// `scheme://host[:port][/base]`: TLS or not, host, port, base path.
pub fn parse_url(url: &str) -> Result<(bool, String, u16, String), String> {
    let (tls, rest) = if let Some(r) = url.strip_prefix("https://") {
        (true, r)
    } else if let Some(r) = url.strip_prefix("http://") {
        (false, r)
    } else {
        return Err(format!("{url}: http:// or https://"));
    };
    let (authority, base) = match rest.find('/') {
        Some(i) => (&rest[..i], rest[i..].trim_end_matches('/')),
        None => (rest, ""),
    };
    if authority.contains('@') {
        return Err(format!("{url}: no credentials in the URL"));
    }
    let (host, port) = match authority.rsplit_once(':') {
        Some((h, p)) if !h.ends_with(']') || h.starts_with('[') => {
            (h, p.parse::<u16>().map_err(|_| format!("{url}: bad port"))?)
        }
        _ => (authority, if tls { 443 } else { 80 }),
    };
    let host = host.trim_start_matches('[').trim_end_matches(']');
    if host.is_empty() || !plain(base) || base.contains([' ', '?', '#']) {
        return Err(format!("{url}: bad host or path"));
    }
    Ok((tls, host.to_owned(), port, base.to_owned()))
}

/// Percent-encode a query value.
pub fn query_value(s: &str) -> String {
    let mut out = String::new();
    for b in s.bytes() {
        if b.is_ascii_alphanumeric() || b"-._~".contains(&b) {
            out.push(b as char);
        } else {
            out.push_str(&format!("%{b:02X}"));
        }
    }
    out
}

/// A loopback host, where a secret may go without TLS.
pub fn loopback(host: &str) -> bool {
    host == "localhost"
        || host
            .parse::<std::net::IpAddr>()
            .is_ok_and(|ip| ip.is_loopback())
}
