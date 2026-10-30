//! One S7 connection: TCP, COTP connect, Setup Communication, and request
//! by request exchange with PDU reference matching.
//!
//! The framework may drop any operation at its bound, so the transport is
//! cancel-safe: bytes are read into a buffer that outlives the operation
//! (`read_buf`), whole TPKT frames are taken from it, and a reply whose
//! PDU reference is not the current request's (a late reply to a request
//! that timed out or was cut) is dropped and counted. A request cut while
//! it was being sent leaves the stream in an unknown state: the next
//! request reports a broken transport and the framework reconnects.

use crate::proto::{self, Cotp, Item, ItemResult, S7Reply, Setup};
use std::time::Duration;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::TcpStream;
use tokio::time::Instant;
use tracing::debug;
use wyrm_link_sdk::driver::{DriverError, Outcome};

/// The diagnostics counter of dropped late replies.
pub const LATE_REPLIES: &str = "late_replies";

/// The smallest PDU this link works with.
pub const MIN_PDU: u16 = 96;

/// Bound on one assembled S7 PDU (COTP fragments together).
const MAX_PDU_BYTES: usize = 64 * 1024;

/// How to reach a CPU.
#[derive(Debug, Clone, PartialEq)]
pub struct Target {
    pub host: String,
    pub port: u16,
    pub local_tsap: u16,
    pub remote_tsap: u16,
    pub pdu: u16,
    pub timeout: Duration,
}

/// An open, set-up connection.
pub struct Client {
    stream: TcpStream,
    /// Bytes received and not yet taken as frames.
    rx: Vec<u8>,
    /// COTP DT fragments of the S7 PDU being received.
    frag: Vec<u8>,
    next_ref: u16,
    /// A request was cut while it was being sent.
    dirty: bool,
    pub timeout: Duration,
    /// What Setup Communication agreed (`pdu` capped at the requested).
    pub setup: Setup,
    pub local_tsap: u16,
    pub remote_tsap: u16,
    /// Late replies dropped so far.
    pub late: u64,
    outcomes: Vec<Outcome>,
}

fn io(what: &str, e: std::io::Error) -> DriverError {
    DriverError::Transport(format!("{what}: {e}"))
}

fn protocol(e: proto::ProtoError) -> DriverError {
    DriverError::Transport(format!("protocol error: {e}"))
}

impl Client {
    /// Connect, send the COTP connection request with the TSAPs, and agree
    /// on the PDU size. Every step is bounded by `timeout`; every error is
    /// a transport error.
    pub async fn connect(t: &Target) -> Result<Client, DriverError> {
        let target = format!("{}:{}", t.host, t.port);
        let stream = tokio::time::timeout(t.timeout, TcpStream::connect(&target))
            .await
            .map_err(|_| DriverError::Transport(format!("connect {target}: timeout")))?
            .map_err(|e| io(&format!("connect {target}"), e))?;
        let _ = stream.set_nodelay(true);
        let mut c = Client {
            stream,
            rx: Vec::with_capacity(4096),
            frag: Vec::new(),
            next_ref: 0,
            dirty: false,
            timeout: t.timeout,
            setup: Setup {
                amq_calling: 1,
                amq_called: 1,
                pdu: MIN_PDU,
            },
            local_tsap: t.local_tsap,
            remote_tsap: t.remote_tsap,
            late: 0,
            outcomes: Vec::new(),
        };
        c.send(&proto::cotp_cr(t.local_tsap, t.remote_tsap)).await?;
        let frame = tokio::time::timeout(t.timeout, c.read_frame())
            .await
            .map_err(|_| DriverError::Transport("COTP connect: no confirm in time".into()))??;
        match proto::cotp(&frame).map_err(protocol)? {
            Cotp::Cc => {}
            Cotp::Dr { reason } => {
                return Err(DriverError::Transport(format!(
                    "the PLC refused the connection (COTP disconnect, reason 0x{reason:02X}): \
                     check rack, slot and connection type (remote TSAP 0x{:04X})",
                    t.remote_tsap
                )))
            }
            other => {
                return Err(DriverError::Transport(format!(
                    "COTP connect: unexpected reply {other:?}"
                )))
            }
        }
        let pdu = t.pdu;
        let (reply, _) = c
            .exchange(|r| proto::setup(r, pdu))
            .await
            .map_err(|e| match e {
                DriverError::Transport(m) => DriverError::Transport(m),
                other => DriverError::Transport(format!("setup communication: {other}")),
            })?;
        let r = proto::s7_reply(&reply).map_err(protocol)?;
        if r.error != 0 {
            return Err(DriverError::Transport(format!(
                "setup communication: {}",
                proto::error_text(r.error)
            )));
        }
        let mut setup = proto::setup_reply(&r).map_err(protocol)?;
        setup.pdu = setup.pdu.min(t.pdu);
        if setup.pdu < MIN_PDU {
            return Err(DriverError::Transport(format!(
                "the PLC offers a PDU of {} bytes; this link needs at least {MIN_PDU}",
                setup.pdu
            )));
        }
        c.setup = setup;
        c.outcomes.clear();
        debug!(
            pdu = setup.pdu,
            amq_calling = setup.amq_calling,
            amq_called = setup.amq_called,
            "s7 connection set up"
        );
        Ok(c)
    }

