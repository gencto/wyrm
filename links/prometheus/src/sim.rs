//! In-process Prometheus exporter for tests and demos (feature `sim`).
//!
//! A small HTTP/1.1 server (one request per connection, `Connection:
//! close`) that serves a text exposition 0.0.4 — or OpenMetrics 1.0 when
//! [`Exporter::openmetrics`] is set — with:
//!
//! * `sim_requests_total{path="/a"|"/b"}`: counters that grow by 1 and 2
//!   per scrape (and [`Exporter::counter_a`] to set or reset them);
//! * `sim_temperature_celsius{instance="a"|"b",sensor="t1"}`: gauges;
//! * `sim_latency_seconds`: a histogram with buckets 0.1, 0.5, 1, +Inf;
//! * `sim_rpc_seconds`: a summary with quantiles 0.5 and 0.9;
//! * `sim_escaped{text=…}` with escaped label values, `sim_nan NaN`.
//!
//! Failure modes ([`Fail`]): a 500 reply, silence (the request is read,
//! nothing comes back), a slow body, an oversized body, malformed lines,
//! and a disconnect right after the request. Optional basic or bearer
//! auth ([`Exporter::require_auth`]); gzip when the client accepts it and
//! [`Exporter::gzip`] is on.

use std::fmt::Write as _;
use std::io::Write as _;
use std::net::SocketAddr;
use std::sync::{Arc, Mutex};
use std::time::Duration;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::{TcpListener, TcpStream};
use tokio::task::JoinHandle;

/// How the exporter misbehaves.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum Fail {
    #[default]
    None,
    /// `500 Internal Server Error`.
    Error500,
    /// Read the request, never answer (until the client gives up).
    Silent,
    /// Headers at once, then the body a few bytes every 200 ms.
    SlowBody,
    /// A body of [`Exporter::oversize_bytes`].
    Oversize,
    /// Broken lines between the good ones.
    Malformed,
    /// Close the connection right after the request.
    Disconnect,
}

/// The simulated exporter's state, shared with the test.
#[derive(Debug, Clone)]
pub struct Exporter {
    pub fail: Fail,
    /// Requests seen (every mode).
    pub requests: u64,
    pub counter_a: f64,
    pub counter_b: f64,
    pub temp_a: f64,
    pub temp_b: f64,
    /// Cumulative counts of the buckets 0.1, 0.5, 1, +Inf.
    pub buckets: [f64; 4],
    pub openmetrics: bool,
    pub gzip: bool,
    /// `Authorization` value a request must carry (`None`: no auth).
    pub require_auth: Option<String>,
    pub oversize_bytes: usize,
    /// Headers of the last request (names lowercase).
    pub last_headers: Vec<(String, String)>,
    /// Lines appended to the exposition.
    pub extra: Vec<String>,
}

impl Default for Exporter {
    fn default() -> Self {
        Self {
            fail: Fail::None,
            requests: 0,
            counter_a: 0.0,
            counter_b: 0.0,
            temp_a: 21.5,
            temp_b: 19.0,
            buckets: [10.0, 20.0, 20.0, 20.0],
            openmetrics: false,
            gzip: true,
            require_auth: None,
            oversize_bytes: 9 * 1024 * 1024,
            last_headers: Vec::new(),
            extra: Vec::new(),
        }
    }
}

