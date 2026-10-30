//! One SNMP session over a connected UDP socket: v2c (community) or v3
//! (USM: engine discovery, time window, HMAC, AES-128).
//!
//! Every request carries a fresh request id (and, on v3, the same msgID);
//! only a reply with one of the ids sent for that request is taken, so a
//! reply that comes after its timeout is dropped and counted
//! (`late_replies`), never taken for a later request. A timeout sends the
//! request again (new id) up to `retries` times. No datagram is ever
//! logged: a v2c datagram holds the community.

use std::net::SocketAddr;
use std::time::Duration;
use tokio::net::UdpSocket;
use tokio::time::Instant;
use tracing::debug;
use wyrm_link_sdk::driver::{DriverError, Outcome};
use zeroize::Zeroizing;

use crate::ber::{Oid, SnmpValue};
use crate::msg::{self, Message, Pdu, ScopedData, ScopedPdu, UsmOut};
use crate::usm::{self, Auth, ReportKind};

/// Diagnostics counter of replies dropped because their id was not the
/// one of the request waited for (late replies), or that did not
/// authenticate.
pub const LATE: &str = "late_replies";

/// `sysUpTime.0`: the ping and the probe of `open`.
pub const SYS_UPTIME: [u32; 9] = [1, 3, 6, 1, 2, 1, 1, 3, 0];

/// v3 credentials and the keys localized for the agent's engine.
pub struct V3 {
    pub user: Vec<u8>,
    pub auth: Auth,
    pub auth_pass: Zeroizing<Vec<u8>>,
    /// AES-128 privacy passphrase; `None` = authNoPriv.
    pub priv_pass: Option<Zeroizing<Vec<u8>>>,
}

pub enum Security {
    V2c { community: Zeroizing<Vec<u8>> },
    V3(V3),
}

/// The agent's engine as discovered, and our keys for it.
struct Engine {
    id: Vec<u8>,
    boots: u32,
    time: u32,
    /// When `time` was learned.
    at: Instant,
    auth_key: Zeroizing<Vec<u8>>,
    priv_key: Option<Zeroizing<[u8; 16]>>,
}

impl Engine {
    fn now(&self) -> (u32, u32) {
        let secs = u32::try_from(self.at.elapsed().as_secs()).unwrap_or(u32::MAX);
        (self.boots, self.time.saturating_add(secs))
    }
}

/// Where a request goes on the agent: a community (v2c; `None` = the
/// connection's) or a context name (v3).
#[derive(Clone, Copy, Default)]
pub struct Scope<'a> {
    pub community: Option<&'a [u8]>,
    pub context: &'a [u8],
}

pub struct Session {
    sock: UdpSocket,
    pub timeout: Duration,
    pub retries: u8,
    next_id: u32,
    salt: u64,
    sec: Security,
    engine: Option<Engine>,
    outcomes: Vec<Outcome>,
    buf: Vec<u8>,
}

fn random_u64() -> u64 {
    let mut b = [0u8; 8];
    if getrandom::fill(&mut b).is_err() {
        // Not for secrecy: ids only need to differ between sessions.
        let n = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_nanos())
            .unwrap_or(0);
        return u64::try_from(n & u128::from(u64::MAX)).unwrap_or(0) ^ 0x9E37_79B9_7F4A_7C15;
    }
    u64::from_be_bytes(b)
}

/// A failed request as the framework sees it.
enum Fail {
    /// Send again (a time window resync).
    Again,
    Error(DriverError),
}

