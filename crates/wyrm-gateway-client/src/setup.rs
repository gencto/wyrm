//! The first admin of a new broker from its one-time setup code (ADR 0051 §3), as a
//! person's first client does it (`wyr setup`):
//!
//! 1. [`begin`]: `GET /api/info` over TLS without trust in the certificate; the gateway
//!    offers a setup (`setup: true`) with the CA it presents (`ca`) and a proof that binds
//!    that CA to the setup code (`setup_proof`). The proof is checked with the code as the
//!    person typed it ([`wyrm_core::setup::verify_setup_proof`]): only who holds the hash
//!    of the code can make it, so a proof that verifies names the device's own CA.
//! 2. That CA is pinned: every later connection trusts it alone (no public roots) and
//!    checks the certificate against one of its names ([`server_name`]). `/api/info` is
//!    read again over the pinned connection and must carry the same CA.
//! 3. [`Pending::finish`]: `POST /api/setup {code, user, password}` (CBOR), then a login
//!    and `GET /api/me` as that user.
//!
//! Nothing secret is sent before step 2: neither the code nor the password ever travels
//! over a connection whose certificate is not the proven CA's.

use crate::{http_with, transport, Endpoint, Error, Gateway};
use std::collections::BTreeMap;
use std::sync::Arc;
use std::time::Duration;
use tokio_rustls::rustls;
use wyrm_core::Value;

mod decode;

/// How long `POST /api/setup` and the login may take: the gateway hashes the password
/// (Argon2id), which an emulated board (QEMU without acceleration) does many times slower.
pub const HASH_TIMEOUT: Duration = Duration::from_secs(120);

