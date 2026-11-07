//! The lease arbiter of a standby pair (ADR 0036, amendment 2026-11-08).
//!
//! A witness (`standby.witness`) is a TCP port: it tells a host whether it
//! reaches the plant, not whether the other host is active. Two hosts that
//! both reach a witness but not each other (a firewall between them, a
//! hung process) would both be active. An arbiter holds the one thing a
//! port cannot: who has the role. It runs on a third host
//! (`wyrmd arbiter serve`) and grants one lease per site, for a time:
//!
//! * a standby takes over only once it holds the lease of a majority of
//!   `standby.arbiter`;
//! * the active renews it every second; told that another host holds it,
//!   it steps down at once; unable to renew it (no answer), it steps down
//!   when the lease runs out and its standby has stopped asking (a standby
//!   that asks follows it and cannot take over);
//! * after its own start the arbiter grants nothing for [`MAX_TTL`]: a
//!   lease it forgot may still run on a broker.
//!
//! The link is TLS over TCP with the site CA on both ends: the arbiter's
//! certificate is `arbiter:<site>` (`wyrmd arbiter issue`), a broker's is
//! its `standby:<site>` one; nothing else of the site's CA (links, brokers
//! of downstream sites) may hold a lease. One request per connection, a
//! frame of `u32` big-endian length + canonical CBOR (`wyrm_core::codec`):
//! `{op: "hold" | "release", holder, ttl_ms}` →
//! `{state: "granted" | "held" | "recovering" | "released", holder?, left_ms}`.

use crate::{Config, Error};
use rustls_pki_types::pem::PemObject;
use rustls_pki_types::{CertificateDer, PrivateKeyDer, ServerName};
use std::collections::BTreeMap;
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};
use std::time::Duration;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::time::Instant;
use wyrm_core::Value;

/// Longest lease a broker may ask for, and how long a started arbiter
/// grants nothing.
pub const MAX_TTL: Duration = Duration::from_secs(30);
/// Shortest lease (a renewal is sent every second).
pub const MIN_TTL: Duration = Duration::from_secs(3);
/// One request (connect, handshake, answer) may take this long.
const TIMEOUT: Duration = Duration::from_secs(1);
/// Largest frame either side reads.
const MAX_FRAME: u32 = 4096;
/// Longest holder name.
const MAX_HOLDER: usize = 64;

/// What the arbiter answers.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Answer {
    /// The caller holds the lease for `left`.
    Granted { left: Duration },
    /// Another holder has it for `left`.
    Held { holder: String, left: Duration },
    /// The arbiter started less than [`MAX_TTL`] ago: no grant yet.
    Recovering { left: Duration },
    /// The caller's lease is given up (or it had none).
    Released,
}

/// The lease of one site, as the arbiter keeps it (in memory only).
#[derive(Debug)]
pub struct Lease {
    /// No grant before this (a lease forgotten by a restart may still run).
    recovered: Instant,
    holder: Option<(String, Instant)>,
}

impl Lease {
    pub fn new(now: Instant) -> Self {
        Self::with_grace(now, MAX_TTL)
    }

    /// A lease that grants nothing for `grace` (tests: less than [`MAX_TTL`]).
    pub fn with_grace(now: Instant, grace: Duration) -> Self {
        Self {
            recovered: now + grace,
            holder: None,
        }
    }

    /// Grant or renew `who`'s lease for `ttl` (capped), unless another holds
    /// one that has not run out.
    pub fn hold(&mut self, now: Instant, who: &str, ttl: Duration) -> Answer {
        let ttl = ttl.clamp(MIN_TTL, MAX_TTL);
        let recovered = self.recovered;
        if now < recovered {
            return Answer::Recovering {
                left: recovered - now,
            };
        }
        if let Some((h, until)) = &self.holder {
            if h != who && *until > now {
                return Answer::Held {
                    holder: h.clone(),
                    left: *until - now,
                };
            }
        }
        self.holder = Some((who.to_owned(), now + ttl));
        Answer::Granted { left: ttl }
    }