impl Session {
    /// Bind a socket to `addr` and, as a probe, ask for `sysUpTime.0`
    /// (v3: discover the engine first). No answer means the agent cannot be
    /// reached: `open` fails (UDP has no connection to set up).
    pub async fn open(
        addr: SocketAddr,
        timeout: Duration,
        retries: u8,
        sec: Security,
    ) -> Result<Session, DriverError> {
        let local: SocketAddr = if addr.is_ipv4() {
            "0.0.0.0:0".parse().map_err(|_| transport("bind"))?
        } else {
            "[::]:0".parse().map_err(|_| transport("bind"))?
        };
        let sock = UdpSocket::bind(local)
            .await
            .map_err(|e| DriverError::Transport(format!("bind: {e}")))?;
        sock.connect(addr)
            .await
            .map_err(|e| DriverError::Transport(format!("connect {addr}: {e}")))?;
        let seed = random_u64();
        let mut s = Session {
            sock,
            timeout,
            retries,
            next_id: u32::try_from(seed >> 33).unwrap_or(1),
            salt: random_u64(),
            sec,
            engine: None,
            outcomes: Vec::new(),
            buf: vec![0u8; msg::MAX_MESSAGE + 64],
        };
        if matches!(s.sec, Security::V3(_)) {
            s.discover().await.map_err(as_transport)?;
        }
        let probe = Oid(SYS_UPTIME.to_vec());
        let r = s
            .request(
                msg::GET,
                0,
                0,
                vec![(probe, SnmpValue::Null)],
                Scope::default(),
            )
            .await;
        match r {
            Ok(_) => Ok(s),
            Err(e) => Err(as_transport(e)),
        }
    }

    pub fn take_outcomes(&mut self) -> Vec<Outcome> {
        std::mem::take(&mut self.outcomes)
    }

    pub fn is_v3(&self) -> bool {
        matches!(self.sec, Security::V3(_))
    }

    /// Whether requests are encrypted (v3 authPriv).
    pub fn is_private(&self) -> bool {
        matches!(&self.sec, Security::V3(v) if v.priv_pass.is_some())
    }

    fn id(&mut self) -> i32 {
        self.next_id = self.next_id.wrapping_add(1) & 0x7FFF_FFFF;
        if self.next_id == 0 {
            self.next_id = 1;
        }
        i32::try_from(self.next_id).unwrap_or(1)
    }

    /// GET of `oids`.
    pub async fn get(&mut self, scope: Scope<'_>, oids: &[Oid]) -> Result<Pdu, DriverError> {
        let vbs = oids.iter().map(|o| (o.clone(), SnmpValue::Null)).collect();
        self.request(msg::GET, 0, 0, vbs, scope).await
    }

    /// GETBULK of `oids` (all repeaters).
    pub async fn get_bulk(
        &mut self,
        scope: Scope<'_>,
        max_repetitions: i32,
        oids: &[Oid],
    ) -> Result<Pdu, DriverError> {
        let vbs = oids.iter().map(|o| (o.clone(), SnmpValue::Null)).collect();
        self.request(msg::GET_BULK, 0, max_repetitions, vbs, scope)
            .await
    }

    pub async fn set(
        &mut self,
        scope: Scope<'_>,
        varbinds: Vec<(Oid, SnmpValue)>,
    ) -> Result<Pdu, DriverError> {
        self.request(msg::SET, 0, 0, varbinds, scope).await
    }