/// Why the first admin was not made. Each says what happened in a sentence a person can
/// act on.
#[derive(Debug, thiserror::Error)]
pub enum SetupError {
    /// The address is no `https://host[:port]`; the text says why.
    #[error("{0}: the gateway address is https://<device address>[:port], for example https://wyrm-plant.local:8445")]
    Url(String),
    /// The gateway could not be reached or answered something that is no answer.
    #[error("{0}")]
    Transport(#[from] Error),
    /// `/api/info` offers no setup.
    #[error("this gateway offers no setup: its broker already has a user, or it was started without a setup code. Log in with that user instead")]
    NoSetup,
    /// A setup without a CA or a proof: plain HTTP, or a gateway that presents no CA.
    #[error("this gateway offers a setup but no proof of its certificate (no `ca` or `setup_proof` in /api/info): wyr setup needs a gateway with `tls: \"site_ca\"`, as a board image has it")]
    NoProof,
    /// The proof does not verify with this code and the CA presented.
    #[error("the setup code does not match this device: the code is mistyped, or something between you and the device presents another certificate. Nothing was sent. Check the code and the address, then run wyr setup again")]
    ProofMismatch,
    /// The certificate names no host to check it against.
    #[error("the gateway's certificate names no host or address this client can check it against")]
    NoName,
    /// The pinned connection presented another CA, or no longer offers the setup.
    #[error("the device answered differently over the pinned connection (another CA, or no setup any more). Nothing was sent. Run wyr setup again")]
    Changed,
    /// `409 no_setup`: the code was used meanwhile.
    #[error("the first admin of this broker was made meanwhile: the setup code is used up. Log in with that user")]
    Taken,
    /// `403 setup_code_wrong`.
    #[error("the gateway refused the setup code")]
    WrongCode,
    /// `400`: the user name or the password is refused; the gateway's words.
    #[error("the gateway refused the user or the password: {0}")]
    Rejected(String),
    /// `429`.
    #[error("too many tries from this address or for this user: wait a minute, then run wyr setup again")]
    RateLimited,
    /// Any other answer.
    #[error("POST /api/setup: HTTP {0}")]
    Http(u16),
    /// The admin was made, but logging in as that user failed.
    #[error("the first admin {user} was made, but the login check failed: {error}")]
    Login { user: String, error: Error },
}

/// What `/api/info` offers while a setup is pending, the proof checked.
#[derive(Debug, Clone, PartialEq)]
pub struct Offer {
    /// The DER of the CA the gateway presents (proven by the setup code).
    pub ca_der: Vec<u8>,
    /// The CA's code (`ca_fp`, 32 hex digits), as `wyrmd ca fingerprint` prints it.
    pub ca_fp: String,
    /// The DNS and IP names of the gateway's certificate.
    pub names: Vec<String>,
    /// The site the gateway serves.
    pub site: String,
}

/// Reads the offer of `info` (the map of `/api/info`) and checks its proof with `code`.
pub fn read_offer(info: &Value, code: &str) -> Result<Offer, SetupError> {
    let info = decode::info(info).ok_or_else(|| Error::Transport("/api/info: not a map".into()))?;
    if !info.setup {
        return Err(SetupError::NoSetup);
    }
    let (Some(ca), Some(proof)) = (info.ca, info.setup_proof) else {
        return Err(SetupError::NoProof);
    };
    if !wyrm_core::setup::verify_setup_proof(code, &ca, &proof) {
        return Err(SetupError::ProofMismatch);
    }
    Ok(Offer {
        // the code of the bytes proven, not the text the gateway sent beside them
        ca_fp: ca_fingerprint(&ca),
        ca_der: ca,
        names: info.names,
        site: info.site,
    })
}

/// The CA's code: the first 16 bytes of its SHA-256 in hex (`/api/info` `ca_fp`).
pub fn ca_fingerprint(der: &[u8]) -> String {
    wyrm_core::hex::encode(&wyrm_core::hex::sha256(der)[..16])
}

/// The name a certificate of `names` is checked against when the client reached it at
/// `host` (as in the URL, IPv6 without brackets): `host` itself when the certificate
/// names it; else `wyrm-<site>.local` (the name the gateway announces); else its first
/// DNS name; else its first address.
pub fn server_name(host: &str, names: &[String]) -> Option<String> {
    let host = host
        .trim_start_matches('[')
        .trim_end_matches(']')
        .to_ascii_lowercase();
    let is_ip = |n: &str| n.parse::<std::net::IpAddr>().is_ok();
    if names.contains(&host) {
        return Some(host);
    }
    names
        .iter()
        .find(|n| n.starts_with("wyrm-") && n.ends_with(".local"))
        .or_else(|| names.iter().find(|n| !is_ip(n)))
        .or_else(|| names.first())
        .cloned()
}

/// A gateway whose offer is proven and whose CA is pinned: [`Pending::finish`] makes the
/// first admin.
pub struct Pending {
    ep: Endpoint,
    offer: Offer,
    name: String,
}

impl Pending {
    /// The proven offer: the CA and its code.
    pub fn offer(&self) -> &Offer {
        &self.offer
    }

    /// The certificate name every connection is checked against.
    pub fn name(&self) -> &str {
        &self.name
    }

    /// The pinned endpoint: the address of the URL, the proven CA alone, [`Self::name`].
    pub fn endpoint(&self) -> &Endpoint {
        &self.ep
    }

