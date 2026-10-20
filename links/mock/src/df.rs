//! `mockdev`: the mock as a framework driver (ADR 0004), with injectable
//! failures for tests — a connection that refuses to open, a device that
//! does not answer, points that raise protocol exceptions, slow polls.

use std::collections::HashMap;
use std::f64::consts::TAU;
use std::time::Duration;
use wyrm_core::meta::Writable;
use wyrm_core::{NodeMeta, Value};
use wyrm_link_sdk::driver::{Driver, DriverError, PointId};
use wyrm_link_sdk::{now_us, ParamEnum, Params};

#[derive(Debug, Clone, PartialEq, Params)]
pub struct Conn {
    /// `true`: `open` fails (transport down).
    #[param(default = false)]
    pub down: bool,
    /// Added to every poll.
    #[param(default = 0, max = 10000)]
    pub latency_ms: u32,
    /// Where `token` goes (a destination field: changing it drops a stored
    /// token unless the edit supplies it again).
    #[param(default = "sim", dest)]
    pub host: String,
    /// `open` fails while `token` is empty (secret handling tests).
    #[param(default = false)]
    pub need_token: bool,
    #[param(default = "", secret)]
    pub token: String,
}

#[derive(Debug, Clone, PartialEq, Params)]
pub struct Dev {
    #[param(default = 1, min = 1, max = 247)]
    pub unit: u8,
    #[param(default = 1.0, min = 0.05, max = 3600.0)]
    pub ping_s: f64,
    /// `true`: the device never answers (polls and pings time out).
    #[param(default = false)]
    pub silent: bool,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, ParamEnum)]
pub enum Kind {
    Wave,
    Counter,
    Constant,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, ParamEnum)]
pub enum Fail {
    None,
    Exception,
}

#[derive(Debug, Clone, PartialEq, Params)]
pub struct Point {
    #[param(enum, default = "wave")]
    pub kind: Kind,
    #[param(default = 1.0, min = 0.01, max = 3600.0)]
    pub poll_s: f64,
    #[param(default = "")]
    pub unit: String,
    #[param(default = false)]
    pub writable: bool,
    #[param(enum, default = "none")]
    pub fail: Fail,
    #[param(default = 0.0)]
    pub initial: f64,
}

pub struct Transport {
    latency: Duration,
    /// Held values of counter/constant points and written values.
    values: HashMap<PointId, f64>,
}

pub struct MockDev;

impl Driver for MockDev {
    const NAME: &'static str = "mockdev";
    const VERSION: &'static str = env!("CARGO_PKG_VERSION");
    type Conn = Conn;
    type Dev = Dev;
    type Point = Point;
    type Transport = Transport;
    type Plan = Vec<(PointId, Point)>;

    async fn open(conn: &Conn) -> Result<Transport, DriverError> {
        if conn.down {
            return Err(DriverError::Transport("connection refused".into()));
        }
        if conn.need_token && conn.token.is_empty() {
            return Err(DriverError::Transport("authentication failed".into()));
        }
        Ok(Transport {
            latency: Duration::from_millis(conn.latency_ms.into()),
            values: HashMap::new(),
        })
    }

    async fn ping(_t: &mut Transport, dev: &Dev) -> Result<(), DriverError> {
        if dev.silent {
            // Never answers: the framework's timeout turns this into a miss.
            std::future::pending::<()>().await;
        }
        Ok(())
    }

    fn plan(_dev: &Dev, points: &[(PointId, Point)]) -> Self::Plan {
        points.to_vec()
    }

    async fn poll(
        t: &mut Transport,
        dev: &Dev,
        plan: &Self::Plan,
    ) -> Vec<(PointId, Result<Value, DriverError>)> {
        if !t.latency.is_zero() {
            tokio::time::sleep(t.latency).await;
        }
        if dev.silent {
            return plan
                .iter()
                .map(|(id, _)| (id.clone(), Err(DriverError::Device("no answer".into()))))
                .collect();
        }
        let secs = now_us() as f64 / 1e6;
        plan.iter()
            .enumerate()
            .map(|(k, (id, p))| {
                if p.fail == Fail::Exception {
                    return (
                        id.clone(),
                        Err(DriverError::Point("illegal data address".into())),
                    );
                }
                let v = match p.kind {
                    Kind::Wave => t
                        .values
                        .get(id)
                        .copied()
                        .unwrap_or_else(|| 20.0 + 10.0 * (TAU * secs / 60.0 + k as f64).sin()),
                    Kind::Counter => {
                        let c = t.values.entry(id.clone()).or_insert(p.initial);
                        *c += 1.0;
                        *c
                    }
                    Kind::Constant => *t.values.entry(id.clone()).or_insert(p.initial),
                };
                (id.clone(), Ok(Value::Float(v)))
            })
            .collect()
    }

    async fn write(
        t: &mut Transport,
        dev: &Dev,
        id: &str,
        point: &Point,
        v: &Value,
    ) -> Result<(), DriverError> {
        if dev.silent {
            return Err(DriverError::Device("no answer".into()));
        }
        if point.fail == Fail::Exception {
            return Err(DriverError::Point("illegal data value".into()));
        }
        let x = v
            .as_f64()
            .ok_or_else(|| DriverError::Point("expected a number".into()))?;
        t.values.insert(id.to_owned(), x);
        Ok(())
    }

    fn point_meta(p: &Point) -> NodeMeta {
        let mut m = NodeMeta::number().writable(if p.writable {
            Writable::Write
        } else {
            Writable::Never
        });
        if !p.unit.is_empty() {
            m = m.unit(p.unit.clone());
        }
        m
    }

    fn poll_period(p: &Point) -> Duration {
        Duration::from_secs_f64(p.poll_s)
    }

    fn ping_period(dev: &Dev) -> Option<Duration> {
        Some(Duration::from_secs_f64(dev.ping_s))
    }

    fn io_timeout(_conn: &Conn) -> Duration {
        Duration::from_millis(500)
    }
}
