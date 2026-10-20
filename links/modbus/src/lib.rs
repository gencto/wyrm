//! Modbus TCP connector.
//!
//! One link = one device (unit id). Points are polled every `poll_ms`; a value
//! is published when it or its quality changes. All I/O is bounded by
//! `timeout_ms`. Quality is honest: a failed cycle marks every point
//! `uncertain/stale`, `stale_cycles` failed cycles in a row mark them
//! `bad/comm_fail`; a Modbus exception marks that one point `bad/device_error`.
//! Writes go to coils and holding registers and are read back before `ok`.

#![forbid(unsafe_code)]

pub mod codec;
mod config;
#[cfg(feature = "sim")]
pub mod sim;

pub use config::{DataKind, ModbusConfig, PointConfig, Table};

use std::net::SocketAddr;
use std::sync::Arc;
use tokio::sync::Mutex;
use tokio_modbus::client::{tcp, Context};
use tokio_modbus::prelude::{Reader, Writer};
use tokio_modbus::{ExceptionCode, Slave};
use tracing::{debug, info};
use wyrm_core::meta::Writable;
use wyrm_core::{NodeMeta, Quality, Status, TypeCode, Value};
use wyrm_link_sdk::{now_us, Caller, Link, LinkCtx, LinkError, Result};

pub const QUAL_STALE: &str = "uncertain/stale";
pub const QUAL_COMM_FAIL: &str = "bad/comm_fail";
pub const QUAL_DEVICE_ERROR: &str = "bad/device_error";

/// Why one point could not be read or written.
#[derive(Debug)]
enum IoFail {
    /// The device answered with a Modbus exception: the link is fine.
    Exception(ExceptionCode),
    /// Timeout, transport or protocol error: drop the connection.
    Link(String),
}

struct Shared {
    cfg: ModbusConfig,
    conn: Mutex<Option<Context>>,
}

impl Shared {
    async fn connect(&self) -> std::result::Result<Context, String> {
        let t = self.cfg.timeout();
        let target = format!("{}:{}", self.cfg.host, self.cfg.port);
        let addr: SocketAddr = tokio::time::timeout(t, tokio::net::lookup_host(&target))
            .await
            .map_err(|_| format!("resolve {target}: timeout"))?
            .map_err(|e| format!("resolve {target}: {e}"))?
            .next()
            .ok_or_else(|| format!("resolve {target}: no address"))?;
        tokio::time::timeout(t, tcp::connect_slave(addr, Slave(self.cfg.unit)))
            .await
            .map_err(|_| format!("connect {target}: timeout"))?
            .map_err(|e| format!("connect {target}: {e}"))
    }
}

async fn bounded<T>(
    t: std::time::Duration,
    f: impl std::future::Future<Output = tokio_modbus::Result<T>>,
) -> std::result::Result<T, IoFail> {
    match tokio::time::timeout(t, f).await {
        Err(_) => Err(IoFail::Link("timeout".into())),
        Ok(Err(e)) => Err(IoFail::Link(e.to_string())),
        Ok(Ok(Err(code))) => Err(IoFail::Exception(code)),
        Ok(Ok(Ok(v))) => Ok(v),
    }
}

async fn read_point(
    ctx: &mut Context,
    p: &PointConfig,
    t: std::time::Duration,
) -> std::result::Result<Value, IoFail> {
    let n = p.kind.words();
    let raw = match p.table {
        Table::Coil => {
            return bounded(t, ctx.read_coils(p.address, 1))
                .await
                .and_then(|b| bit(&b))
        }
        Table::Discrete => {
            return bounded(t, ctx.read_discrete_inputs(p.address, 1))
                .await
                .and_then(|b| bit(&b))
        }
        Table::Input => bounded(t, ctx.read_input_registers(p.address, n)).await?,
        Table::Holding => bounded(t, ctx.read_holding_registers(p.address, n)).await?,
    };
    let v = p
        .kind
        .decode(&raw, p.word_swap)
        .ok_or_else(|| IoFail::Link("short register response".into()))?;
    Ok(Value::Float(v * p.scale + p.offset))
}

fn bit(b: &[bool]) -> std::result::Result<Value, IoFail> {
    b.first()
        .map(|v| Value::Bool(*v))
        .ok_or_else(|| IoFail::Link("short coil response".into()))
}

fn meta_for(p: &PointConfig) -> NodeMeta {
    let mut m = if p.kind == DataKind::Bool {
        NodeMeta::leaf(TypeCode::Bool)
    } else {
        NodeMeta::number()
    };
    if let Some(u) = &p.unit {
        m = m.unit(u.clone());
    }
    m.writable(if p.writable {
        Writable::Write
    } else {
        Writable::Never
    })
}

fn exception_error(code: ExceptionCode) -> LinkError {
    match code {
        ExceptionCode::IllegalDataAddress => {
            LinkError::invalid_parameter("device: illegal data address")
        }
        ExceptionCode::IllegalDataValue => {
            LinkError::new(Status::OutOfRange, "device: illegal data value")
        }
        ExceptionCode::ServerDeviceBusy => LinkError::new(Status::Busy, "device busy"),
        other => LinkError::internal(format!("device exception {other:?}")),
    }
}

pub struct Modbus {
    ctx: LinkCtx,
    shared: Arc<Shared>,
    poller: Option<tokio::task::JoinHandle<()>>,
}

impl Link for Modbus {
    const NAME: &'static str = "modbus";
    const VERSION: &'static str = env!("CARGO_PKG_VERSION");
    type Config = ModbusConfig;