    pub fn pdu(&self) -> u16 {
        self.setup.pdu
    }

    pub fn take_outcomes(&mut self) -> Vec<Outcome> {
        std::mem::take(&mut self.outcomes)
    }

    /// Count a reply: an exception when the PLC refused (part of) it.
    pub fn answered(&mut self, rtt: Duration, failed: bool) {
        self.outcomes.push(if failed {
            Outcome::Exception(rtt)
        } else {
            Outcome::Reply(rtt)
        });
    }

    fn pdu_ref(&mut self) -> u16 {
        self.next_ref = self.next_ref.wrapping_add(1).max(1);
        self.next_ref
    }

    async fn send(&mut self, frame: &[u8]) -> Result<(), DriverError> {
        if self.dirty {
            return Err(DriverError::Transport(
                "an earlier request was cut while being sent; reconnecting".into(),
            ));
        }
        self.dirty = true;
        tokio::time::timeout(self.timeout, self.stream.write_all(frame))
            .await
            .map_err(|_| DriverError::Transport("send: timeout".into()))?
            .map_err(|e| io("send", e))?;
        self.dirty = false;
        Ok(())
    }

    /// The next whole TPKT frame (cancel-safe).
    async fn read_frame(&mut self) -> Result<Vec<u8>, DriverError> {
        loop {
            if let Some(len) = proto::tpkt_len(&self.rx).map_err(protocol)? {
                return Ok(self.rx.drain(..len).collect());
            }
            if self.rx.capacity() - self.rx.len() < 1024 {
                self.rx.reserve(4096);
            }
            let n = self
                .stream
                .read_buf(&mut self.rx)
                .await
                .map_err(|e| io("receive", e))?;
            if n == 0 {
                return Err(DriverError::Transport(
                    "the PLC closed the connection".into(),
                ));
            }
        }
    }

    /// The next whole S7 PDU (COTP DT fragments together; cancel-safe).
    async fn read_pdu(&mut self) -> Result<Vec<u8>, DriverError> {
        loop {
            let frame = self.read_frame().await?;
            match proto::cotp(&frame).map_err(protocol)? {
                Cotp::Dt { last, data } => {
                    if self.frag.len() + data.len() > MAX_PDU_BYTES {
                        return Err(DriverError::Transport("S7 PDU too long".into()));
                    }
                    self.frag.extend_from_slice(data);
                    if last {
                        return Ok(std::mem::take(&mut self.frag));
                    }
                }
                Cotp::Dr { reason } => {
                    return Err(DriverError::Transport(format!(
                        "the PLC closed the connection (COTP disconnect, reason 0x{reason:02X})"
                    )))
                }
                other => {
                    return Err(DriverError::Transport(format!(
                        "unexpected COTP TPDU {other:?}"
                    )))
                }
            }
        }
    }