    /// Give `who`'s lease up; another holder's stays.
    pub fn release(&mut self, who: &str) -> Answer {
        if self.holder.as_ref().is_some_and(|(h, _)| h == who) {
            self.holder = None;
        }
        Answer::Released
    }
}

fn answer_value(a: &Answer) -> Value {
    let (state, holder, left) = match a {
        Answer::Granted { left } => ("granted", None, *left),
        Answer::Held { holder, left } => ("held", Some(holder.clone()), *left),
        Answer::Recovering { left } => ("recovering", None, *left),
        Answer::Released => ("released", None, Duration::ZERO),
    };
    let mut m = BTreeMap::from([
        ("state".to_owned(), Value::from(state)),
        ("left_ms".to_owned(), Value::UInt(left.as_millis() as u64)),
    ]);
    if let Some(h) = holder {
        m.insert("holder".to_owned(), Value::from(h));
    }
    Value::Map(m)
}

fn parse_answer(v: Value) -> Option<Answer> {
    let Value::Map(mut m) = v else { return None };
    let Some(Value::UInt(ms)) = m.remove("left_ms") else {
        return None;
    };
    let left = Duration::from_millis(ms);
    match m.remove("state") {
        Some(Value::Str(s)) => match s.as_str() {
            "granted" => Some(Answer::Granted { left }),
            "held" => match m.remove("holder") {
                Some(Value::Str(holder)) => Some(Answer::Held { holder, left }),
                _ => None,
            },
            "recovering" => Some(Answer::Recovering { left }),
            "released" => Some(Answer::Released),
            _ => None,
        },
        _ => None,
    }
}

fn request_value(op: &str, holder: &str, ttl: Duration) -> Value {
    Value::Map(BTreeMap::from([
        ("op".to_owned(), Value::from(op)),
        ("holder".to_owned(), Value::from(holder)),
        ("ttl_ms".to_owned(), Value::UInt(ttl.as_millis() as u64)),
    ]))
}

/// `(op, holder, ttl)` of a request.
fn parse_request(v: Value) -> Option<(String, String, Duration)> {
    let Value::Map(mut m) = v else { return None };
    let (Some(Value::Str(op)), Some(Value::Str(holder)), Some(Value::UInt(ttl))) =
        (m.remove("op"), m.remove("holder"), m.remove("ttl_ms"))
    else {
        return None;
    };
    let ok = !holder.is_empty()
        && holder.len() <= MAX_HOLDER
        && holder
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || c == '-');
    ok.then(|| (op, holder, Duration::from_millis(ttl)))
}

async fn read_frame<R: AsyncReadExt + Unpin>(r: &mut R) -> Result<Value, String> {
    let n = r.read_u32().await.map_err(|e| e.to_string())?;
    if n > MAX_FRAME {
        return Err(format!("frame of {n} bytes"));
    }
    let mut buf = vec![0u8; n as usize];
    r.read_exact(&mut buf).await.map_err(|e| e.to_string())?;
    wyrm_core::codec::from_slice(&buf).map_err(|e| e.to_string())
}

async fn write_frame<W: AsyncWriteExt + Unpin>(w: &mut W, v: &Value) -> Result<(), String> {
    let bytes = wyrm_core::codec::to_vec(v).map_err(|e| e.to_string())?;
    w.write_u32(bytes.len() as u32)
        .await
        .map_err(|e| e.to_string())?;
    w.write_all(&bytes).await.map_err(|e| e.to_string())?;
    w.flush().await.map_err(|e| e.to_string())
}

fn certs(path: &Path) -> Result<Vec<CertificateDer<'static>>, Error> {
    CertificateDer::pem_file_iter(path)
        .map_err(|e| format!("{}: {e}", path.display()))?
        .collect::<Result<Vec<_>, _>>()
        .map_err(|e| format!("{}: {e}", path.display()).into())
}

fn roots(ca: &Path) -> Result<rustls::RootCertStore, Error> {
    let mut store = rustls::RootCertStore::empty();
    for c in certs(ca)? {
        store.add(c).map_err(|e| format!("{}: {e}", ca.display()))?;
    }
    Ok(store)
}

fn provider() -> Arc<rustls::crypto::CryptoProvider> {
    Arc::new(rustls::crypto::ring::default_provider())
}