    /// `POST /api/setup {code, user, password}` over the pinned connection, then a login as
    /// `user` and `GET /api/me`. `timeout` bounds each of the two hashing requests
    /// ([`HASH_TIMEOUT`] is a good one).
    pub async fn finish(
        self,
        code: &str,
        user: &str,
        password: &str,
        timeout: Duration,
    ) -> Result<Gateway, SetupError> {
        let body = Value::Map(BTreeMap::from([
            ("code".to_owned(), Value::from(code)),
            ("user".to_owned(), Value::from(user)),
            ("password".to_owned(), Value::from(password)),
        ]));
        let (st, v) = http_with(&self.ep, "/api/setup", None, Some(&body), timeout).await?;
        match st {
            204 => {}
            409 => return Err(SetupError::Taken),
            403 => return Err(SetupError::WrongCode),
            400 => {
                return Err(SetupError::Rejected(
                    crate::text_field(&v, "message").unwrap_or_else(|| "no reason given".into()),
                ))
            }
            429 => return Err(SetupError::RateLimited),
            other => return Err(SetupError::Http(other)),
        }
        let login = |error: Error| SetupError::Login {
            user: user.to_owned(),
            error,
        };
        let body = Value::Map(BTreeMap::from([
            ("user".to_owned(), Value::from(user)),
            ("password".to_owned(), Value::from(password)),
        ]));
        let (st, v) = http_with(&self.ep, "/api/login", None, Some(&body), timeout)
            .await
            .map_err(login)?;
        let session = match (st, crate::text_field(&v, "session")) {
            (200, Some(s)) => s,
            (st, _) => return Err(login(Error::Transport(format!("/api/login: HTTP {st}")))),
        };
        let gw = Gateway {
            ep: self.ep,
            session,
        };
        let me = gw.me().await.map_err(login)?;
        if me.sub != user {
            return Err(login(Error::Transport(format!(
                "/api/me names {:?}, not {user:?}",
                me.sub
            ))));
        }
        Ok(gw)
    }
}

/// Steps 1 and 2 of the head of this module for the gateway at `url`
/// (`https://host[:port]`) and the setup code as the person typed it.
pub async fn begin(url: &str, code: &str) -> Result<Pending, SetupError> {
    let (tls, host, port) = crate::endpoint_parts(url).map_err(SetupError::Url)?;
    if !tls {
        return Err(SetupError::Url("plain HTTP".into()));
    }
    let bare = host
        .trim_start_matches('[')
        .trim_end_matches(']')
        .to_owned();

    // 1. not yet trusted: read what the device offers, check the proof
    let any = Endpoint {
        host: host.clone(),
        port,
        tls: Some((
            tokio_rustls::TlsConnector::from(Arc::new(unverified_config()?)),
            rustls::pki_types::ServerName::try_from(bare.clone())
                .map_err(|e| SetupError::Url(format!("gateway url: {e}")))?,
        )),
    };
    let (st, info) = http_with(&any, "/api/info", None, None, crate::REQUEST_TIMEOUT).await?;
    if st != 200 {
        return Err(Error::Transport(format!("/api/info: HTTP {st}")).into());
    }
    let offer = read_offer(&info, code)?;

    // 2. the proven CA alone, and one of the certificate's names
    let name = server_name(&bare, &offer.names).ok_or(SetupError::NoName)?;
    let server = rustls::pki_types::ServerName::try_from(name.clone())
        .ok()
        .ok_or(SetupError::NoName)?;
    let ep = Endpoint {
        host,
        port,
        tls: Some((
            tokio_rustls::TlsConnector::from(Arc::new(pinned_config(&offer.ca_der)?)),
            server,
        )),
    };
    let (st, again) = http_with(&ep, "/api/info", None, None, crate::REQUEST_TIMEOUT).await?;
    if st != 200 {
        return Err(Error::Transport(format!("/api/info: HTTP {st}")).into());
    }
    match read_offer(&again, code) {
        Ok(o) if o.ca_der == offer.ca_der => {}
        _ => return Err(SetupError::Changed),
    }
    Ok(Pending { ep, offer, name })
}

fn provider() -> Arc<rustls::crypto::CryptoProvider> {
    Arc::new(rustls::crypto::ring::default_provider())
}

/// TLS that trusts `ca_der` alone.
fn pinned_config(ca_der: &[u8]) -> Result<rustls::ClientConfig, Error> {
    let mut roots = rustls::RootCertStore::empty();
    roots
        .add(rustls::pki_types::CertificateDer::from(ca_der.to_vec()))
        .map_err(|e| Error::Transport(format!("the CA of /api/info: {e}")))?;
    let mut cfg = rustls::ClientConfig::builder_with_provider(provider())
        .with_safe_default_protocol_versions()
        .map_err(transport)?
        .with_root_certificates(roots)
        .with_no_client_auth();
    cfg.alpn_protocols = vec![b"http/1.1".to_vec()];
    Ok(cfg)
}

/// TLS that takes any certificate (the handshake's signatures are still checked): for the
/// one `GET /api/info` whose answer is then proven by the setup code. Nothing is sent over
/// it but that request.
fn unverified_config() -> Result<rustls::ClientConfig, Error> {
    let p = provider();
    let mut cfg = rustls::ClientConfig::builder_with_provider(p.clone())
        .with_safe_default_protocol_versions()
        .map_err(transport)?
        .dangerous()
        .with_custom_certificate_verifier(Arc::new(AnyCert(p)))
        .with_no_client_auth();
    cfg.alpn_protocols = vec![b"http/1.1".to_vec()];
    Ok(cfg)
}

/// Any server certificate, the handshake's signatures checked.
#[derive(Debug)]
struct AnyCert(Arc<rustls::crypto::CryptoProvider>);

impl rustls::client::danger::ServerCertVerifier for AnyCert {
    fn verify_server_cert(
        &self,
        _end_entity: &rustls::pki_types::CertificateDer<'_>,
        _intermediates: &[rustls::pki_types::CertificateDer<'_>],
        _server_name: &rustls::pki_types::ServerName<'_>,
        _ocsp_response: &[u8],
        _now: rustls::pki_types::UnixTime,
    ) -> Result<rustls::client::danger::ServerCertVerified, rustls::Error> {
        Ok(rustls::client::danger::ServerCertVerified::assertion())
    }

    fn verify_tls12_signature(
        &self,
        message: &[u8],
        cert: &rustls::pki_types::CertificateDer<'_>,
        dss: &rustls::DigitallySignedStruct,
    ) -> Result<rustls::client::danger::HandshakeSignatureValid, rustls::Error> {
        rustls::crypto::verify_tls12_signature(
            message,
            cert,
            dss,
            &self.0.signature_verification_algorithms,
        )
    }

    fn verify_tls13_signature(
        &self,
        message: &[u8],
        cert: &rustls::pki_types::CertificateDer<'_>,
        dss: &rustls::DigitallySignedStruct,
    ) -> Result<rustls::client::danger::HandshakeSignatureValid, rustls::Error> {
        rustls::crypto::verify_tls13_signature(
            message,
            cert,
            dss,
            &self.0.signature_verification_algorithms,
        )
    }

    fn supported_verify_schemes(&self) -> Vec<rustls::SignatureScheme> {
        self.0.signature_verification_algorithms.supported_schemes()
    }
}

#[cfg(test)]
mod tests {
    #![allow(clippy::unwrap_used, clippy::panic, reason = "test code")]
    use super::*;

