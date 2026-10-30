//! An SNMP agent for tests and demos (feature `sim`): v2c communities and
//! v3 USM users (SHA-1/SHA-256, AES-128) over UDP, a small MIB (system
//! group, an `ifTable`/`ifXTable` with 4 rows whose counters grow, a
//! writable `sysContact` and `ifAdminStatus`, and one object of each SMI
//! type under `1.3.6.1.4.1.64999.1`), and failure modes: silence, a reply
//! delayed past the client's timeout, `authorizationError`, `tooBig`,
//! `genErr` on one OID, a restart (new boots), unknown OIDs, and v3
//! responses forged one way each ([`Forge`]).

use std::collections::BTreeMap;
use std::net::SocketAddr;
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};
use tokio::net::UdpSocket;
use zeroize::Zeroizing;

use crate::ber::{Oid, SnmpValue};
use crate::msg::{self, Message, Pdu, ScopedData, ScopedPdu, UsmOut};
use crate::usm::{self, Auth, ReportKind};

/// The test-types subtree (an unassigned enterprise number).
pub const TYPES: [u32; 8] = [1, 3, 6, 1, 4, 1, 64999, 1];
pub const IF_TABLE: [u32; 9] = [1, 3, 6, 1, 2, 1, 2, 2, 1];
pub const IFX_TABLE: [u32; 10] = [1, 3, 6, 1, 2, 1, 31, 1, 1, 1];
pub const SYS_CONTACT: [u32; 9] = [1, 3, 6, 1, 2, 1, 1, 4, 0];

/// The engine id of every simulated agent (RFC 3411 format, text).
pub const ENGINE_ID: &[u8] = b"\x80\x00\xfd\xe7\x04wyrm-sim";

/// Another engine id (forged messages).
pub const OTHER_ENGINE_ID: &[u8] = b"\x80\x00\xfd\xe7\x04other-engine";

/// RFC 3414: a message more than 150 s off the agent's clock is refused.
const TIME_WINDOW: u32 = 150;

/// How a v3 response is forged (every other part of it is right, and it
/// carries the request's msgID): the link must never take it.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Forge {
    /// The MAC is wrong (one octet flipped).
    CorruptMac,
    /// `FLAG_AUTH` cleared: no MAC, not encrypted (a downgrade).
    NoAuth,
    /// Authenticated but not encrypted, to an authPriv request.
    NoPriv,
    /// Another `msgAuthoritativeEngineID`; the MAC is made with the key
    /// of the real engine, so it verifies: only the engine id check drops
    /// it.
    WrongEngine,
    /// `msgAuthoritativeEngineBoots` one lower (a replayed old message;
    /// MAC and encryption right for it).
    StaleBoots,
    /// `msgAuthoritativeEngineTime` 1000 s earlier, same boots (a replayed
    /// old message; MAC and encryption right for it).
    StaleTime,
    /// An unauthenticated `usmStatsUnknownEngineIDs` report that names the
    /// agent's own engine id, instead of the response.
    UnknownEngine,
    /// An unauthenticated `usmStatsUnknownEngineIDs` report that names
    /// another engine id, instead of the response.
    OtherEngineReport,
}

/// A v3 user and its localized keys.
pub struct User {
    pub name: String,
    pub auth: Auth,
    auth_key: Zeroizing<Vec<u8>>,
    priv_key: Option<Zeroizing<[u8; 16]>>,
}

/// One object.
#[derive(Debug, Clone)]
pub struct Object {
    pub value: SnmpValue,
    pub writable: bool,
}