/// The common name of a DER certificate.
fn common_name(der: &[u8]) -> Option<String> {
    let (_, cert) = x509_parser::parse_x509_certificate(der).ok()?;
    let cn = cert
        .subject()
        .iter_common_name()
        .next()?
        .as_str()
        .ok()?
        .to_owned();
    Some(cn)
}

/// The files of an arbiter, in its own directory (`wyrmd arbiter issue`).
pub struct ArbiterFiles {
    pub dir: PathBuf,
}

impl ArbiterFiles {
    fn ca(&self) -> PathBuf {
        self.dir.join("ca.pem")
    }
    fn cert(&self) -> PathBuf {
        self.dir.join("arbiter.pem")
    }
    fn key(&self) -> PathBuf {
        self.dir.join("arbiter.key")
    }
    fn site(&self) -> PathBuf {
        self.dir.join("site")
    }
}

/// Write an arbiter's directory from this broker's site CA: the CA
/// certificate, `arbiter.{pem,key}` for `host` (a DNS name or an address
/// the brokers dial), and the site name. Run on a broker of the pair; the
/// directory then goes to the arbiter's host.
pub fn issue(cfg: &Config, host: &str, out: &Path) -> Result<(), Error> {
    if host.is_empty() || host.contains([':', '/', ' ']) {
        return Err(format!("{host:?}: a host name or an IPv4 address").into());
    }
    let pki = wyrm_admin::secret::Pki::open_or_create(&cfg.data_dir.join("pki"))?;
    std::fs::create_dir_all(out)?;
    pki.issue(
        &format!("arbiter:{}", cfg.site),
        &[host.to_owned()],
        true,
        out,
        "arbiter",
    )?;
    let files = ArbiterFiles {
        dir: out.to_path_buf(),
    };
    std::fs::copy(pki.ca_path(), files.ca())?;
    std::fs::write(files.site(), &cfg.site)?;
    Ok(())
}

/// Serve the lease of the site in `dir` on `listen` until `shutdown`.
pub async fn serve(
    dir: &Path,
    listen: &str,
    shutdown: impl std::future::Future<Output = ()>,
) -> Result<(), Error> {
    serve_with(dir, listen, MAX_TTL, shutdown).await
}

/// [`serve`] with no grant for `grace` after the start ([`MAX_TTL`] in
/// production: shorter only in tests).
pub async fn serve_with(
    dir: &Path,
    listen: &str,
    grace: Duration,
    shutdown: impl std::future::Future<Output = ()>,
) -> Result<(), Error> {
    let files = ArbiterFiles {
        dir: dir.to_path_buf(),
    };
    let site = std::fs::read_to_string(files.site())
        .map_err(|e| format!("{}: {e}", files.site().display()))?
        .trim()
        .to_owned();
    let verifier = rustls::server::WebPkiClientVerifier::builder_with_provider(
        roots(&files.ca())?.into(),
        provider(),
    )
    .build()
    .map_err(|e| format!("client verifier: {e}"))?;
    let key = PrivateKeyDer::from_pem_file(files.key())
        .map_err(|e| format!("{}: {e}", files.key().display()))?;
    let tls = rustls::ServerConfig::builder_with_provider(provider())
        .with_safe_default_protocol_versions()
        .map_err(|e| e.to_string())?
        .with_client_cert_verifier(verifier)
        .with_single_cert(certs(&files.cert())?, key)
        .map_err(|e| format!("arbiter certificate: {e}"))?;
    let acceptor = tokio_rustls::TlsAcceptor::from(Arc::new(tls));
    let listener = tokio::net::TcpListener::bind(listen)
        .await
        .map_err(|e| format!("{listen}: {e}"))?;
    let lease = Arc::new(Mutex::new(Lease::with_grace(Instant::now(), grace)));
    let want = format!("standby:{site}");
    tracing::info!(%site, %listen, "arbiter: serving; no grant for the first {}s", grace.as_secs());
    tokio::pin!(shutdown);
    loop {
        let (tcp, from) = tokio::select! {
            _ = &mut shutdown => return Ok(()),
            r = listener.accept() => match r {
                Ok(c) => c,
                Err(e) => {
                    tracing::warn!("arbiter: accept: {e}");
                    tokio::time::sleep(Duration::from_millis(100)).await;
                    continue;
                }
            },
        };
        let (acceptor, lease, want) = (acceptor.clone(), lease.clone(), want.clone());
        tokio::spawn(async move {
            let r = tokio::time::timeout(TIMEOUT * 3, async {
                let mut s = acceptor.accept(tcp).await.map_err(|e| e.to_string())?;
                let cn = s
                    .get_ref()
                    .1
                    .peer_certificates()
                    .and_then(|c| c.first())
                    .and_then(|c| common_name(c));
                if cn.as_deref() != Some(want.as_str()) {
                    return Err(format!("certificate {cn:?}: not {want}"));
                }
                let (op, holder, ttl) =
                    parse_request(read_frame(&mut s).await?).ok_or("bad request")?;
                let a = {
                    let mut l = lease.lock().unwrap_or_else(|p| p.into_inner());
                    match op.as_str() {
                        "hold" => l.hold(Instant::now(), &holder, ttl),
                        "release" => l.release(&holder),
                        _ => return Err(format!("op {op:?}")),
                    }
                };
                if !matches!(a, Answer::Granted { .. }) || op != "hold" {
                    tracing::debug!(%holder, %op, ?a, "arbiter");
                }
                write_frame(&mut s, &answer_value(&a)).await?;
                let _ = s.shutdown().await;
                Ok::<(), String>(())
            })
            .await;
            match r {
                Ok(Ok(())) => {}
                Ok(Err(e)) => tracing::debug!(%from, "arbiter: {e}"),
                Err(_) => tracing::debug!(%from, "arbiter: too slow"),
            }
        });
    }
}