impl Exporter {
    /// The exposition at the current state.
    pub fn body(&self) -> String {
        let mut b = String::new();
        let om = self.openmetrics;
        let total = if om {
            "sim_requests"
        } else {
            "sim_requests_total"
        };
        let _ = writeln!(b, "# HELP {total} Requests served.");
        let _ = writeln!(b, "# TYPE {total} counter");
        let _ = writeln!(
            b,
            "sim_requests_total{{path=\"/a\"}} {}",
            fmt(self.counter_a)
        );
        let _ = writeln!(
            b,
            "sim_requests_total{{path=\"/b\"}} {}",
            fmt(self.counter_b)
        );
        let _ = writeln!(b, "# TYPE sim_temperature_celsius gauge");
        if om {
            let _ = writeln!(b, "# UNIT sim_temperature_celsius celsius");
        }
        let _ = writeln!(
            b,
            "sim_temperature_celsius{{instance=\"a\",sensor=\"t1\"}} {}",
            fmt(self.temp_a)
        );
        let _ = writeln!(
            b,
            "sim_temperature_celsius{{sensor=\"t1\",instance=\"b\"}} {} 1700000000000",
            fmt(self.temp_b)
        );
        let _ = writeln!(b, "# TYPE sim_latency_seconds histogram");
        for (le, c) in ["0.1", "0.5", "1", "+Inf"].iter().zip(self.buckets) {
            let _ = writeln!(b, "sim_latency_seconds_bucket{{le=\"{le}\"}} {}", fmt(c));
        }
        let _ = writeln!(b, "sim_latency_seconds_sum 4.5");
        let _ = writeln!(b, "sim_latency_seconds_count {}", fmt(self.buckets[3]));
        let _ = writeln!(b, "# TYPE sim_rpc_seconds summary");
        let _ = writeln!(b, "sim_rpc_seconds{{quantile=\"0.5\"}} 0.05");
        let _ = writeln!(b, "sim_rpc_seconds{{quantile=\"0.9\"}} 0.2");
        let _ = writeln!(b, "sim_rpc_seconds_sum 12.5");
        let _ = writeln!(b, "sim_rpc_seconds_count 100");
        let _ = writeln!(
            b,
            "sim_escaped{{text=\"a \\\"quoted\\\" \\\\ value\\nnext\"}} 1"
        );
        let _ = writeln!(b, "sim_nan NaN");
        if self.fail == Fail::Malformed {
            let _ = writeln!(b, "9broken 1");
            let _ = writeln!(b, "sim_broken{{l=\"x}} 1");
            let _ = writeln!(b, "sim_broken_value abc");
        }
        for l in &self.extra {
            let _ = writeln!(b, "{l}");
        }
        if om {
            let _ = writeln!(b, "# EOF");
        }
        b
    }

    fn content_type(&self) -> &'static str {
        if self.openmetrics {
            "application/openmetrics-text; version=1.0.0; charset=utf-8"
        } else {
            "text/plain; version=0.0.4; charset=utf-8"
        }
    }
}

fn fmt(v: f64) -> String {
    if v.is_nan() {
        "NaN".into()
    } else if v == f64::INFINITY {
        "+Inf".into()
    } else if v == f64::NEG_INFINITY {
        "-Inf".into()
    } else {
        format!("{v}")
    }
}

pub type Shared = Arc<Mutex<Exporter>>;

fn lock(s: &Shared) -> std::sync::MutexGuard<'_, Exporter> {
    s.lock().unwrap_or_else(|p| p.into_inner())
}

/// Serve on `addr`; returns the bound address, the shared state and the
/// accept task (abort it to stop: open connections end with it).
pub async fn spawn(addr: &str) -> std::io::Result<(SocketAddr, Shared, JoinHandle<()>)> {
    let l = TcpListener::bind(addr).await?;
    let local = l.local_addr()?;
    let state: Shared = Arc::new(Mutex::new(Exporter::default()));
    let st = state.clone();
    let task = tokio::spawn(async move {
        let mut conns = tokio::task::JoinSet::new();
        loop {
            tokio::select! {
                r = l.accept() => match r {
                    Ok((s, _)) => {
                        let st = st.clone();
                        conns.spawn(async move { serve(s, st).await });
                    }
                    Err(_) => return,
                },
                Some(_) = conns.join_next(), if !conns.is_empty() => {}
            }
        }
    });
    Ok((local, state, task))
}