pub struct Agent {
    pub mib: BTreeMap<Oid, Object>,
    /// Accepted v2c communities (read and write).
    pub communities: Vec<String>,
    pub users: Vec<User>,
    pub boots: u32,
    started: Instant,
    /// Answer nothing.
    pub silent: bool,
    /// Answer the next request after this long, every value replaced by
    /// the marker (a late reply), v2c and v3.
    pub late_next: Option<(Duration, SnmpValue)>,
    /// Forge every v3 response this way, every value replaced by the
    /// marker.
    pub forge: Option<(Forge, SnmpValue)>,
    /// Seconds added to `snmpEngineTime` (an agent that has run a while).
    pub clock_offset: u32,
    /// Replace every value of the answers by this (set per request).
    mark_with: Option<SnmpValue>,
    /// Before each v3 answer, send a replayed old response to the same
    /// msgID (1000 s old, MAC and encryption right), values this marker.
    pub replay_first: Option<SnmpValue>,
    /// Datagrams to send before the reply (replays).
    pre: Vec<Vec<u8>>,
    /// Authenticated `notInTimeWindow` reports sent.
    pub time_reports: u64,
    /// Answer every request with `authorizationError`.
    pub auth_error: bool,
    /// Answer a GET of more varbinds with `tooBig`; truncate a GETBULK.
    pub max_varbinds: Option<usize>,
    /// Answer a GET that asks for this OID with `genErr` at its index.
    pub gen_err: Option<Oid>,
    /// Answer nothing to a request that asks for this OID (a vendor MIB
    /// handler that hangs).
    pub hang: Option<Oid>,
    /// v3 contexts the agent knows (`None` = any); another context gets a
    /// `snmpUnknownContexts` report.
    pub contexts: Option<Vec<String>>,
    /// Requests received (all, dropped ones too).
    pub requests: u64,
    /// GET requests and their sizes (varbinds), GETBULK as negative counts.
    pub gets: Vec<i64>,
    /// Requests dropped for a community that is not accepted.
    pub bad_community: u64,
    /// SETs applied.
    pub sets: Vec<(Oid, SnmpValue)>,
    salt: u64,
}

pub type Shared = Arc<Mutex<Agent>>;

fn obj(mib: &mut BTreeMap<Oid, Object>, oid: &[u32], value: SnmpValue, writable: bool) {
    mib.insert(Oid(oid.to_vec()), Object { value, writable });
}

impl Default for Agent {
    fn default() -> Self {
        Self::new()
    }
}