    fn info(setup: bool, ca: &[u8], proof: Option<[u8; 32]>) -> Value {
        let mut m = BTreeMap::from([
            ("site".to_owned(), Value::from("plant")),
            ("setup".to_owned(), Value::Bool(setup)),
            ("ca".to_owned(), Value::Bytes(ca.to_vec())),
            (
                "names".to_owned(),
                Value::Array(vec![
                    Value::from("10.0.2.15"),
                    Value::from("Wyrm-Plant.local"),
                    Value::from("plant-box.local"),
                ]),
            ),
        ]);
        if let Some(p) = proof {
            m.insert("setup_proof".to_owned(), Value::Bytes(p.to_vec()));
        }
        Value::Map(m)
    }

    fn code() -> (String, [u8; 32]) {
        wyrm_core::setup::code_of(&[7u8; 16])
    }

    #[test]
    fn a_proof_of_the_code_and_the_ca_is_taken() {
        let (code, hash) = code();
        let ca = b"the CA's DER".to_vec();
        let proof = wyrm_core::setup::setup_proof(&hash, &ca);
        let offer = read_offer(&info(true, &ca, Some(proof)), &code.to_lowercase()).unwrap();
        assert_eq!(offer.ca_der, ca);
        assert_eq!(offer.ca_fp, ca_fingerprint(&ca));
        assert_eq!(offer.site, "plant");
        assert_eq!(
            offer.names,
            ["10.0.2.15", "wyrm-plant.local", "plant-box.local"]
        );
    }