async fn serve(mut s: TcpStream, st: Shared) {
    // The request head (bounded); the body of a GET is ignored.
    let mut head = Vec::new();
    let mut buf = [0u8; 2048];
    while !head.windows(4).any(|w| w == b"\r\n\r\n") {
        match tokio::time::timeout(Duration::from_secs(10), s.read(&mut buf)).await {
            Ok(Ok(n)) if n > 0 => head.extend_from_slice(&buf[..n]),
            _ => return,
        }
        if head.len() > 16 * 1024 {
            return;
        }
    }
    let text = String::from_utf8_lossy(&head).into_owned();
    let headers: Vec<(String, String)> = text
        .split("\r\n")
        .skip(1)
        .filter_map(|l| l.split_once(':'))
        .map(|(n, v)| (n.trim().to_ascii_lowercase(), v.trim().to_owned()))
        .collect();
    let header = |n: &str| headers.iter().find(|(k, _)| k == n).map(|(_, v)| v.clone());
    let (fail, body, ctype, gzip, authorized, oversize) = {
        let mut e = lock(&st);
        e.requests += 1;
        e.last_headers = headers.clone();
        let authorized = match &e.require_auth {
            None => true,
            Some(want) => header("authorization").as_deref() == Some(want.as_str()),
        };
        let gzip = e.gzip
            && header("accept-encoding").is_some_and(|v| v.contains("gzip"))
            && e.fail != Fail::SlowBody;
        let out = (
            e.fail,
            e.body(),
            e.content_type(),
            gzip,
            authorized,
            e.oversize_bytes,
        );
        if authorized && e.fail == Fail::None || e.fail == Fail::Malformed {
            e.counter_a += 1.0;
            e.counter_b += 2.0;
        }
        out
    };
    let reply = |status: &str, extra: &str, len: usize| {
        format!(
            "HTTP/1.1 {status}\r\nContent-Type: text/plain\r\n{extra}Content-Length: {len}\r\n\
             Connection: close\r\n\r\n"
        )
    };
    match fail {
        Fail::Disconnect => return,
        Fail::Silent => {
            // Hold the connection until the client drops it.
            let _ = s.read(&mut buf).await;
            return;
        }
        Fail::Error500 => {
            let msg = "exporter failed\n";
            let _ = s
                .write_all(
                    format!("{}{msg}", reply("500 Internal Server Error", "", msg.len()))
                        .as_bytes(),
                )
                .await;
            return;
        }
        _ => {}
    }
    if !authorized {
        let msg = "unauthorized\n";
        let _ = s
            .write_all(format!("{}{msg}", reply("401 Unauthorized", "", msg.len())).as_bytes())
            .await;
        return;
    }
    match fail {
        Fail::Oversize => {
            let _ = s.write_all(reply("200 OK", "", oversize).as_bytes()).await;
            let line = b"sim_filler 1\n";
            let mut sent = 0;
            while sent < oversize {
                let n = line.len().min(oversize - sent);
                if s.write_all(&line[..n]).await.is_err() {
                    return;
                }
                sent += n;
            }
        }
        Fail::SlowBody => {
            let b = body.into_bytes();
            let _ = s.write_all(reply("200 OK", "", b.len()).as_bytes()).await;
            for chunk in b.chunks(8) {
                if s.write_all(chunk).await.is_err() {
                    return;
                }
                tokio::time::sleep(Duration::from_millis(200)).await;
            }
        }
        _ => {
            let (bytes, enc) = if gzip {
                let mut z =
                    flate2::write::GzEncoder::new(Vec::new(), flate2::Compression::default());
                let _ = z.write_all(body.as_bytes());
                (z.finish().unwrap_or_default(), "Content-Encoding: gzip\r\n")
            } else {
                (body.into_bytes(), "")
            };
            let head = reply("200 OK", enc, bytes.len()).replace("text/plain", ctype);
            let _ = s.write_all(head.as_bytes()).await;
            let _ = s.write_all(&bytes).await;
        }
    }
    let _ = s.shutdown().await;
}