impl Agent {
    /// The MIB, community `public`, users `sha1user` (SHA-1, AES), `sha256user`
    /// (SHA-256, AES) and `authonly` (SHA-256, no privacy); every passphrase
    /// is `<user>-pass`.
    pub fn new() -> Agent {
        let mut mib = BTreeMap::new();
        let sys = |n: u32| vec![1, 3, 6, 1, 2, 1, 1, n, 0];
        let text = |s: &str| SnmpValue::OctetString(s.as_bytes().to_vec());
        obj(&mut mib, &sys(1), text("WYRM SNMP simulator"), false);
        obj(
            &mut mib,
            &sys(2),
            SnmpValue::Oid(Oid(vec![1, 3, 6, 1, 4, 1, 64999])),
            false,
        );
        // sys(3) sysUpTime is computed.
        obj(&mut mib, &sys(4), text("ops@example.net"), true);
        obj(&mut mib, &sys(5), text("sim"), false);
        obj(&mut mib, &sys(6), text("lab"), false);
        obj(
            &mut mib,
            &[1, 3, 6, 1, 2, 1, 2, 1, 0],
            SnmpValue::Integer(4),
            false,
        );
        for row in 1..=4u32 {
            let col = |c: u32| {
                let mut o = IF_TABLE.to_vec();
                o.extend([c, row]);
                o
            };
            let xcol = |c: u32| {
                let mut o = IFX_TABLE.to_vec();
                o.extend([c, row]);
                o
            };
            let i = i32::try_from(row).unwrap_or(0);
            let b = u8::try_from(row).unwrap_or(0);
            obj(&mut mib, &col(1), SnmpValue::Integer(i), false);
            obj(&mut mib, &col(2), text(&format!("eth{}", row - 1)), false);
            obj(&mut mib, &col(3), SnmpValue::Integer(6), false);
            obj(&mut mib, &col(4), SnmpValue::Integer(1500), false);
            obj(&mut mib, &col(5), SnmpValue::Gauge32(1_000_000_000), false);
            obj(
                &mut mib,
                &col(6),
                SnmpValue::OctetString(vec![0x02, 0, 0, 0, 0, b]),
                false,
            );
            obj(&mut mib, &col(7), SnmpValue::Integer(1), true);
            obj(
                &mut mib,
                &col(8),
                SnmpValue::Integer(if row == 4 { 2 } else { 1 }),
                false,
            );
            // Row 1 is just below the Counter32 wrap.
            let start = if row == 1 { u32::MAX - 999 } else { 1000 * row };
            obj(&mut mib, &col(10), SnmpValue::Counter32(start), false);
            obj(&mut mib, &col(16), SnmpValue::Counter32(500 * row), false);
            obj(&mut mib, &xcol(1), text(&format!("eth{}", row - 1)), false);
            obj(
                &mut mib,
                &xcol(6),
                SnmpValue::Counter64(10_000_000_000 * u64::from(row)),
                false,
            );
            obj(
                &mut mib,
                &xcol(10),
                SnmpValue::Counter64(5_000_000_000 * u64::from(row)),
                false,
            );
            obj(&mut mib, &xcol(15), SnmpValue::Gauge32(1000), false);
        }
        let t = |n: u32| {
            let mut o = TYPES.to_vec();
            o.extend([n, 0]);
            o
        };
        obj(&mut mib, &t(1), SnmpValue::Integer(-40), true);
        obj(&mut mib, &t(2), SnmpValue::Gauge32(650), true);
        obj(&mut mib, &t(3), SnmpValue::IpAddress([192, 0, 2, 1]), false);
        obj(&mut mib, &t(4), SnmpValue::TimeTicks(12_345), false);
        obj(&mut mib, &t(5), SnmpValue::Opaque(vec![1, 2]), false);
        obj(&mut mib, &t(6), SnmpValue::Counter64(u64::MAX - 1), false);
        obj(
            &mut mib,
            &t(7),
            SnmpValue::OctetString(vec![0xde, 0xad, 0xbe, 0xef]),
            false,
        );
        obj(&mut mib, &t(8), text("set me"), true);
        // An INTEGER of no octets (a broken agent's encoding).
        obj(
            &mut mib,
            &t(9),
            SnmpValue::Malformed(crate::ber::INTEGER),
            false,
        );
        let mut a = Agent {
            mib,
            communities: vec!["public".into()],
            users: Vec::new(),
            boots: 1,
            started: Instant::now(),
            silent: false,
            late_next: None,
            forge: None,
            clock_offset: 0,
            mark_with: None,
            replay_first: None,
            pre: Vec::new(),
            time_reports: 0,
            auth_error: false,
            max_varbinds: None,
            gen_err: None,
            hang: None,
            contexts: None,
            requests: 0,
            gets: Vec::new(),
            bad_community: 0,
            sets: Vec::new(),
            salt: 0x5EED,
        };
        a.add_user(
            "sha1user",
            Auth::Sha1,
            "sha1user-pass",
            Some("sha1user-pass"),
        );
        a.add_user(
            "sha256user",
            Auth::Sha256,
            "sha256user-pass",
            Some("sha256user-pass"),
        );
        a.add_user("authonly", Auth::Sha256, "authonly-pass", None);
        a
    }

    /// Add a v3 user (keys localized for [`ENGINE_ID`]).
    pub fn add_user(&mut self, name: &str, auth: Auth, auth_pass: &str, priv_pass: Option<&str>) {
        self.users.retain(|u| u.name != name);
        self.users.push(User {
            name: name.into(),
            auth,
            auth_key: auth.localized_key(auth_pass.as_bytes(), ENGINE_ID),
            priv_key: priv_pass
                .and_then(|p| usm::aes_key(&auth.localized_key(p.as_bytes(), ENGINE_ID))),
        });
    }

    /// `snmpEngineTime`, seconds since start.
    pub fn engine_time(&self) -> u32 {
        u32::try_from(self.started.elapsed().as_secs())
            .unwrap_or(u32::MAX)
            .saturating_add(self.clock_offset)
    }

