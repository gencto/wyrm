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

/// The longest line of a chunked body (a size or a trailer).
const MAX_LINE: usize = 1024;

/// One CRLF-ended line from `rest` (read more as needed), without the CRLF.
fn read_line(
    net: &mut dyn Host,
    conn: ConnId,
    rest: &mut Vec<u8>,
    timeout_ms: u32,
) -> Result<Vec<u8>, TargetError> {
    loop {
        if let Some(i) = find(rest, b"\r\n") {
            let line = rest[..i].to_vec();
            rest.drain(..i + 2);
            return Ok(line);
        }
        if rest.len() > MAX_LINE {
            return Err(lost("chunk line too long"));
        }
        recv_more(net, conn, rest, timeout_ms)?;
    }
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
            let line = read_line(net, conn, &mut rest, timeout_ms)?;
            let size = std::str::from_utf8(&line)
                .ok()
                .and_then(|s| usize::from_str_radix(s.split(';').next()?.trim(), 16).ok())
                .ok_or_else(|| lost("bad chunk size"))?;
            if size == 0 {
                // trailers, up to the empty line: the connection stays clean for the next request
                while !read_line(net, conn, &mut rest, timeout_ms)?.is_empty() {}
                break;
            }
            // checked before any sum: a huge size cannot overflow
            if size > MAX_BODY || body.len() + size > MAX_BODY {
                return Err(lost("response body too long"));
            }
            while rest.len() < size + 2 {
                recv_more(net, conn, &mut rest, timeout_ms)?;
            }
            if &rest[size..size + 2] != b"\r\n" {
                return Err(lost("bad chunk end"));
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
        return Err("the URL must start with http:// or https://".into());
    };
    let (authority, base) = match rest.find('/') {
        Some(i) => (&rest[..i], rest[i..].trim_end_matches('/')),
        None => (rest, ""),
    };
    if authority.contains('@') {
        return Err("no credentials in the URL".into());
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

/// One HTTP endpoint over a keep-alive connection: opened on first use (TLS with `tls`), opened
/// again once when the server closed it meanwhile, closed after `Connection: close`.
pub struct Client {
    pub tls: bool,
    pub host: String,
    pub port: u16,
    pub ca_pem: Option<String>,
    pub timeout_ms: u32,
    conn: Option<ConnId>,
}

impl Client {
    pub fn new(
        tls: bool,
        host: String,
        port: u16,
        ca_pem: Option<String>,
        timeout_ms: u32,
    ) -> Self {
        Self {
            tls,
            host,
            port,
            ca_pem,
            timeout_ms,
            conn: None,
        }
    }

    /// Open the connection now (a target's `connect` checks the server is there).
    pub fn open(&mut self, net: &mut dyn Host) -> Result<ConnId, TargetError> {
        if let Some(c) = self.conn {
            return Ok(c);
        }
        let r = if self.tls {
            net.tls_connect(
                &self.host,
                self.port,
                self.timeout_ms,
                self.ca_pem.as_deref(),
            )
        } else {
            net.tcp_connect(&self.host, self.port, self.timeout_ms)
        };
        let c =
            r.map_err(|e| TargetError::Reconnect(format!("connect {}: {}", self.host, e.msg)))?;
        self.conn = Some(c);
        Ok(c)
    }

    pub fn close(&mut self, net: &mut dyn Host) {
        if let Some(c) = self.conn.take() {
            net.tcp_close(c);
        }
    }

    /// `Host`: the name, and the port when it is not the scheme's (what SigV4 signs too).
    pub fn host_header(&self) -> String {
        let name = if self.host.contains(':') {
            format!("[{}]", self.host)
        } else {
            self.host.clone()
        };
        match (self.tls, self.port) {
            (true, 443) | (false, 80) => name,
            (_, p) => format!("{name}:{p}"),
        }
    }

    /// One request (`Host` is added).
    pub fn request(
        &mut self,
        net: &mut dyn Host,
        method: &str,
        path: &str,
        headers: &[(&str, &str)],
        body: &[u8],
    ) -> Result<Response, TargetError> {
        let host = self.host_header();
        for attempt in 0..2 {
            let conn = self.open(net)?;
            let req = Request {
                method,
                path,
                host: &host,
                headers,
                body,
            };
            match send(net, conn, &req, self.timeout_ms) {
                Ok(r) => {
                    if r.close {
                        self.close(net);
                    }
                    return Ok(r);
                }
                Err(TargetError::Reconnect(m)) => {
                    self.close(net);
                    if attempt == 1 {
                        return Err(TargetError::Reconnect(m));
                    }
                }
                Err(e) => return Err(e),
            }
        }
        Err(TargetError::Reconnect("http: no connection".into()))
    }
}

/// A JSON string literal (RFC 8259): quotes, backslashes and control characters escaped.
pub fn json_string(s: &str) -> String {
    let mut out = String::with_capacity(s.len() + 2);
    out.push('"');
    for c in s.chars() {
        match c {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            c if (c as u32) < 0x20 => out.push_str(&format!("\\u{:04x}", c as u32)),
            c => out.push(c),
        }
    }
    out.push('"');
    out
}