/// What a broker learns from its arbiters.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Verdict {
    /// A majority granted the lease.
    Granted,
    /// Enough of them have another holder that no majority can grant it.
    Lost,
    /// Neither (no answer, recovering arbiters).
    Unknown,
}

/// A broker's side: its arbiters and its holder name.
#[derive(Clone)]
pub struct Arbiters {
    list: Vec<String>,
    holder: String,
    tls: tokio_rustls::TlsConnector,
    ttl: Duration,
}

impl Arbiters {
    /// The arbiters of `cfg.standby`, `None` without any.
    pub fn of(cfg: &Config) -> Result<Option<Self>, Error> {
        let Some(sb) = cfg.standby.as_ref().filter(|s| !s.arbiter.is_empty()) else {
            return Ok(None);
        };
        let cert = crate::standby::standby_cert(cfg)?;
        let key = PrivateKeyDer::from_pem_file(&cert.key)
            .map_err(|e| format!("{}: {e}", cert.key.display()))?;
        let tls = rustls::ClientConfig::builder_with_provider(provider())
            .with_safe_default_protocol_versions()
            .map_err(|e| e.to_string())?
            .with_root_certificates(roots(&cfg.data_dir.join("pki/ca.pem"))?)
            .with_client_auth_cert(certs(&cert.cert)?, key)
            .map_err(|e| format!("standby certificate: {e}"))?;
        Ok(Some(Self {
            list: sb.arbiter.clone(),
            holder: host_id(&cfg.data_dir)?,
            tls: tokio_rustls::TlsConnector::from(Arc::new(tls)),
            ttl: sb.lease_ttl(),
        }))
    }

    /// The lease time this broker asks for.
    pub fn ttl(&self) -> Duration {
        self.ttl
    }

    async fn one(&self, addr: &str, op: &str) -> Option<Answer> {
        let host = addr
            .rsplit_once(':')?
            .0
            .trim_start_matches('[')
            .trim_end_matches(']');
        let name = ServerName::try_from(host.to_owned()).ok()?;
        tokio::time::timeout(TIMEOUT, async {
            let tcp = tokio::net::TcpStream::connect(addr).await.ok()?;
            let mut s = self.tls.connect(name, tcp).await.ok()?;
            write_frame(&mut s, &request_value(op, &self.holder, self.ttl))
                .await
                .ok()?;
            parse_answer(read_frame(&mut s).await.ok()?)
        })
        .await
        .ok()
        .flatten()
    }

