//! TLS on rustls + ring: a self-signed certificate, a raw HTTPS request.

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