    /// A restart: boots goes up, time and `sysUpTime` start again.
    pub fn restart(&mut self) {
        self.boots += 1;
        self.started = Instant::now();
    }

    pub fn get(&self, oid: &[u32]) -> Option<SnmpValue> {
        self.lookup(&Oid(oid.to_vec()))
    }

    pub fn set(&mut self, oid: &[u32], value: SnmpValue) {
        let writable = self.mib.get(&Oid(oid.to_vec())).is_some_and(|o| o.writable);
        obj(&mut self.mib, oid, value, writable);
    }

    /// Let `secs` seconds of traffic pass: the octet counters grow
    /// (Counter32 wraps).
    pub fn tick(&mut self, secs: u32) {
        for row in 1..=4u32 {
            for (table, c, per_s) in [
                (&IF_TABLE[..], 10, 1000 * row),
                (&IF_TABLE[..], 16, 400 * row),
                (&IFX_TABLE[..], 6, 1000 * row),
                (&IFX_TABLE[..], 10, 400 * row),
            ] {
                let mut o = table.to_vec();
                o.extend([c, row]);
                if let Some(obj) = self.mib.get_mut(&Oid(o)) {
                    let add = per_s.wrapping_mul(secs);
                    obj.value = match obj.value {
                        SnmpValue::Counter32(x) => SnmpValue::Counter32(x.wrapping_add(add)),
                        SnmpValue::Counter64(x) => {
                            SnmpValue::Counter64(x.wrapping_add(u64::from(add)))
                        }
                        ref v => v.clone(),
                    };
                }
            }
        }
    }

    fn uptime(&self) -> SnmpValue {
        let ticks = self.started.elapsed().as_millis() / 10;
        SnmpValue::TimeTicks(u32::try_from(ticks & 0xFFFF_FFFF).unwrap_or(0))
    }

    fn lookup(&self, oid: &Oid) -> Option<SnmpValue> {
        if oid.0 == crate::client::SYS_UPTIME {
            return Some(self.uptime());
        }
        self.mib.get(oid).map(|o| o.value.clone())
    }

    /// The first object after `oid`.
    fn next(&self, oid: &Oid) -> (Oid, SnmpValue) {
        let up = Oid(crate::client::SYS_UPTIME.to_vec());
        let from_mib = self
            .mib
            .range((
                std::ops::Bound::Excluded(oid.clone()),
                std::ops::Bound::Unbounded,
            ))
            .next()
            .map(|(k, o)| (k.clone(), o.value.clone()));
        match from_mib {
            Some((k, _)) if *oid < up && up < k => (up, self.uptime()),
            Some(kv) => kv,
            None if *oid < up => (up, self.uptime()),
            None => (oid.clone(), SnmpValue::EndOfMibView),
        }
    }

    /// `noSuchInstance` when the object (`oid` without its last arc) exists.
    fn missing(&self, oid: &Oid) -> SnmpValue {
        let mut parent = oid.0.clone();
        parent.pop();
        let parent = Oid(parent);
        let has_object = self
            .mib
            .range(parent.clone()..)
            .next()
            .is_some_and(|(k, _)| k.starts_with(&parent) && k != &parent);
        if has_object {
            SnmpValue::NoSuchInstance
        } else {
            SnmpValue::NoSuchObject
        }
    }

    /// The response to `req`, its values replaced by the marker of a late
    /// or forged reply.
    fn answer(&mut self, req: &Pdu) -> Pdu {
        let mut resp = self.answer_plain(req);
        if let Some(m) = &self.mark_with {
            for vb in &mut resp.varbinds {
                vb.1 = m.clone();
            }
        }
        resp
    }