    async fn all(&self, op: &str) -> Vec<Option<Answer>> {
        let mut set = tokio::task::JoinSet::new();
        for (i, a) in self.list.iter().enumerate() {
            let (me, a, op) = (self.clone(), a.clone(), op.to_owned());
            set.spawn(async move { (i, me.one(&a, &op).await) });
        }
        let mut out = vec![None; self.list.len()];
        while let Some(r) = set.join_next().await {
            if let Ok((i, a)) = r {
                out[i] = a;
            }
        }
        out
    }

    /// Ask every arbiter for the lease (or renew it).
    pub async fn hold(&self) -> Verdict {
        let answers = self.all("hold").await;
        let verdict = tally(&answers);
        if verdict != Verdict::Granted {
            if let Some(Some(Answer::Held { holder, .. })) = answers
                .iter()
                .find(|a| matches!(a, Some(Answer::Held { .. })))
            {
                tracing::debug!(%holder, "arbiter: the lease is held by another broker");
            }
        }
        verdict
    }

    /// Take the lease for a takeover: a majority, or none (the grants of a
    /// minority are given back so that they do not block the other host).
    pub async fn acquire(&self) -> Verdict {
        let v = self.hold().await;
        if v != Verdict::Granted {
            self.release().await;
        }
        v
    }

    /// Give the lease up (a step-down, a stop).
    pub async fn release(&self) {
        let _ = self.all("release").await;
    }
}

/// A majority of grants is [`Verdict::Granted`]; so many held by another
/// that no majority is left is [`Verdict::Lost`].
fn tally(answers: &[Option<Answer>]) -> Verdict {
    let n = answers.len();
    let need = n / 2 + 1;
    let granted = answers
        .iter()
        .filter(|a| matches!(a, Some(Answer::Granted { .. })))
        .count();
    let held = answers
        .iter()
        .filter(|a| matches!(a, Some(Answer::Held { .. })))
        .count();
    if granted >= need {
        Verdict::Granted
    } else if held > n - need {
        Verdict::Lost
    } else {
        Verdict::Unknown
    }
}

/// This host's holder name: random, made once, kept in
/// `standby/host.id` (not replicated: each host of a pair has its own).
pub fn host_id(data_dir: &Path) -> Result<String, Error> {
    let path = crate::standby::standby_dir(data_dir).join("host.id");
    if let Ok(t) = std::fs::read_to_string(&path) {
        let t = t.trim();
        if !t.is_empty() && t.len() <= MAX_HOLDER && t.chars().all(|c| c.is_ascii_hexdigit()) {
            return Ok(t.to_owned());
        }
    }
    let mut b = [0u8; 8];
    getrandom::fill(&mut b).map_err(|e| format!("random: {e}"))?;
    let id = hex::encode(b);
    wyrm_admin::secret::write_private(&path, id.as_bytes())?;
    Ok(id)
}

/// The lease as the active broker keeps it: renewed every second by
/// [`keep`]; `lost` once another holder has it.
#[derive(Debug, Default)]
pub struct Held {
    /// Until when this host may count on it (the send time of the last
    /// granted renewal plus the lease, less a second: the arbiter counts
    /// from when it read the request, later).
    pub until: Option<std::time::Instant>,
    pub lost: bool,
}