    async fn start(cfg: ModbusConfig, ctx: LinkCtx) -> Result<Self> {
        cfg.validate()?;
        // Folders for every parent segment, then the points.
        for p in &cfg.points {
            let mut parent = String::new();
            for seg in p
                .path
                .split('/')
                .rev()
                .skip(1)
                .collect::<Vec<_>>()
                .into_iter()
                .rev()
            {
                if !parent.is_empty() {
                    parent.push('/');
                }
                parent.push_str(seg);
                if ctx.meta(&parent).is_none() {
                    ctx.declare_node(&parent, NodeMeta::folder()).await?;
                }
            }
            ctx.declare_node(&p.path, meta_for(p)).await?;
        }
        let shared = Arc::new(Shared {
            cfg,
            conn: Mutex::new(None),
        });
        let poller = tokio::spawn(poll(ctx.clone(), shared.clone()));
        Ok(Self {
            ctx,
            shared,
            poller: Some(poller),
        })
    }

    async fn on_set(&mut self, path: &str, value: Value, _who: &Caller) -> Result<()> {
        let p = self
            .shared
            .cfg
            .points
            .iter()
            .find(|p| p.path == path)
            .ok_or_else(|| LinkError::not_found(path.to_owned()))?
            .clone();
        let t = self.shared.cfg.timeout();
        let mut guard = self.shared.conn.lock().await;
        let Some(conn) = guard.as_mut() else {
            return Err(LinkError::new(Status::Disconnected, "device not connected"));
        };
        let written = match (p.table, &value) {
            (Table::Coil, Value::Bool(b)) => {
                bounded(t, conn.write_single_coil(p.address, *b)).await
            }
            (Table::Holding, v) => {
                let x = v
                    .as_f64()
                    .ok_or_else(|| LinkError::invalid_parameter("expected number"))?;
                let words = p
                    .kind
                    .encode((x - p.offset) / p.scale, p.word_swap)
                    .ok_or_else(|| {
                        LinkError::new(Status::OutOfRange, "value does not fit the register")
                    })?;
                if words.len() == 1 {
                    bounded(t, conn.write_single_register(p.address, words[0])).await
                } else {
                    bounded(t, conn.write_multiple_registers(p.address, &words)).await
                }
            }
            _ => return Err(LinkError::not_supported("point is not writable")),
        };
        match written {
            Ok(()) => {}
            Err(IoFail::Exception(code)) => return Err(exception_error(code)),
            Err(IoFail::Link(e)) => {
                *guard = None;
                return Err(LinkError::new(Status::Disconnected, e));
            }
        }
        // Read back: publish what the device holds, not what was asked.
        match read_point(conn, &p, t).await {
            Ok(v) => self.ctx.update(&p.path, v, Quality::Good, now_us()).await,
            Err(IoFail::Exception(code)) => Err(exception_error(code)),
            Err(IoFail::Link(e)) => {
                *guard = None;
                Err(LinkError::new(Status::Disconnected, e))
            }
        }
    }

    async fn stop(&mut self) {
        if let Some(p) = self.poller.take() {
            p.abort();
        }
        if let Some(mut c) = self.shared.conn.lock().await.take() {
            use tokio_modbus::client::Client;
            let _ = tokio::time::timeout(self.shared.cfg.timeout(), c.disconnect()).await;
        }
    }
}

async fn poll(ctx: LinkCtx, sh: Arc<Shared>) {
    let mut iv = tokio::time::interval(sh.cfg.poll());
    iv.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Delay);
    let t = sh.cfg.timeout();
    let mut fails = 0u32;
    loop {
        iv.tick().await;
        if ctx.is_closed() {
            return;
        }
        let mut ok = true;
        {
            let mut guard = sh.conn.lock().await;
            if guard.is_none() {
                match sh.connect().await {
                    Ok(c) => {
                        info!(host = %sh.cfg.host, "modbus connected");
                        *guard = Some(c);
                    }
                    Err(e) => {
                        debug!("modbus: {e}");
                        ok = false;
                    }
                }
            }
            if let Some(conn) = guard.as_mut() {
                for p in &sh.cfg.points {
                    // The tree holds what was last published (poll, set, mark_all).
                    let prev = ctx.last(&p.path);
                    let (v, q, qual) = match read_point(conn, p, t).await {
                        Ok(v) => (v, Quality::Good, None),
                        Err(IoFail::Exception(code)) => {
                            debug!(path = %p.path, ?code, "modbus exception");
                            let v = prev.as_ref().map(|s| s.v.clone()).unwrap_or(Value::Null);
                            (v, Quality::Bad, Some(QUAL_DEVICE_ERROR))
                        }
                        Err(IoFail::Link(e)) => {
                            debug!("modbus link error: {e}");
                            *guard = None;
                            ok = false;
                            break;
                        }
                    };
                    if prev.is_none_or(|s| s.v != v || s.q != q) {
                        let s = wyrm_core::Sample { v, q, t: now_us() };
                        if ctx.update_sample(&p.path, s, qual).await.is_err() {
                            return; // link stopped
                        }
                    }
                }
            }
        }
        if ok {
            fails = 0;
            continue;
        }
        fails += 1;
        // Mark once on each transition: first failure, then the give-up cycle.
        let mark = if fails == sh.cfg.stale_cycles.max(1) {
            Some((Quality::Bad, QUAL_COMM_FAIL))
        } else if fails == 1 {
            Some((Quality::Uncertain, QUAL_STALE))
        } else {
            None
        };
        if let Some((q, qual)) = mark {
            // The next good read republishes: the stored quality now differs.
            if ctx.mark_all(q, Some(qual)).await.is_err() {
                return;
            }
        }
    }
}