    fn answer_plain(&mut self, req: &Pdu) -> Pdu {
        let mut resp = Pdu {
            ty: msg::RESPONSE,
            request_id: req.request_id,
            error_status: 0,
            error_index: 0,
            varbinds: Vec::new(),
        };
        if self.auth_error {
            resp.error_status = msg::AUTHORIZATION_ERROR;
            resp.varbinds = req.varbinds.clone();
            return resp;
        }
        match req.ty {
            msg::GET => {
                self.gets
                    .push(i64::try_from(req.varbinds.len()).unwrap_or(i64::MAX));
                if let Some(limit) = self.max_varbinds {
                    if req.varbinds.len() > limit {
                        resp.error_status = msg::TOO_BIG;
                        resp.varbinds = req.varbinds.clone();
                        return resp;
                    }
                }
                if let Some(bad) = &self.gen_err {
                    if let Some(i) = req.varbinds.iter().position(|(o, _)| o == bad) {
                        resp.error_status = msg::GEN_ERR;
                        resp.error_index = i32::try_from(i + 1).unwrap_or(0);
                        resp.varbinds = req.varbinds.clone();
                        return resp;
                    }
                }
                for (oid, _) in &req.varbinds {
                    let v = self.lookup(oid).unwrap_or_else(|| self.missing(oid));
                    resp.varbinds.push((oid.clone(), v));
                }
            }
            msg::GET_NEXT => {
                for (oid, _) in &req.varbinds {
                    resp.varbinds.push(self.next(oid));
                }
            }
            msg::GET_BULK => {
                self.gets
                    .push(-i64::try_from(req.varbinds.len()).unwrap_or(i64::MAX));
                let n = usize::try_from(req.error_status.max(0))
                    .unwrap_or(0)
                    .min(req.varbinds.len());
                let reps = usize::try_from(req.error_index.max(0)).unwrap_or(0);
                for (oid, _) in &req.varbinds[..n] {
                    resp.varbinds.push(self.next(oid));
                }
                let mut cursors: Vec<Oid> =
                    req.varbinds[n..].iter().map(|(o, _)| o.clone()).collect();
                let limit = self.max_varbinds.unwrap_or(usize::MAX).min(1000);
                'reps: for _ in 0..reps {
                    if cursors.is_empty() {
                        break;
                    }
                    let mut all_end = true;
                    for c in cursors.iter_mut() {
                        if resp.varbinds.len() >= limit {
                            break 'reps;
                        }
                        let (k, v) = self.next(c);
                        all_end &= v == SnmpValue::EndOfMibView;
                        *c = k.clone();
                        resp.varbinds.push((k, v));
                    }
                    if all_end {
                        break;
                    }
                }
            }
            msg::SET => {
                // Check all, then apply all.
                for (i, (oid, v)) in req.varbinds.iter().enumerate() {
                    let index = i32::try_from(i + 1).unwrap_or(0);
                    let status = match self.mib.get(oid) {
                        None => Some(msg::NOT_WRITABLE),
                        Some(o) if !o.writable => Some(msg::NOT_WRITABLE),
                        Some(o)
                            if std::mem::discriminant(&o.value) != std::mem::discriminant(v) =>
                        {
                            Some(msg::WRONG_TYPE)
                        }
                        Some(_) => None,
                    };
                    if let Some(s) = status {
                        resp.error_status = s;
                        resp.error_index = index;
                        resp.varbinds = req.varbinds.clone();
                        return resp;
                    }
                }
                for (oid, v) in &req.varbinds {
                    if let Some(o) = self.mib.get_mut(oid) {
                        o.value = v.clone();
                    }
                    self.sets.push((oid.clone(), v.clone()));
                }
                resp.varbinds = req.varbinds.clone();
            }
            _ => {
                resp.error_status = msg::GEN_ERR;
            }
        }
        resp
    }

    /// Whether `req` asks for the OID that hangs.
    fn hangs(&self, req: &Pdu) -> bool {
        self.hang
            .as_ref()
            .is_some_and(|h| req.varbinds.iter().any(|(o, _)| o == h))
    }

    /// The reply datagram to `datagram`, if any.
    fn handle(&mut self, datagram: &[u8]) -> Option<Vec<u8>> {
        self.requests += 1;
        if self.silent {
            return None;
        }
        match msg::decode(datagram).ok()? {
            Message::Community {
                version,
                community,
                pdu,
            } => {
                if version != msg::VERSION_2C {
                    return None;
                }
                if !self.communities.iter().any(|c| c.as_bytes() == community) {
                    self.bad_community += 1;
                    return None;
                }
                let community = community.to_vec();
                if self.hangs(&pdu) {
                    return None;
                }
                let resp = self.answer(&pdu);
                Some(msg::encode_community(&community, &resp))
            }
            Message::V3(m) => self.handle_v3(datagram, m),
        }
    }

    fn report(&mut self, msg_id: i32, kind: ReportKind, user: Option<&User>) -> Vec<u8> {
        self.report_as(msg_id, kind, user, ENGINE_ID)
    }

    /// A report with `engine_id` as the authoritative engine.
    fn report_as(
        &mut self,
        msg_id: i32,
        kind: ReportKind,
        user: Option<&User>,
        engine_id: &[u8],
    ) -> Vec<u8> {
        if kind == ReportKind::NotInTimeWindow && user.is_some() {
            self.time_reports += 1;
        }
        let pdu = Pdu {
            ty: msg::REPORT,
            request_id: msg_id,
            error_status: 0,
            error_index: 0,
            varbinds: vec![(kind.oid(), SnmpValue::Counter32(1))],
        };
        let scoped = ScopedPdu {
            engine_id: ENGINE_ID.to_vec(),
            context: Vec::new(),
            pdu,
        }
        .encode();
        let (boots, time) = (self.boots, self.engine_time());
        // RFC 3414 3.2 7b: notInTimeWindow goes out authenticated.
        let auth = user.filter(|_| kind == ReportKind::NotInTimeWindow);
        let usm = UsmOut {
            engine_id,
            boots,
            time,
            user: user.map_or(&[][..], |u| u.name.as_bytes()),
            auth_len: auth.map_or(0, |u| u.auth.mac_len()),
            priv_params: &[],
        };
        let flags = if auth.is_some() { msg::FLAG_AUTH } else { 0 };
        let mut out = msg::encode_v3(msg_id, flags, &usm, &scoped);
        if let Some(u) = auth {
            let mac = u.auth.sign(&u.auth_key, &out.bytes);
            out.bytes[out.auth_at..out.auth_at + mac.len()].copy_from_slice(&mac);
        }
        out.bytes
    }

    fn handle_v3(&mut self, datagram: &[u8], m: msg::V3In<'_>) -> Option<Vec<u8>> {
        let id = m.msg_id;
        if !m.usm.engine_id.is_empty() {
            match self.forge {
                Some((Forge::UnknownEngine, _)) => {
                    return Some(self.report(id, ReportKind::UnknownEngineId, None));
                }
                Some((Forge::OtherEngineReport, _)) => {
                    let r = self.report_as(id, ReportKind::UnknownEngineId, None, OTHER_ENGINE_ID);
                    return Some(r);
                }
                _ => {}
            }
        }
        if m.usm.engine_id.is_empty() || m.usm.engine_id != ENGINE_ID {
            return Some(self.report(id, ReportKind::UnknownEngineId, None));
        }
        let Some(ui) = self
            .users
            .iter()
            .position(|u| u.name.as_bytes() == m.usm.user)
        else {
            return Some(self.report(id, ReportKind::UnknownUserName, None));
        };
        let user = &self.users[ui];
        let wants_priv = m.flags & msg::FLAG_PRIV != 0;
        if m.flags & msg::FLAG_AUTH == 0 || wants_priv != user.priv_key.is_some() {
            return Some(self.report(id, ReportKind::UnsupportedSecLevel, None));
        }
        let mut zeroed = datagram.to_vec();
        zeroed
            .get_mut(m.usm.auth_at..m.usm.auth_at + m.usm.auth.len())?
            .fill(0);
        if !user.auth.verify(&user.auth_key, &zeroed, m.usm.auth) {
            return Some(self.report(id, ReportKind::WrongDigest, None));
        }
        let scoped = match m.data {
            ScopedData::Plain(s) => s,
            ScopedData::Encrypted(c) => {
                let key = user.priv_key.clone()?;
                let salt: [u8; 8] = match m.usm.priv_params.try_into() {
                    Ok(s) => s,
                    Err(_) => return Some(self.report(id, ReportKind::DecryptionError, None)),
                };
                let mut plain = c.to_vec();
                usm::decrypt(&key, m.usm.boots, m.usm.time, &salt, &mut plain);
                match ScopedPdu::decode(&plain) {
                    Ok(s) => s,
                    Err(_) => return Some(self.report(id, ReportKind::DecryptionError, None)),
                }
            }
        };
        // An on-path replay of an old recorded response, sent before the
        // agent's own answer (the msgID is in clear text).
        if let Some(marker) = self.replay_first.clone() {
            let old = self.respond(ui, id, &scoped, Some((Forge::StaleTime, marker)));
            self.pre.push(old);
        }
        let now = self.engine_time();
        if m.usm.boots != self.boots || m.usm.time.abs_diff(now) > TIME_WINDOW {
            let user = &self.users[ui];
            let user = User {
                name: user.name.clone(),
                auth: user.auth,
                auth_key: user.auth_key.clone(),
                priv_key: None,
            };
            return Some(self.report(id, ReportKind::NotInTimeWindow, Some(&user)));
        }
        if self.hangs(&scoped.pdu) {
            return None;
        }
        if let Some(known) = &self.contexts {
            if !known.iter().any(|c| c.as_bytes() == scoped.context) {
                return Some(self.report(id, ReportKind::UnknownContext, None));
            }
        }
        let forge = self.forge.clone();
        Some(self.respond(ui, id, &scoped, forge))
    }

    /// The response of user `ui` to the request `scoped` with msgID `id`,
    /// forged as `forge` (its values replaced by the marker).
    fn respond(
        &mut self,
        ui: usize,
        id: i32,
        scoped: &ScopedPdu,
        forge: Option<(Forge, SnmpValue)>,
    ) -> Vec<u8> {
        let marked = self.mark_with.clone();
        if let Some((_, marker)) = &forge {
            self.mark_with = Some(marker.clone());
        }
        let resp = ScopedPdu {
            engine_id: ENGINE_ID.to_vec(),
            context: scoped.context.clone(),
            pdu: self.answer(&scoped.pdu),
        }
        .encode();
        self.mark_with = marked;
        let forge = forge.map(|(f, _)| f);
        let user = &self.users[ui];
        let (auth, auth_key) = (user.auth, user.auth_key.clone());
        let priv_key = match forge {
            Some(Forge::NoAuth | Forge::NoPriv) => None,
            _ => user.priv_key.clone(),
        };
        let name = user.name.clone();
        let (mut boots, mut time) = (self.boots, self.engine_time());
        match forge {
            Some(Forge::StaleBoots) => boots = boots.saturating_sub(1),
            Some(Forge::StaleTime) => time = time.saturating_sub(1000),
            _ => {}
        }
        let engine_id: &[u8] = if forge == Some(Forge::WrongEngine) {
            OTHER_ENGINE_ID
        } else {
            ENGINE_ID
        };
        let authenticate = forge != Some(Forge::NoAuth);
        self.salt = self.salt.wrapping_add(1);
        let salt = self.salt.to_be_bytes();
        let (data, priv_params, mut flags): (Vec<u8>, &[u8], u8) = match &priv_key {
            Some(k) => {
                let mut enc = resp;
                usm::encrypt(k, boots, time, &salt, &mut enc);
                let mut d = Vec::new();
                crate::ber::tlv(&mut d, crate::ber::OCTET_STRING, &enc);
                (d, &salt, msg::FLAG_AUTH | msg::FLAG_PRIV)
            }
            None => (resp, &[], msg::FLAG_AUTH),
        };
        if !authenticate {
            flags = 0;
        }
        let usm_out = UsmOut {
            engine_id,
            boots,
            time,
            user: name.as_bytes(),
            auth_len: if authenticate { auth.mac_len() } else { 0 },
            priv_params,
        };
        let mut out = msg::encode_v3(id, flags, &usm_out, &data);
        if authenticate {
            let mut mac = auth.sign(&auth_key, &out.bytes);
            if forge == Some(Forge::CorruptMac) {
                mac[0] ^= 0x01;
            }
            out.bytes[out.auth_at..out.auth_at + mac.len()].copy_from_slice(&mac);
        }
        out.bytes
    }
}