/// Renew the lease every second into `state` until the task is dropped.
/// `granted_at` is when the lease was taken (by [`Arbiters::acquire`]).
pub async fn keep(arb: Arbiters, state: Arc<Mutex<Held>>, granted_at: std::time::Instant) {
    let margin = Duration::from_secs(1);
    state.lock().unwrap_or_else(|p| p.into_inner()).until =
        Some(granted_at + arb.ttl().saturating_sub(margin));
    let mut tick = tokio::time::interval(Duration::from_secs(1));
    tick.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Delay);
    loop {
        tick.tick().await;
        let sent = std::time::Instant::now();
        let v = arb.hold().await;
        let mut s = state.lock().unwrap_or_else(|p| p.into_inner());
        match v {
            Verdict::Granted => s.until = Some(sent + arb.ttl().saturating_sub(margin)),
            Verdict::Lost => {
                if !s.lost {
                    tracing::warn!("arbiter: another broker holds the lease");
                }
                s.lost = true;
            }
            Verdict::Unknown => {}
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_lease_is_granted_renewed_held_and_released() {
        let t0 = Instant::now();
        let mut l = Lease::new(t0);
        let ttl = Duration::from_secs(5);
        assert!(
            matches!(l.hold(t0, "a", ttl), Answer::Recovering { .. }),
            "just started"
        );
        let t = t0 + MAX_TTL;
        assert_eq!(l.hold(t, "a", ttl), Answer::Granted { left: ttl });
        assert_eq!(
            l.hold(t + Duration::from_secs(1), "b", ttl),
            Answer::Held {
                holder: "a".into(),
                left: Duration::from_secs(4)
            }
        );
        // renewed by its holder
        assert_eq!(
            l.hold(t + Duration::from_secs(4), "a", ttl),
            Answer::Granted { left: ttl }
        );
        assert!(matches!(
            l.hold(t + Duration::from_secs(8), "b", ttl),
            Answer::Held { .. }
        ));
        // run out: the other host gets it
        assert_eq!(
            l.hold(t + Duration::from_secs(9), "b", ttl),
            Answer::Granted { left: ttl }
        );
        assert_eq!(l.release("a"), Answer::Released, "not a's: b keeps it");
        assert!(matches!(
            l.hold(t + Duration::from_secs(10), "a", ttl),
            Answer::Held { .. }
        ));
        l.release("b");
        assert!(matches!(
            l.hold(t + Duration::from_secs(10), "a", ttl),
            Answer::Granted { .. }
        ));
        // the time asked for is bounded
        assert_eq!(
            l.hold(t + Duration::from_secs(11), "a", Duration::from_secs(3600)),
            Answer::Granted { left: MAX_TTL }
        );
        assert_eq!(
            l.hold(t + Duration::from_secs(11), "a", Duration::ZERO),
            Answer::Granted { left: MIN_TTL }
        );
    }

    #[test]
    fn frames_roundtrip() {
        for a in [
            Answer::Granted {
                left: Duration::from_millis(5),
            },
            Answer::Held {
                holder: "ab12".into(),
                left: Duration::from_millis(7),
            },
            Answer::Recovering {
                left: Duration::from_secs(3),
            },
            Answer::Released,
        ] {
            assert_eq!(parse_answer(answer_value(&a)), Some(a));
        }
        let r = parse_request(request_value("hold", "ab12", Duration::from_secs(5))).unwrap();
        assert_eq!(r, ("hold".into(), "ab12".into(), Duration::from_secs(5)));
        assert!(parse_request(request_value("hold", "", Duration::ZERO)).is_none());
        assert!(parse_request(request_value("hold", "a b", Duration::ZERO)).is_none());
        assert!(parse_request(request_value("hold", &"a".repeat(65), Duration::ZERO)).is_none());
    }

    #[test]
    fn a_majority_decides() {
        let g = Some(Answer::Granted { left: MIN_TTL });
        let h = Some(Answer::Held {
            holder: "x".into(),
            left: MIN_TTL,
        });
        let r = Some(Answer::Recovering { left: MIN_TTL });
        assert_eq!(tally(std::slice::from_ref(&g)), Verdict::Granted);
        assert_eq!(tally(std::slice::from_ref(&h)), Verdict::Lost);
        assert_eq!(tally(&[None]), Verdict::Unknown);
        assert_eq!(tally(std::slice::from_ref(&r)), Verdict::Unknown);
        assert_eq!(tally(&[g.clone(), g.clone(), None]), Verdict::Granted);
        assert_eq!(tally(&[g.clone(), h.clone(), None]), Verdict::Unknown);
        assert_eq!(tally(&[g.clone(), h.clone(), h.clone()]), Verdict::Lost);
        assert_eq!(
            tally(&[g.clone(), h.clone()]),
            Verdict::Lost,
            "two: both are needed"
        );
        assert_eq!(tally(&[g, None]), Verdict::Unknown);
    }
}