    /// One request with retries; the answer may carry an error status (the
    /// caller decides) but never a report (those are errors here).
    pub async fn request(
        &mut self,
        ty: u8,
        status: i32,
        index: i32,
        varbinds: Vec<(Oid, SnmpValue)>,
        scope: Scope<'_>,
    ) -> Result<Pdu, DriverError> {
        let mut resynced = false;
        let mut ids: Vec<i32> = Vec::new();
        let mut attempt = 0u8;
        loop {
            let id = self.id();
            ids.push(id);
            let pdu = Pdu {
                ty,
                request_id: id,
                error_status: status,
                error_index: index,
                varbinds: varbinds.clone(),
            };
            let wire = self.build(&pdu, scope).map_err(|e| match e {
                Fail::Error(e) => e,
                Fail::Again => DriverError::Device("cannot build the request".into()),
            })?;
            let sent = Instant::now();
            if let Err(e) = self.sock.send(&wire).await {
                self.outcomes.push(Outcome::Error);
                return Err(io_err(&e));
            }
            match self.wait(&ids, sent).await {
                Ok(Some(p)) => {
                    let rtt = sent.elapsed();
                    self.outcomes.push(if p.error_status == 0 {
                        Outcome::Reply(rtt)
                    } else {
                        Outcome::Exception(rtt)
                    });
                    return Ok(p);
                }
                Ok(None) => {
                    self.outcomes.push(Outcome::Timeout);
                    if attempt >= self.retries {
                        return Err(DriverError::Device(format!(
                            "no answer from the agent ({} tries of {} ms)",
                            u32::from(attempt) + 1,
                            self.timeout.as_millis()
                        )));
                    }
                    attempt += 1;
                    debug!(attempt, "request timed out; sending it again");
                }
                Err(Fail::Again) if !resynced => {
                    self.outcomes.push(Outcome::Exception(sent.elapsed()));
                    resynced = true;
                    debug!("engine time resynchronized; sending again");
                }
                Err(Fail::Again) => {
                    self.outcomes.push(Outcome::Exception(sent.elapsed()));
                    return Err(DriverError::Device(
                        ReportKind::NotInTimeWindow.message().into(),
                    ));
                }
                Err(Fail::Error(e)) => {
                    self.outcomes.push(match e {
                        DriverError::Transport(_) => Outcome::Error,
                        _ => Outcome::Exception(sent.elapsed()),
                    });
                    return Err(e);
                }
            }
        }
    }

    /// Wait until `timeout` after `sent` for a reply to one of `ids`.
    /// `Ok(None)` = no reply in time.
    async fn wait(&mut self, ids: &[i32], sent: Instant) -> Result<Option<Pdu>, Fail> {
        let deadline = sent + self.timeout;
        loop {
            let n = match tokio::time::timeout_at(deadline, self.sock.recv(&mut self.buf)).await {
                Err(_) => return Ok(None),
                Ok(Err(e)) => return Err(Fail::Error(io_err(&e))),
                Ok(Ok(n)) => n,
            };
            let datagram = self.buf[..n].to_vec();
            match self.accept(&datagram, ids) {
                Ok(Some(p)) => return Ok(Some(p)),
                Ok(None) => {
                    self.outcomes.push(Outcome::Count(LATE));
                    debug!("dropped a reply that is not for this request");
                }
                Err(e) => return Err(e),
            }
        }
    }

    /// The message for `pdu`.
    fn build(&mut self, pdu: &Pdu, scope: Scope<'_>) -> Result<Vec<u8>, Fail> {
        match &self.sec {
            Security::V2c { community } => {
                let c = scope.community.unwrap_or(community);
                Ok(msg::encode_community(c, pdu))
            }
            Security::V3(v3) => {
                let Some(e) = &self.engine else {
                    return Err(Fail::Error(DriverError::Transport(
                        "engine not discovered".into(),
                    )));
                };
                let (boots, time) = e.now();
                let scoped = ScopedPdu {
                    engine_id: e.id.clone(),
                    context: scope.context.to_vec(),
                    pdu: pdu.clone(),
                }
                .encode();
                let mut flags = msg::FLAG_AUTH | msg::FLAG_REPORTABLE;
                let salt_bytes;
                let data = match &e.priv_key {
                    Some(k) => {
                        flags |= msg::FLAG_PRIV;
                        self.salt = self.salt.wrapping_add(1);
                        salt_bytes = self.salt.to_be_bytes();
                        let mut enc = scoped;
                        usm::encrypt(k, boots, time, &salt_bytes, &mut enc);
                        let mut d = Vec::with_capacity(enc.len() + 4);
                        crate::ber::tlv(&mut d, crate::ber::OCTET_STRING, &enc);
                        d
                    }
                    None => {
                        salt_bytes = [0; 8];
                        scoped
                    }
                };
                let priv_params: &[u8] = if e.priv_key.is_some() {
                    &salt_bytes
                } else {
                    &[]
                };
                let usm = UsmOut {
                    engine_id: &e.id,
                    boots,
                    time,
                    user: &v3.user,
                    auth_len: v3.auth.mac_len(),
                    priv_params,
                };
                let mut out = msg::encode_v3(pdu.request_id, flags, &usm, &data);
                let mac = v3.auth.sign(&e.auth_key, &out.bytes);
                let at = out.auth_at;
                out.bytes[at..at + mac.len()].copy_from_slice(&mac);
                Ok(out.bytes)
            }
        }
    }