/// Run `agent` on `addr` (`127.0.0.1:0` for a free port).
pub async fn spawn_with(
    addr: &str,
    agent: Shared,
) -> std::io::Result<(SocketAddr, tokio::task::JoinHandle<()>)> {
    let sock = Arc::new(UdpSocket::bind(addr).await?);
    let local = sock.local_addr()?;
    let task = tokio::spawn(async move {
        let mut buf = vec![0u8; 65_535];
        loop {
            let Ok((n, peer)) = sock.recv_from(&mut buf).await else {
                // An ICMP error from an earlier reply: keep serving.
                continue;
            };
            let (pre, reply, late) = {
                let mut a = agent.lock().unwrap_or_else(|p| p.into_inner());
                // A late reply's values are the marker (it must never be
                // published).
                let late = a.late_next.take();
                a.mark_with = late.as_ref().map(|(_, m)| m.clone());
                let reply = a.handle(&buf[..n]);
                a.mark_with = None;
                (std::mem::take(&mut a.pre), reply, late.map(|(d, _)| d))
            };
            for d in pre {
                let _ = sock.send_to(&d, peer).await;
            }
            let Some(reply) = reply else {
                continue;
            };
            match late {
                Some(delay) => {
                    let sock = sock.clone();
                    tokio::spawn(async move {
                        tokio::time::sleep(delay).await;
                        let _ = sock.send_to(&reply, peer).await;
                    });
                }
                None => {
                    let _ = sock.send_to(&reply, peer).await;
                }
            }
        }
    });
    Ok((local, task))
}

