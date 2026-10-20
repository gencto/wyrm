//! Client session configuration for one broker endpoint, shared by `wyr`
//! and `wyrm-ffi`. Principle 6: `tls/` and `quic/` endpoints use mTLS with
//! certificates from the broker CA; plaintext only on loopback.

use std::path::PathBuf;

/// The mTLS files of a client: the broker CA and a certificate it issued.
#[derive(Debug, Clone)]
pub struct TlsFiles {
    pub ca: PathBuf,
    pub cert: PathBuf,
    pub key: PathBuf,
}

/// `true` for a `tls/` or `quic/` endpoint.
pub fn is_tls(endpoint: &str) -> bool {
    endpoint.starts_with("tls/") || endpoint.starts_with("quic/")
}

/// `tcp/`, `udp/` or `ws/` endpoint whose host is not loopback.
pub fn plaintext_off_loopback(endpoint: &str) -> bool {
    let Some((proto, rest)) = endpoint.split_once('/') else {
        return false;
    };
    if !matches!(proto, "tcp" | "udp" | "ws") {
        return false;
    }
    // strip `?metadata` / `#config`, then the port
    let addr = rest.split(['?', '#']).next().unwrap_or(rest);
    let host = match addr.rsplit_once(':') {
        Some((h, _)) => h.trim_start_matches('[').trim_end_matches(']'),
        None => addr,
    };
    let loopback = host.eq_ignore_ascii_case("localhost")
        || host
            .parse::<std::net::IpAddr>()
            .is_ok_and(|ip| ip.is_loopback());
    !loopback
}

/// `transport/link/tls` (json5) for `endpoint`: mTLS for `tls/`/`quic/`,
/// which need `tls`; `None` for other endpoints.
pub fn tls_section(endpoint: &str, tls: Option<&TlsFiles>) -> Result<Option<String>, String> {
    if !is_tls(endpoint) {
        return Ok(None);
    }
    let Some(t) = tls else {
        return Err(format!(
            "{endpoint}: tls/quic endpoints need the CA, a certificate and its key"
        ));
    };
    // A json5 string; `\` (Windows paths) and `"` escaped.
    let path = |p: &PathBuf| match p.to_str() {
        Some(s) if !s.chars().any(char::is_control) => Ok(format!(
            "\"{}\"",
            s.replace('\\', "\\\\").replace('"', "\\\"")
        )),
        _ => Err(format!("{}: path must be UTF-8 text", p.display())),
    };
    Ok(Some(format!(
        "{{ root_ca_certificate: {}, connect_certificate: {}, connect_private_key: {}, enable_mtls: true }}",
        path(&t.ca)?,
        path(&t.cert)?,
        path(&t.key)?
    )))
}

/// Client-mode Zenoh config for one `endpoint`, no scouting.
pub fn client_config(endpoint: &str, tls: Option<&TlsFiles>) -> Result<zenoh::Config, String> {
    if endpoint
        .chars()
        .any(|c| c == '"' || c == '\\' || c.is_control())
    {
        return Err("endpoint: illegal character".into());
    }
    let mut zc = zenoh::Config::default();
    let mut set = |k: &str, v: &str| {
        zc.insert_json5(k, v)
            .map_err(|e| format!("zenoh config {k}: {e}"))
    };
    set("mode", r#""client""#)?;
    set("connect/endpoints", &format!("[\"{endpoint}\"]"))?;
    set("scouting/multicast/enabled", "false")?;
    if let Some(t) = tls_section(endpoint, tls)? {
        set("transport/link/tls", &t)?;
    }
    Ok(zc)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn plaintext_and_tls_rules() {
        let off = plaintext_off_loopback;
        assert!(!off("tcp/127.0.0.1:7447"));
        assert!(!off("tcp/[::1]:7447"));
        assert!(!off("tcp/localhost:7447"));
        assert!(!off("tls/0.0.0.0:7447"));
        assert!(!off("unixsock-stream//tmp/wyrm.sock"));
        assert!(off("tcp/0.0.0.0:7447"));
        assert!(off("tcp/192.168.1.10:7447#iface=eth0"));

        assert_eq!(tls_section("tcp/127.0.0.1:7447", None).unwrap(), None);
        assert!(tls_section("tls/127.0.0.1:7448", None).is_err());
        let f = TlsFiles {
            ca: "ca.pem".into(),
            cert: "c\"x.pem".into(),
            key: "c.key".into(),
        };
        let c = tls_section("quic/127.0.0.1:7448", Some(&f))
            .unwrap()
            .unwrap();
        assert!(c.contains("enable_mtls: true") && c.contains(r#""c\"x.pem""#));
        let f = TlsFiles {
            ca: r"C:\pki\ca.pem".into(),
            ..f
        };
        let zc = client_config("tls/127.0.0.1:7448", Some(&f)).unwrap();
        assert!(zc
            .get_json("transport/link/tls/root_ca_certificate")
            .unwrap()
            .contains(r"C:\\pki"));
        assert!(client_config("tcp/a\"b:1", None).is_err());
    }
}