    /// The PDU of `datagram` if it answers one of `ids`; `Ok(None)` drops
    /// it (another request's, or not authentic).
    fn accept(&mut self, datagram: &[u8], ids: &[i32]) -> Result<Option<Pdu>, Fail> {
        let Ok(m) = msg::decode(datagram) else {
            return Ok(None);
        };
        match (m, &self.sec) {
            (
                Message::Community {
                    version,
                    pdu,
                    community: _,
                },
                Security::V2c { .. },
            ) => {
                if version != msg::VERSION_2C
                    || pdu.ty != msg::RESPONSE
                    || !ids.contains(&pdu.request_id)
                {
                    return Ok(None);
                }
                Ok(Some(pdu))
            }
            (Message::V3(m), Security::V3(v3)) => {
                if !ids.contains(&m.msg_id) {
                    return Ok(None);
                }
                let Some(e) = &self.engine else {
                    return Ok(None);
                };
                let authentic = m.flags & msg::FLAG_AUTH != 0;
                if authentic {
                    if m.usm.engine_id != e.id.as_slice() {
                        return Ok(None);
                    }
                    let mut zeroed = datagram.to_vec();
                    let at = m.usm.auth_at;
                    let Some(slot) = zeroed.get_mut(at..at + m.usm.auth.len()) else {
                        return Ok(None);
                    };
                    slot.fill(0);
                    if !v3.auth.verify(&e.auth_key, &zeroed, m.usm.auth) {
                        return Ok(None);
                    }
                }
                let scoped = match m.data {
                    ScopedData::Plain(s) => s,
                    ScopedData::Encrypted(c) => {
                        let (Some(k), true) = (&e.priv_key, authentic) else {
                            return Ok(None);
                        };
                        let Ok(salt) = <[u8; 8]>::try_from(m.usm.priv_params) else {
                            return Ok(None);
                        };
                        let mut plain = c.to_vec();
                        usm::decrypt(k, m.usm.boots, m.usm.time, &salt, &mut plain);
                        match ScopedPdu::decode(&plain) {
                            Ok(s) => s,
                            Err(_) => return Ok(None),
                        }
                    }
                };
                let pdu = scoped.pdu;
                match pdu.ty {
                    msg::RESPONSE => {
                        // A response must be as secure as the request.
                        let private = m.flags & msg::FLAG_PRIV != 0;
                        if !authentic || private != e.priv_key.is_some() {
                            return Ok(None);
                        }
                        if !ids.contains(&pdu.request_id) {
                            return Ok(None);
                        }
                        let (boots, time) = (m.usm.boots, m.usm.time);
                        if let Some(e) = &mut self.engine {
                            e.boots = boots;
                            e.time = time;
                            e.at = Instant::now();
                        }
                        Ok(Some(pdu))
                    }
                    msg::REPORT => {
                        let kind = pdu
                            .varbinds
                            .first()
                            .map_or(ReportKind::Other, |(o, _)| ReportKind::of(o));
                        Err(self.report(kind, authentic, m.usm.boots, m.usm.time))
                    }
                    _ => Ok(None),
                }
            }
            _ => Ok(None),
        }
    }

    /// What a report means for the request.
    fn report(&mut self, kind: ReportKind, authentic: bool, boots: u32, time: u32) -> Fail {
        match kind {
            // Only an authentic report may move our notion of the clock.
            ReportKind::NotInTimeWindow if authentic => {
                if let Some(e) = &mut self.engine {
                    e.boots = boots;
                    e.time = time;
                    e.at = Instant::now();
                }
                Fail::Again
            }
            // A reopen discovers the engine again.
            ReportKind::UnknownEngineId => Fail::Error(DriverError::Transport(format!(
                "{}; discovering it again",
                kind.message()
            ))),
            _ => Fail::Error(DriverError::Device(kind.message().into())),
        }
    }