    #[test]
    fn another_code_or_another_ca_is_refused() {
        let (code, hash) = code();
        let ca = b"the CA's DER".to_vec();
        let proof = wyrm_core::setup::setup_proof(&hash, &ca);
        let (other, other_hash) = wyrm_core::setup::code_of(&[9u8; 16]);
        // a mistyped code
        assert!(matches!(
            read_offer(&info(true, &ca, Some(proof)), &other),
            Err(SetupError::ProofMismatch)
        ));
        assert!(matches!(
            read_offer(&info(true, &ca, Some(proof)), "not a code"),
            Err(SetupError::ProofMismatch)
        ));
        // another CA put in the device's place, with the device's proof or its own
        let swapped = b"another CA".to_vec();
        assert!(matches!(
            read_offer(&info(true, &swapped, Some(proof)), &code),
            Err(SetupError::ProofMismatch)
        ));
        let own = wyrm_core::setup::setup_proof(&other_hash, &swapped);
        assert!(matches!(
            read_offer(&info(true, &swapped, Some(own)), &code),
            Err(SetupError::ProofMismatch)
        ));
    }

    #[test]
    fn no_setup_and_no_proof_say_so() {
        let (code, hash) = code();
        let ca = b"ca".to_vec();
        let proof = wyrm_core::setup::setup_proof(&hash, &ca);
        assert!(matches!(
            read_offer(&info(false, &ca, Some(proof)), &code),
            Err(SetupError::NoSetup)
        ));
        assert!(matches!(
            read_offer(&info(true, &ca, None), &code),
            Err(SetupError::NoProof)
        ));
        assert!(matches!(
            read_offer(&Value::Map(BTreeMap::new()), &code),
            Err(SetupError::NoSetup)
        ));
    }

    #[test]
    fn the_name_checked_is_the_url_host_else_the_announced_one() {
        let names: Vec<String> = ["10.0.2.15", "wyrm-plant.local", "plant-box.local"]
            .map(String::from)
            .to_vec();
        // reached by a name or an address the certificate carries: that one
        assert_eq!(server_name("10.0.2.15", &names).unwrap(), "10.0.2.15");
        assert_eq!(
            server_name("Plant-Box.local", &names).unwrap(),
            "plant-box.local"
        );
        // reached through a forward (127.0.0.1): the name the gateway announces
        assert_eq!(
            server_name("127.0.0.1", &names).unwrap(),
            "wyrm-plant.local"
        );
        let plain: Vec<String> = ["192.168.1.9", "box.lan"].map(String::from).to_vec();
        assert_eq!(server_name("127.0.0.1", &plain).unwrap(), "box.lan");
        let only_ip: Vec<String> = ["192.168.1.9".to_owned()].to_vec();
        assert_eq!(server_name("127.0.0.1", &only_ip).unwrap(), "192.168.1.9");
        assert_eq!(server_name("[::1]", &["::1".to_owned()]).unwrap(), "::1");
        assert_eq!(server_name("127.0.0.1", &[]), None);
    }

    #[test]
    fn plain_http_is_refused() {
        let rt = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .unwrap();
        for url in [
            "http://127.0.0.1:8445",
            "127.0.0.1:8445",
            "https://h/x",
            "ftp://h",
        ] {
            assert!(
                matches!(rt.block_on(begin(url, "x")), Err(SetupError::Url(_))),
                "{url}"
            );
        }
    }
}