    /// Send the PDU `build(pdu_ref)` makes and wait for the reply with that
    /// reference, dropping late replies to earlier requests. No reply in
    /// time is a device error (counted as a timeout); a broken or garbled
    /// stream a transport error. The caller counts the answer
    /// ([`Client::answered`]).
    pub async fn exchange(
        &mut self,
        build: impl FnOnce(u16) -> Vec<u8>,
    ) -> Result<(Vec<u8>, Duration), DriverError> {
        let r = self.pdu_ref();
        let frame = proto::dt(&build(r));
        if let Err(e) = self.send(&frame).await {
            self.outcomes.push(Outcome::Error);
            return Err(e);
        }
        let sent = Instant::now();
        let deadline = sent + self.timeout;
        loop {
            let pdu = match tokio::time::timeout_at(deadline, self.read_pdu()).await {
                Err(_) => {
                    self.outcomes.push(Outcome::Timeout);
                    return Err(DriverError::Device(format!(
                        "no reply within {} ms",
                        self.timeout.as_millis()
                    )));
                }
                Ok(Err(e)) => {
                    self.outcomes.push(Outcome::Error);
                    return Err(e);
                }
                Ok(Ok(p)) => p,
            };
            let got = match proto::s7_reply(&pdu) {
                Ok(reply) => reply.pdu_ref,
                Err(e) => {
                    self.outcomes.push(Outcome::Error);
                    return Err(protocol(e));
                }
            };
            if got != r {
                self.late += 1;
                self.outcomes.push(Outcome::Count(LATE_REPLIES));
                debug!(
                    got,
                    want = r,
                    late = self.late,
                    "dropped a reply to an earlier request"
                );
                continue;
            }
            return Ok((pdu, sent.elapsed()));
        }
    }

    /// Read Var of `items` (they fit the PDU). A header error (the PLC
    /// refused the whole request) is a point error with its text.
    pub async fn read(&mut self, items: &[Item]) -> Result<Vec<Result<Vec<u8>, u8>>, DriverError> {
        if items.is_empty() || items.len() > proto::MAX_ITEMS {
            return Err(DriverError::Point(format!(
                "a Read Var takes 1…{} items, not {}",
                proto::MAX_ITEMS,
                items.len()
            )));
        }
        let (pdu, rtt) = self.exchange(|r| proto::read_var(r, items)).await?;
        let r = parsed(&pdu, self)?;
        if r.error != 0 {
            self.answered(rtt, true);
            return Err(DriverError::Point(proto::error_text(r.error)));
        }
        let res: Vec<ItemResult<'_>> = match proto::read_reply(&r, items.len()) {
            Ok(res) => res,
            Err(e) => {
                self.outcomes.push(Outcome::Error);
                return Err(protocol(e));
            }
        };
        let failed = res.iter().any(Result::is_err);
        let out = res.into_iter().map(|x| x.map(<[u8]>::to_vec)).collect();
        self.answered(rtt, failed);
        Ok(out)
    }

    /// Write Var of one item. A header error or an item return code is a
    /// point error with its text.
    pub async fn write(&mut self, item: &Item, data: &[u8]) -> Result<(), DriverError> {
        let (pdu, rtt) = self.exchange(|r| proto::write_var(r, item, data)).await?;
        let r = parsed(&pdu, self)?;
        if r.error != 0 {
            self.answered(rtt, true);
            return Err(DriverError::Point(proto::error_text(r.error)));
        }
        let rc = match proto::write_reply(&r) {
            Ok(rc) => rc,
            Err(e) => {
                self.outcomes.push(Outcome::Error);
                return Err(protocol(e));
            }
        };
        self.answered(rtt, rc != proto::RC_OK);
        if rc != proto::RC_OK {
            return Err(DriverError::Point(proto::item_text(rc)));
        }
        Ok(())
    }

    /// Read SZL `id`/`index` (the first part).
    pub async fn szl(&mut self, id: u16, index: u16) -> Result<proto::Szl, DriverError> {
        let (pdu, rtt) = self.exchange(|r| proto::read_szl(r, id, index)).await?;
        let r = parsed(&pdu, self)?;
        let s = match proto::szl_reply(&r) {
            Ok(s) => s,
            Err(_) if r.error != 0 => {
                self.answered(rtt, true);
                return Err(DriverError::Point(proto::error_text(r.error)));
            }
            Err(e) => {
                self.outcomes.push(Outcome::Error);
                return Err(protocol(e));
            }
        };
        self.answered(rtt, s.error != 0);
        Ok(s)
    }
}

/// Parse a PDU [`Client::exchange`] matched (it parsed once already).
fn parsed<'a>(pdu: &'a [u8], c: &mut Client) -> Result<S7Reply<'a>, DriverError> {
    proto::s7_reply(pdu).map_err(|e| {
        c.outcomes.push(Outcome::Error);
        protocol(e)
    })
}