/// A new [`Agent`] on `addr`.
pub async fn spawn(
    addr: &str,
) -> std::io::Result<(SocketAddr, Shared, tokio::task::JoinHandle<()>)> {
    let agent = Shared::new(Mutex::new(Agent::new()));
    let (local, task) = spawn_with(addr, agent.clone()).await?;
    Ok((local, agent, task))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn get_next_walks_in_order_and_ends() {
        let a = Agent::new();
        let (k, _) = a.next(&Oid(vec![1, 3, 6, 1, 2, 1, 1]));
        assert_eq!(k.to_string(), "1.3.6.1.2.1.1.1.0");
        let (k, v) = a.next(&Oid(vec![1, 3, 6, 1, 2, 1, 1, 2, 0]));
        assert_eq!(k.0, crate::client::SYS_UPTIME);
        assert!(matches!(v, SnmpValue::TimeTicks(_)));
        let (_, v) = a.next(&Oid(vec![2]));
        assert_eq!(v, SnmpValue::EndOfMibView);
        assert_eq!(
            a.missing(&Oid(vec![1, 3, 6, 1, 2, 1, 1, 4, 1])),
            SnmpValue::NoSuchInstance
        );
        assert_eq!(
            a.missing(&Oid(vec![1, 3, 6, 1, 2, 1, 99, 0])),
            SnmpValue::NoSuchObject
        );
    }

    #[test]
    fn counters_grow_and_wrap() {
        let mut a = Agent::new();
        let in1 = [1, 3, 6, 1, 2, 1, 2, 2, 1, 10, 1];
        a.tick(1);
        assert_eq!(a.get(&in1), Some(SnmpValue::Counter32(0)));
        a.tick(1);
        assert_eq!(a.get(&in1), Some(SnmpValue::Counter32(1000)));
    }
}