    /// RFC 3414 §4: a request without user or engine id is answered with a
    /// report that names the engine (and, on most agents, its boots and
    /// time; else the first authenticated request resynchronizes). Then the
    /// keys are localized for that engine.
    async fn discover(&mut self) -> Result<(), DriverError> {
        let mut attempt = 0u8;
        let mut ids = Vec::new();
        loop {
            let id = self.id();
            ids.push(id);
            let scoped = ScopedPdu {
                engine_id: Vec::new(),
                context: Vec::new(),
                pdu: Pdu::request(msg::GET, id, []),
            }
            .encode();
            let usm = UsmOut {
                engine_id: &[],
                boots: 0,
                time: 0,
                user: &[],
                auth_len: 0,
                priv_params: &[],
            };
            let wire = msg::encode_v3(id, msg::FLAG_REPORTABLE, &usm, &scoped).bytes;
            let sent = Instant::now();
            if let Err(e) = self.sock.send(&wire).await {
                self.outcomes.push(Outcome::Error);
                return Err(io_err(&e));
            }
            let deadline = sent + self.timeout;
            let found = loop {
                let n = match tokio::time::timeout_at(deadline, self.sock.recv(&mut self.buf)).await
                {
                    Err(_) => break None,
                    Ok(Err(e)) => {
                        self.outcomes.push(Outcome::Error);
                        return Err(io_err(&e));
                    }
                    Ok(Ok(n)) => n,
                };
                match msg::decode(&self.buf[..n]) {
                    Ok(Message::V3(m))
                        if ids.contains(&m.msg_id) && !m.usm.engine_id.is_empty() =>
                    {
                        break Some((m.usm.engine_id.to_vec(), m.usm.boots, m.usm.time));
                    }
                    _ => self.outcomes.push(Outcome::Count(LATE)),
                }
            };
            match found {
                Some((id, boots, time)) => {
                    self.outcomes.push(Outcome::Reply(sent.elapsed()));
                    return self.localize(id, boots, time);
                }
                None => {
                    self.outcomes.push(Outcome::Timeout);
                    if attempt >= self.retries {
                        return Err(DriverError::Device(
                            "no answer to engine discovery (is it an SNMPv3 agent?)".into(),
                        ));
                    }
                    attempt += 1;
                }
            }
        }
    }

    fn localize(&mut self, id: Vec<u8>, boots: u32, time: u32) -> Result<(), DriverError> {
        let Security::V3(v3) = &self.sec else {
            return Ok(());
        };
        let auth_key = v3.auth.localized_key(&v3.auth_pass, &id);
        let priv_key = match &v3.priv_pass {
            Some(p) => Some(
                usm::aes_key(&v3.auth.localized_key(p, &id))
                    .ok_or_else(|| DriverError::Transport("privacy key too short".into()))?,
            ),
            None => None,
        };
        debug!(engine_id_len = id.len(), boots, "engine discovered");
        self.engine = Some(Engine {
            id,
            boots,
            time,
            at: Instant::now(),
            auth_key,
            priv_key,
        });
        Ok(())
    }
}

fn transport(what: &str) -> DriverError {
    DriverError::Transport(what.to_owned())
}

/// `open` fails as a whole: whatever went wrong is the connection's.
fn as_transport(e: DriverError) -> DriverError {
    match e {
        DriverError::Transport(m) => DriverError::Transport(m),
        DriverError::Device(m) | DriverError::Point(m) => DriverError::Transport(m),
    }
}

/// A socket error. On a connected UDP socket an ICMP port unreachable
/// shows as `ConnectionRefused`: nothing listens on the agent's port.
fn io_err(e: &std::io::Error) -> DriverError {
    if e.kind() == std::io::ErrorKind::ConnectionRefused {
        DriverError::Transport("the agent's port is unreachable (ICMP port unreachable)".into())
    } else {
        DriverError::Transport(format!("socket: {e}"))
    }
}
