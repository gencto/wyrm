//! TLS on rustls + ring: a self-signed certificate, a raw HTTPS request.

#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    clippy::panic,
    clippy::unreachable,
    clippy::print_stdout,
    reason = "test code: a failed step fails the test"
)]

use std::sync::Arc;
use std::time::Duration;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::TcpStream;
use wyrm_gateway::{Gateway, GatewayConfig};
use wyrm_link_sdk::harness::{isolated_config, SITE};

#[tokio::test(flavor = "multi_thread")]
async fn serves_https_with_ring() {
    let dir = std::env::temp_dir().join(format!("wyrm-gateway-tls-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    let ck = rcgen::generate_simple_self_signed(vec!["localhost".into()]).unwrap();
    let (cert, key) = (dir.join("gw.crt"), dir.join("gw.key"));
    std::fs::write(&cert, ck.cert.pem()).unwrap();
    std::fs::write(&key, ck.signing_key.serialize_pem()).unwrap();

    let mut cfg = GatewayConfig::new(SITE, dir.join("state"), "127.0.0.1:0".parse().unwrap());
    cfg.tls = Some((cert, key));
    let gw = Gateway::open(cfg, b"k").unwrap();
    let session = zenoh::open(isolated_config()).await.unwrap();
    let (stop, rx) = tokio::sync::oneshot::channel::<()>();
    let server = tokio::spawn(gw.clone().serve(session, async {
        let _ = rx.await;
    }));
    let addr = gw.local_addr().await;

    let mut roots = rustls::RootCertStore::empty();
    roots.add(ck.cert.der().clone()).unwrap();
    let client = rustls::ClientConfig::builder_with_provider(Arc::new(
        rustls::crypto::ring::default_provider(),
    ))
    .with_safe_default_protocol_versions()
    .unwrap()
    .with_root_certificates(roots)
    .with_no_client_auth();
    let tcp = TcpStream::connect(addr).await.unwrap();
    let name = rustls::pki_types::ServerName::try_from("localhost").unwrap();
    let mut tls = tokio_rustls::TlsConnector::from(Arc::new(client))
        .connect(name, tcp)
        .await
        .unwrap();
    tls.write_all(b"GET /api/me HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n")
        .await
        .unwrap();
    let mut resp = Vec::new();
    tokio::time::timeout(Duration::from_secs(5), tls.read_to_end(&mut resp))
        .await
        .unwrap()
        .unwrap();
    assert!(
        resp.starts_with(b"HTTP/1.1 401"),
        "{}",
        String::from_utf8_lossy(&resp)
    );

    // A plain-text client gets no HTTP answer.
    let mut plain = TcpStream::connect(addr).await.unwrap();
    plain
        .write_all(b"GET /api/me HTTP/1.1\r\nHost: x\r\n\r\n")
        .await
        .unwrap();
    let mut buf = Vec::new();
    let _ = tokio::time::timeout(Duration::from_secs(2), plain.read_to_end(&mut buf)).await;
    assert!(!buf.starts_with(b"HTTP/1.1"));

    let _ = stop.send(());
    tokio::time::timeout(Duration::from_secs(10), server)
        .await
        .expect("graceful stop")
        .unwrap()
        .unwrap();
}

/// A certificate for `names` and its key, both PEM, and the certificate's DER.
fn self_signed(names: &[&str]) -> (String, String, Vec<u8>) {
    let ck = rcgen::generate_simple_self_signed(
        names.iter().map(|n| (*n).to_owned()).collect::<Vec<_>>(),
    )
    .unwrap();
    (
        ck.cert.pem(),
        ck.signing_key.serialize_pem(),
        ck.cert.der().to_vec(),
    )
}

/// The DER of the certificate a new TLS connection to `addr` is served.
async fn served(addr: std::net::SocketAddr, roots: &[&[u8]]) -> Vec<u8> {
    let mut store = rustls::RootCertStore::empty();
    for r in roots {
        store
            .add(rustls::pki_types::CertificateDer::from(r.to_vec()))
            .unwrap();
    }
    let client = rustls::ClientConfig::builder_with_provider(Arc::new(
        rustls::crypto::ring::default_provider(),
    ))
    .with_safe_default_protocol_versions()
    .unwrap()
    .with_root_certificates(store)
    .with_no_client_auth();
    let tcp = TcpStream::connect(addr).await.unwrap();
    let name = rustls::pki_types::ServerName::try_from("localhost").unwrap();
    let tls = tokio_rustls::TlsConnector::from(Arc::new(client))
        .connect(name, tcp)
        .await
        .unwrap();
    tls.get_ref().1.peer_certificates().unwrap()[0].to_vec()
}

fn info_names(gw: &Gateway) -> Vec<String> {
    let wyrm_core::Value::Map(m) = gw.info() else {
        panic!("info is a map");
    };
    match m.get("names") {
        Some(wyrm_core::Value::Array(a)) => a
            .iter()
            .map(|v| match v {
                wyrm_core::Value::Str(s) => s.clone(),
                other => panic!("name: {other:?}"),
            })
            .collect(),
        other => panic!("names: {other:?}"),
    }
}

/// `reload_tls` swaps the certificate of a gateway that serves: a new connection gets the
/// new one, and every value read from the certificate (`/api/info` `names`, the device
/// origins) follows it. A plain-HTTP gateway has nothing to reload.
#[tokio::test(flavor = "multi_thread")]
async fn reloaded_certificate_is_served() {
    let dir = std::env::temp_dir().join(format!("wyrm-gateway-reload-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    let (a_pem, a_key, a_der) = self_signed(&["localhost"]);
    let (b_pem, b_key, b_der) = self_signed(&["localhost", "gw-b.example"]);
    let (cert, key) = (dir.join("gw.crt"), dir.join("gw.key"));
    std::fs::write(&cert, &a_pem).unwrap();
    std::fs::write(&key, &a_key).unwrap();

    let mut cfg = GatewayConfig::new(SITE, dir.join("state"), "127.0.0.1:0".parse().unwrap());
    cfg.tls = Some((cert, key));
    let gw = Gateway::open(cfg, b"k").unwrap();
    let session = zenoh::open(isolated_config()).await.unwrap();
    let (stop, rx) = tokio::sync::oneshot::channel::<()>();
    let server = tokio::spawn(gw.clone().serve(session, async {
        let _ = rx.await;
    }));
    let addr = gw.local_addr().await;
    let roots = [a_der.as_slice(), b_der.as_slice()];
    assert_eq!(served(addr, &roots).await, a_der);
    assert_eq!(info_names(&gw), ["localhost"]);

    // a broken pair is refused and changes nothing
    assert!(gw
        .reload_tls(b_pem.clone().into_bytes(), a_key.clone().into_bytes())
        .is_err());
    assert_eq!(served(addr, &roots).await, a_der);
    assert_eq!(info_names(&gw), ["localhost"]);

    gw.reload_tls(b_pem.into_bytes(), b_key.into_bytes())
        .unwrap();
    assert_eq!(served(addr, &roots).await, b_der);
    assert_eq!(info_names(&gw), ["localhost", "gw-b.example"]);

    let _ = stop.send(());
    tokio::time::timeout(Duration::from_secs(10), server)
        .await
        .expect("graceful stop")
        .unwrap()
        .unwrap();

    // plain HTTP (loopback): nothing to reload
    let plain = Gateway::open(
        GatewayConfig::new(SITE, dir.join("plain"), "127.0.0.1:0".parse().unwrap()),
        b"k",
    )
    .unwrap();
    assert!(matches!(
        plain.reload_tls(a_pem.into_bytes(), a_key.into_bytes()),
        Err(wyrm_gateway::Error::Config(_))
    ));
    let _ = std::fs::remove_dir_all(&dir);
}
