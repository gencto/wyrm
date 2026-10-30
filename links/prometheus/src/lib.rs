//! Prometheus / OpenMetrics scrape connector on the driver framework
//! (ADR 0004).
//!
//! Tree: `<conn>/<device>/<point>`; kinds [`Conn`] (one HTTP(S) endpoint,
//! e.g. `http://host:9100/metrics`) → [`Dev`] (a label filter applied to
//! all its points, so one scrape feeds several devices) → [`Point`] (a
//! series selector with an aggregate, a mode and an optional
//! `histogram_quantile`). Points are read-only.
//!
//! **One scrape per connection per `scrape_s`.** The framework polls each
//! `(device, period)` group on its own ticker; here every point has the
//! same short period ([`EVAL_TICK`]) and the connection's [`Transport`]
//! holds the last scrape. A poll scrapes only when the last good scrape is
//! `scrape_s` old; otherwise it evaluates the points on the scrape it has,
//! and values are published only when they change. Polls of other devices
//! in the same tick share one attempt. A failed scrape is not kept: the
//! next tick tries again, so each failed attempt is one miss of the
//! quality ladder (`uncertain/stale`, then `bad/comm_fail` after three);
//! after that, retries slow down to one per `scrape_s`.
//!
//! Errors ([`DriverError`]): a connect, TLS or I/O failure, a body over
//! `max_body_mib` or more series than `max_series` → `Transport` (the
//! connection fails with the reason and reconnects with backoff); no
//! complete response within `timeout_ms` or a non-2xx status → `Device`
//! (the quality ladder); a selector that matches nothing, several series
//! with `aggregate: none`, a NaN/±Inf result or a broken histogram →
//! `Point` (that point only). Opening the connection is a first scrape, and
//! any failure there fails the connection. Each scrape uses its own HTTP
//! connection, so a late reply can never be taken for a later scrape.

#![forbid(unsafe_code)]

pub mod eval;
pub mod expo;
pub mod http;
pub mod select;
#[cfg(feature = "sim")]
pub mod sim;

use eval::{Aggregate, Function, Mode};
use expo::{Scrape, Series};
use select::{Matcher, Selector};
use std::collections::{BTreeMap, HashMap, HashSet};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Arc;
use std::time::{Duration, Instant};
use tracing::debug;
use wyrm_core::meta::{ActionResult, ParamMeta, Writable, EDITOR_TEXTAREA};
use wyrm_core::{ActionMeta, NodeMeta, Perm, Status, TypeCode, Value};
use wyrm_link_sdk::driver::params::{field, ParamSpec};
use wyrm_link_sdk::driver::{
    Driver, DriverError, Framework, Level, Outcome, ParamEnum, Params, PointId, Target,
};
use wyrm_link_sdk::{LinkError, Secret};

/// The `prometheus` link: the framework running [`PrometheusDriver`].
pub type Prometheus = Framework<PrometheusDriver>;

/// The poll period of every point: how often points are evaluated on the
/// last scrape (scrapes themselves follow `scrape_s`).
pub const EVAL_TICK: Duration = Duration::from_secs(1);

/// Time to parse a large body, beside `timeout_ms`.
const PARSE_MARGIN: Duration = Duration::from_secs(5);

/// Bound on `list_series` (it may scrape).
const LIST_ACTION_MS: u32 = 70_000;

/// Diagnostics counter of skipped exposition lines.
const PARSE_ERRORS: &str = "parse_errors";

fn bad(name: &str, what: impl std::fmt::Display) -> LinkError {
    LinkError::invalid_parameter(format!("{name}: {what}"))
}

// ---------- parameters ----------

/// One scrape endpoint.
#[derive(Clone)]
pub struct Conn {
    pub url: http::Url,
    url_text: String,
    pub timeout_ms: u32,
    pub scrape_s: f64,
    pub username: String,
    password: Secret,
    bearer_token: Secret,
    pub ca_pem: String,
    pub cert_pem: String,
    key_pem: Secret,
    pub insecure_skip_verify: bool,
    headers_text: String,
    headers: Vec<(hyper::header::HeaderName, hyper::header::HeaderValue)>,
    pub gzip: bool,
    pub max_body_mib: u32,
    pub max_series: u32,
}

impl PartialEq for Conn {
    fn eq(&self, o: &Self) -> bool {
        self.to_map() == o.to_map()
    }
}

fn secret_str(s: &Secret) -> String {
    s.expose_str().unwrap_or_default().to_owned()
}

impl Params for Conn {
    fn schema() -> Vec<ParamSpec> {
        vec![
            ParamSpec::new("url", TypeCode::String)
                .dest()
                .display("URL")
                .placeholder("http://127.0.0.1:9100/metrics")
                .desc("http:// or https:// endpoint of the exposition"),
            ParamSpec::new("timeout_ms", TypeCode::Number)
                .default(5000u64)
                .bounds(100.0, 60_000.0)
                .display("Timeout (ms)")
                .desc("bound on one scrape: connect, TLS, headers and body"),
            ParamSpec::new("scrape_s", TypeCode::Number)
                .default(15.0)
                .bounds(1.0, 3600.0)
                .display("Scrape Interval (s)"),
            ParamSpec::new("username", TypeCode::String)
                .default("")
                .display("Username")
                .desc("basic auth user"),
            ParamSpec::new("password", TypeCode::String)
                .default("")
                .secret()
                .display("Password")
                .desc("basic auth password (kept sealed by the link)"),
            ParamSpec::new("bearer_token", TypeCode::String)
                .default("")
                .secret()
                .display("Bearer Token")
                .desc("instead of basic auth (kept sealed by the link)"),
            ParamSpec::new("ca_pem", TypeCode::String)
                .default("")
                .dest()
                .editor(EDITOR_TEXTAREA)
                .display("CA Certificates (PEM)")
                .desc("for https; empty = the system roots"),
            ParamSpec::new("cert_pem", TypeCode::String)
                .default("")
                .editor(EDITOR_TEXTAREA)
                .display("Client Certificate (PEM)")
                .desc("for mutual TLS"),
            ParamSpec::new("key_pem", TypeCode::String)
                .default("")
                .secret()
                .display("Client Key (PEM)")
                .desc("private key of cert_pem"),
            ParamSpec::new("insecure_skip_verify", TypeCode::Bool)
                .default(false)
                .dest()
                .display("Skip Certificate Check")
                .desc("accept any server certificate (testing only)"),
            ParamSpec::new("headers", TypeCode::String)
                .default("")
                .editor(EDITOR_TEXTAREA)
                .display("Extra Headers")
                .placeholder("X-Scope-OrgID: plant")
                .desc("one `Name: value` per line; not for credentials"),
            ParamSpec::new("gzip", TypeCode::Bool)
                .default(true)
                .display("Accept Gzip"),
            ParamSpec::new("max_body_mib", TypeCode::Number)
                .default(8u64)
                .bounds(1.0, 256.0)
                .display("Max Body (MiB)"),
            ParamSpec::new("max_series", TypeCode::Number)
                .default(100_000u64)
                .bounds(1.0, 1_000_000.0)
                .display("Max Series"),
        ]
    }

    fn from_map(m: &BTreeMap<String, Value>) -> wyrm_link_sdk::Result<Self> {
        let url_text = field::string(m, "url")?;
        let url = http::Url::parse(&url_text).map_err(|e| bad("url", e))?;
        let headers_text = field::string(m, "headers")?;
        let headers = http::parse_headers(&headers_text).map_err(|e| bad("headers", e))?;
        let c = Conn {
            url,
            url_text,
            timeout_ms: field::int(m, "timeout_ms")?,
            scrape_s: field::f64(m, "scrape_s")?,
            username: field::string(m, "username")?,
            password: Secret::new(field::string(m, "password")?),
            bearer_token: Secret::new(field::string(m, "bearer_token")?),
            ca_pem: field::string(m, "ca_pem")?,
            cert_pem: field::string(m, "cert_pem")?,
            key_pem: Secret::new(field::string(m, "key_pem")?),
            insecure_skip_verify: field::bool(m, "insecure_skip_verify")?,
            headers_text,
            headers,
            gzip: field::bool(m, "gzip")?,
            max_body_mib: field::int(m, "max_body_mib")?,
            max_series: field::int(m, "max_series")?,
        };
        let tls_only = !c.ca_pem.is_empty() || !c.cert_pem.is_empty() || c.insecure_skip_verify;
        if !c.url.tls && tls_only {
            return Err(bad(
                "url",
                "ca_pem, cert_pem and insecure_skip_verify need an https:// url",
            ));
        }
        if c.cert_pem.is_empty() != c.key_pem.expose().is_empty() {
            return Err(bad("cert_pem", "cert_pem and key_pem go together"));
        }
        if c.insecure_skip_verify && !c.ca_pem.is_empty() {
            return Err(bad("ca_pem", "no ca_pem with insecure_skip_verify"));
        }
        if !c.ca_pem.is_empty() || !c.cert_pem.is_empty() {
            // Parse now: a bad PEM is an edit error, not a connect failure.
            http::tls_config(&c.ca_pem, &c.cert_pem, &c.key_pem, c.insecure_skip_verify)
                .map_err(|e| bad("tls", e))?;
        }
        let basic = !c.username.is_empty() || !c.password.expose().is_empty();
        let bearer = !c.bearer_token.expose().is_empty();
        if basic && bearer {
            return Err(bad(
                "bearer_token",
                "give username/password or bearer_token, not both",
            ));
        }
        if !c.password.expose().is_empty() && c.username.is_empty() {
            return Err(bad("username", "required with password"));
        }
        if c.username.contains(':') {
            return Err(bad("username", "must not contain ':'"));
        }
        if (basic || bearer) && !c.url.tls && !c.url.is_loopback() {
            return Err(bad(
                "url",
                "credentials are never sent in plaintext to a non-loopback host: use https://",
            ));
        }
        if http::auth_header(&c.username, &c.password, &c.bearer_token).is_none()
            && (basic || bearer)
        {
            return Err(bad("password", "not a valid header value"));
        }
        Ok(c)
    }

    fn to_map(&self) -> BTreeMap<String, Value> {
        BTreeMap::from([
            ("url".into(), Value::Str(self.url_text.clone())),
            ("timeout_ms".into(), Value::UInt(self.timeout_ms.into())),
            ("scrape_s".into(), Value::Float(self.scrape_s)),
            ("username".into(), Value::Str(self.username.clone())),
            ("password".into(), Value::Str(secret_str(&self.password))),
            (
                "bearer_token".into(),
                Value::Str(secret_str(&self.bearer_token)),
            ),
            ("ca_pem".into(), Value::Str(self.ca_pem.clone())),
            ("cert_pem".into(), Value::Str(self.cert_pem.clone())),
            ("key_pem".into(), Value::Str(secret_str(&self.key_pem))),
            (
                "insecure_skip_verify".into(),
                Value::Bool(self.insecure_skip_verify),
            ),
            ("headers".into(), Value::Str(self.headers_text.clone())),
            ("gzip".into(), Value::Bool(self.gzip)),
            ("max_body_mib".into(), Value::UInt(self.max_body_mib.into())),
            ("max_series".into(), Value::UInt(self.max_series.into())),
        ])
    }
}

/// A logical group of series under the connection.
#[derive(Debug, Clone, PartialEq)]
pub struct Dev {
    labels_text: String,
    /// Applied to every point of the device.
    pub labels: Vec<Matcher>,
}

impl Params for Dev {
    fn schema() -> Vec<ParamSpec> {
        vec![ParamSpec::new("labels", TypeCode::String)
            .default("")
            .display("Label Filter")
            .placeholder("instance=\"a\", job=~\"node.*\"")
            .desc("matchers (=, !=, =~, !~) applied to every point; empty = all series")]
    }

    fn from_map(m: &BTreeMap<String, Value>) -> wyrm_link_sdk::Result<Self> {
        let labels_text = field::string(m, "labels")?;
        let labels = Selector::parse_matchers(&labels_text).map_err(|e| bad("labels", e))?;
        Ok(Dev {
            labels_text,
            labels,
        })
    }

    fn to_map(&self) -> BTreeMap<String, Value> {
        BTreeMap::from([("labels".into(), Value::Str(self.labels_text.clone()))])
    }
}

/// A series selector and what to compute from it.
#[derive(Debug, Clone, PartialEq)]
pub struct Point {
    selector_text: String,
    pub selector: Selector,
    pub aggregate: Aggregate,
    pub mode: Mode,
    pub function: Function,
    pub q: f64,
    pub scale: f64,
    pub offset: f64,
    pub unit: String,
}

impl Point {
    /// The exposed series name a point reads.
    fn series_name(&self) -> String {
        let n = &self.selector.name;
        if self.function == Function::HistogramQuantile && !n.ends_with("_bucket") {
            format!("{n}_bucket")
        } else {
            n.clone()
        }
    }
}

impl Params for Point {
    fn schema() -> Vec<ParamSpec> {
        vec![
            ParamSpec::new("selector", TypeCode::String)
                .display("Selector")
                .placeholder("node_cpu_seconds_total{mode=\"idle\"}")
                .desc("metric name with optional label matchers (=, !=, =~, !~)"),
            ParamSpec::new("aggregate", TypeCode::Enum)
                .one_of(Aggregate::NAMES)
                .default("none")
                .display("Aggregate")
                .desc("when several series match; none = exactly one must match"),
            ParamSpec::new("mode", TypeCode::Enum)
                .one_of(Mode::NAMES)
                .default("raw")
                .display("Mode")
                .desc("rate_per_s: increase per second between scrapes (counter resets handled)"),
            ParamSpec::new("function", TypeCode::Enum)
                .one_of(Function::NAMES)
                .default("value")
                .display("Function")
                .desc("histogram_quantile: the q quantile from the _bucket series"),
            ParamSpec::new("q", TypeCode::Number)
                .default(0.5)
                .bounds(0.0, 1.0)
                .display("Quantile")
                .desc("for histogram_quantile"),
            ParamSpec::new("scale", TypeCode::Number)
                .default(1.0)
                .display("Scaling"),
            ParamSpec::new("offset", TypeCode::Number)
                .default(0.0)
                .display("Scaling Offset"),
            ParamSpec::new("unit", TypeCode::String)
                .default("")
                .display("Unit"),
        ]
    }

    fn from_map(m: &BTreeMap<String, Value>) -> wyrm_link_sdk::Result<Self> {
        let selector_text = field::string(m, "selector")?;
        let selector = Selector::parse(&selector_text).map_err(|e| bad("selector", e))?;
        if selector.name.is_empty() {
            return Err(bad("selector", "needs a metric name"));
        }
        let p = Point {
            selector_text,
            selector,
            aggregate: field::enumv(m, "aggregate")?,
            mode: field::enumv(m, "mode")?,
            function: field::enumv(m, "function")?,
            q: field::f64(m, "q")?,
            scale: field::f64(m, "scale")?,
            offset: field::f64(m, "offset")?,
            unit: field::string(m, "unit")?,
        };
        if p.function == Function::HistogramQuantile && p.aggregate != Aggregate::None {
            return Err(bad(
                "aggregate",
                "histogram_quantile sums the buckets of all matching series by le; \
                 leave aggregate at none",
            ));
        }
        Ok(p)
    }

    fn to_map(&self) -> BTreeMap<String, Value> {
        BTreeMap::from([
            ("selector".into(), Value::Str(self.selector_text.clone())),
            ("aggregate".into(), Value::Str(self.aggregate.name().into())),
            ("mode".into(), Value::Str(self.mode.name().into())),
            ("function".into(), Value::Str(self.function.name().into())),
            ("q".into(), Value::Float(self.q)),
            ("scale".into(), Value::Float(self.scale)),
            ("offset".into(), Value::Float(self.offset)),
            ("unit".into(), Value::Str(self.unit.clone())),
        ])
    }
}

// ---------- transport: the scrape cache ----------

/// One good scrape.
struct Snapshot {
    seq: u64,
    at: Instant,
    scrape: Arc<Scrape>,
}

/// The state of one `rate_per_s` point between scrapes.
struct RateState {
    /// The scrape the state was last updated from.
    seq: u64,
    at: Instant,
    /// Value per series (full label set) at `at`.
    prev: HashMap<String, f64>,
    /// The result computed at `seq` (`None`: no earlier scrape yet).
    last: Option<Result<f64, String>>,
}

/// The open endpoint: its client and the last scrape.
pub struct Transport {
    client: http::Client,
    scrape_every: Duration,
    max_series: usize,
    insecure: bool,
    seq: u64,
    good: Option<Snapshot>,
    /// Start of the last attempt and its outcome.
    attempt: Option<(Instant, Result<(), DriverError>)>,
    /// Failed attempts in a row.
    fails: u32,
    /// Plans (device groups) that got the last attempt's failure.
    served: HashSet<u64>,
    rates: HashMap<(u64, PointId), RateState>,
    outcomes: Vec<Outcome>,
}

impl Transport {
    fn new(c: &Conn) -> Result<Self, DriverError> {
        let tls = if c.url.tls {
            Some(
                http::tls_config(&c.ca_pem, &c.cert_pem, &c.key_pem, c.insecure_skip_verify)
                    .map_err(DriverError::Transport)?,
            )
        } else {
            None
        };
        let client = http::Client::new(
            c.url.clone(),
            tls,
            c.headers.clone(),
            http::auth_header(&c.username, &c.password, &c.bearer_token),
            c.gzip,
            c.max_body_mib as usize * 1024 * 1024,
            Duration::from_millis(c.timeout_ms.into()),
        )
        .map_err(DriverError::Transport)?;
        Ok(Self {
            client,
            scrape_every: Duration::from_secs_f64(c.scrape_s),
            max_series: c.max_series as usize,
            insecure: c.insecure_skip_verify,
            seq: 0,
            good: None,
            attempt: None,
            fails: 0,
            served: HashSet::new(),
            rates: HashMap::new(),
            outcomes: Vec::new(),
        })
    }

    /// Make sure there is a current scrape: reuse it, or scrape now.
    /// `plan`: the device group that polls (`None`: an action).
    ///
    /// A good scrape serves every poll until it is `scrape_s` old. A failed
    /// attempt serves each group once (one miss per group per attempt, and
    /// one attempt per round of polls, however long it took); a group that
    /// already got it tries again, after the ladder reached `bad/comm_fail`
    /// only once per `scrape_s`.
    async fn ensure(&mut self, plan: Option<u64>) -> Result<(), DriverError> {
        let half = EVAL_TICK / 2;
        if let Some((at, r)) = &self.attempt {
            let age = Instant::now().saturating_duration_since(*at);
            let fresh = age + half < self.scrape_every;
            match r {
                Ok(()) if fresh || age < half => return Ok(()),
                Ok(()) => {}
                Err(e) => {
                    let first = match plan {
                        Some(id) => self.served.insert(id),
                        None => age < half,
                    };
                    let slow = matches!(e, DriverError::Device(_))
                        && fresh
                        && self.fails >= stale_misses();
                    if first || slow {
                        return r.clone();
                    }
                }
            }
        }
        let r = self.scrape().await;
        self.served.clear();
        if let Some(id) = plan {
            self.served.insert(id);
        }
        r
    }

    async fn scrape(&mut self) -> Result<(), DriverError> {
        let at = Instant::now();
        let r = self.fetch_and_parse().await;
        match &r {
            Ok(scrape) => {
                self.seq += 1;
                self.fails = 0;
                // Rate states not updated for a few scrapes belong to points
                // that are gone (a re-plan gives new plan ids).
                let seq = self.seq;
                self.rates.retain(|_, s| s.seq + 3 >= seq);
                self.good = Some(Snapshot {
                    seq,
                    at,
                    scrape: scrape.clone(),
                });
            }
            Err(e) => {
                self.fails = self.fails.saturating_add(1);
                self.good = None;
                debug!(url = %self.client.url.authority, fails = self.fails, "scrape failed: {e}");
            }
        }
        let r = r.map(|_| ());
        self.attempt = Some((at, r.clone()));
        r
    }

    async fn fetch_and_parse(&mut self) -> Result<Arc<Scrape>, DriverError> {
        let started = Instant::now();
        let f = match self.client.fetch().await {
            Ok(f) => f,
            Err(e) => {
                return Err(match e {
                    http::FetchError::Timeout => {
                        self.outcomes.push(Outcome::Timeout);
                        DriverError::Device(format!(
                            "no complete response within {} ms",
                            self.client_timeout_ms()
                        ))
                    }
                    http::FetchError::Status(code, reason) => {
                        self.outcomes.push(Outcome::Exception(started.elapsed()));
                        DriverError::Device(format!("HTTP {code} {reason}").trim_end().to_owned())
                    }
                    http::FetchError::Io(e) | http::FetchError::TooLarge(e) => {
                        self.outcomes.push(Outcome::Error);
                        DriverError::Transport(e)
                    }
                });
            }
        };
        self.outcomes.push(Outcome::Reply(f.rtt));
        let max = self.max_series;
        let parsed = tokio::task::spawn_blocking(move || {
            let text = String::from_utf8_lossy(&f.body);
            expo::parse(&text, max)
        })
        .await
        .map_err(|e| DriverError::Transport(format!("parse task: {e}")))?
        .map_err(|e| DriverError::Transport(e.to_string()))?;
        if parsed.bad_lines > 0 {
            if let Some((line, why)) = parsed.first_bad {
                debug!(
                    url = %self.client.url.authority,
                    skipped = parsed.bad_lines,
                    first = line,
                    "exposition lines skipped: {why}"
                );
            }
            for _ in 0..parsed.bad_lines.min(10_000) {
                self.outcomes.push(Outcome::Count(PARSE_ERRORS));
            }
        }
        Ok(Arc::new(parsed))
    }

    fn client_timeout_ms(&self) -> u128 {
        self.client.timeout().as_millis()
    }
}

fn stale_misses() -> u32 {
    <PrometheusDriver as Driver>::stale_misses()
}

// ---------- evaluation ----------

/// The points of one `(device, period)` group, with an id that keys their
/// rate state.
pub struct Plan {
    id: u64,
    points: Vec<(PointId, Point)>,
}

static PLAN_IDS: AtomicU64 = AtomicU64::new(1);

fn matching<'a>(s: &'a Scrape, name: &str, dev: &Dev, p: &Point) -> Vec<&'a Series> {
    s.named(name)
        .filter(|x| p.selector.matches_labels(x) && dev.labels.iter().all(|m| m.matches(x)))
        .collect()
}

/// Per-series inputs of a point at this scrape: raw values, or (with
/// `rate_per_s`) increases since the last scrape, per second for values.
/// `None`: no earlier scrape to compare with yet. Updates `state` to this
/// scrape.
fn inputs(
    series: &[&Series],
    mode: Mode,
    snap: &Snapshot,
    state: &mut Option<RateState>,
    per_second: bool,
) -> Option<Vec<(usize, f64)>> {
    if mode == Mode::Raw {
        return Some(series.iter().map(|s| s.value).enumerate().collect());
    }
    let out = state.as_ref().map(|p| {
        let dt = snap.at.saturating_duration_since(p.at).as_secs_f64();
        series
            .iter()
            .enumerate()
            .filter_map(|(i, s)| {
                let before = p.prev.get(&s.key_without(""))?;
                let inc = eval::increase(*before, s.value);
                Some((i, if per_second { inc / dt.max(1e-3) } else { inc }))
            })
            .collect::<Vec<_>>()
    });
    *state = Some(RateState {
        seq: snap.seq,
        at: snap.at,
        prev: series
            .iter()
            .map(|s| (s.key_without(""), s.value))
            .collect(),
        last: None,
    });
    out
}

/// One point's value on the snapshot; `None` = nothing to publish yet (a
/// rate before its second scrape).
fn evaluate(
    snap: &Snapshot,
    dev: &Dev,
    p: &Point,
    state: &mut Option<RateState>,
) -> Option<Result<f64, String>> {
    let series = matching(&snap.scrape, &p.series_name(), dev, p);
    let r = match p.function {
        Function::Value => {
            if series.is_empty() {
                eval::aggregate(p.aggregate, &[])
            } else {
                let v = inputs(&series, p.mode, snap, state, true)?;
                if v.is_empty() {
                    // Only series new since the last scrape: no rate yet.
                    return None;
                }
                let values: Vec<f64> = v.into_iter().map(|(_, x)| x).collect();
                eval::aggregate(p.aggregate, &values)
            }
        }
        Function::HistogramQuantile => {
            if series.is_empty() {
                Err(format!("no {} series matches", p.series_name()))
            } else {
                let v = inputs(&series, p.mode, snap, state, false)?;
                let mut buckets = Vec::with_capacity(v.len());
                let mut bad_le = false;
                for (i, c) in v {
                    match series[i].label("le").and_then(expo::parse_value) {
                        Some(le) => buckets.push((le, c)),
                        None => bad_le = true,
                    }
                }
                if bad_le {
                    Err("a bucket without a valid le label".to_owned())
                } else {
                    eval::histogram_quantile(p.q, &buckets)
                }
            }
        }
    };
    Some(r.and_then(|v| {
        let v = v * p.scale + p.offset;
        if v.is_finite() {
            Ok(v)
        } else {
            Err(format!("the value is not a finite number ({v})"))
        }
    }))
}

// ---------- driver ----------

pub struct PrometheusDriver;

impl Driver for PrometheusDriver {
    const NAME: &'static str = "prometheus";
    const VERSION: &'static str = env!("CARGO_PKG_VERSION");
    type Conn = Conn;
    type Dev = Dev;
    type Point = Point;
    type Transport = Transport;
    type Plan = Plan;

    /// A first scrape: any failure fails the connection with the reason.
    async fn open(conn: &Conn) -> Result<Transport, DriverError> {
        let mut t = Transport::new(conn)?;
        match t.scrape().await {
            Ok(()) => Ok(t),
            Err(DriverError::Device(e)) | Err(DriverError::Point(e)) => {
                Err(DriverError::Transport(e))
            }
            Err(e) => Err(e),
        }
    }

    /// Never called: there is no periodic ping (see [`Driver::ping_period`]).
    async fn ping(_t: &mut Transport, _dev: &Dev) -> Result<(), DriverError> {
        Ok(())
    }

    fn plan(_dev: &Dev, points: &[(PointId, Point)]) -> Plan {
        Plan {
            id: PLAN_IDS.fetch_add(1, Ordering::Relaxed),
            points: points.to_vec(),
        }
    }

    async fn poll(
        t: &mut Transport,
        dev: &Dev,
        plan: &Plan,
    ) -> Vec<(PointId, Result<Value, DriverError>)> {
        if let Err(e) = t.ensure(Some(plan.id)).await {
            return plan
                .points
                .iter()
                .map(|(id, _)| (id.clone(), Err(e.clone())))
                .collect();
        }
        let Some(snap) = &t.good else {
            return Vec::new();
        };
        let mut out = Vec::with_capacity(plan.points.len());
        for (id, p) in &plan.points {
            let r = if p.mode == Mode::RatePerS {
                let key = (plan.id, id.clone());
                match t.rates.get(&key) {
                    // Between scrapes: the value computed at this scrape.
                    Some(st) if st.seq == snap.seq => st.last.clone(),
                    _ => {
                        let mut st = t.rates.remove(&key);
                        let r = evaluate(snap, dev, p, &mut st);
                        if let Some(mut st) = st {
                            st.seq = snap.seq;
                            st.last = r.clone();
                            t.rates.insert(key, st);
                        }
                        r
                    }
                }
            } else {
                evaluate(snap, dev, p, &mut None)
            };
            if let Some(r) = r {
                out.push((id.clone(), r.map(Value::Float).map_err(DriverError::Point)));
            }
        }
        out
    }

    async fn write(
        _t: &mut Transport,
        _dev: &Dev,
        _id: &str,
        _point: &Point,
        _v: &Value,
    ) -> Result<(), DriverError> {
        Err(DriverError::Point("prometheus points are read-only".into()))
    }

    fn point_meta(p: &Point) -> NodeMeta {
        let mut m = NodeMeta::number().writable(Writable::Never);
        if !p.unit.is_empty() {
            m = m.unit(p.unit.clone());
        }
        m
    }

    fn poll_period(_p: &Point) -> Duration {
        EVAL_TICK
    }

    /// No ping: a ping that answers `Ok` would mark a device good between
    /// failed scrapes. Devices get their state from polls (a device
    /// without points stays `Connecting`).
    fn ping_period(_dev: &Dev) -> Option<Duration> {
        None
    }

    fn io_timeout(conn: &Conn) -> Duration {
        Duration::from_millis(conn.timeout_ms.into()) + PARSE_MARGIN
    }

    fn actions(level: Level, _kind: &str) -> Vec<(&'static str, ActionMeta)> {
        match level {
            Level::Connection => vec![(
                "list_series",
                ActionMeta::new()
                    .level(Perm::Read)
                    .display("List Series")
                    .timeout_ms(LIST_ACTION_MS)
                    .result(ActionResult::Type(TypeCode::Map))
                    .param(
                        "match",
                        ParamMeta::of(TypeCode::String)
                            .display("Match")
                            .placeholder("node_cpu_seconds_total{mode=\"idle\"}")
                            .description("selector; empty = every series"),
                    )
                    .param(
                        "limit",
                        ParamMeta::of(TypeCode::Number)
                            .display("Limit")
                            .description("at most this many series (1…10000)"),
                    ),
            )],
            Level::Device => Vec::new(),
        }
    }

    async fn invoke(
        t: &mut Transport,
        _conn: &Conn,
        target: Target<'_, Self>,
        action: &str,
        args: &Value,
    ) -> Result<Value, LinkError> {
        match (target, action) {
            (Target::Connection, "list_series") => list_series(t, args).await,
            _ => Err(LinkError::not_supported(format!("action {action}"))),
        }
    }

    const DIAGNOSTICS: bool = true;
    const DIAG_EXTRA: &'static [&'static str] = &[PARSE_ERRORS];

    fn take_outcomes(t: &mut Transport) -> Vec<Outcome> {
        std::mem::take(&mut t.outcomes)
    }

    fn status_note(t: &Transport) -> Option<String> {
        t.insecure
            .then(|| "insecure_skip_verify: the server certificate is not checked".to_owned())
    }
}

/// `list_series {match?, limit = 200}`: series of the last scrape.
async fn list_series(t: &mut Transport, args: &Value) -> Result<Value, LinkError> {
    let empty = BTreeMap::new();
    let args = match args {
        Value::Map(m) => m,
        _ => &empty,
    };
    let sel = match args.get("match") {
        None | Some(Value::Null) => Selector::default(),
        Some(Value::Str(s)) => Selector::parse(s).map_err(|e| bad("match", e))?,
        Some(_) => return Err(bad("match", "expected a selector string")),
    };
    let limit = match args.get("limit") {
        None | Some(Value::Null) => 200,
        Some(v) => match v.as_f64() {
            Some(x) if x.fract() == 0.0 && (1.0..=10_000.0).contains(&x) => x as usize,
            _ => return Err(bad("limit", "an integer 1…10000")),
        },
    };
    if let Err(e) = t.ensure(None).await {
        return Err(match e {
            DriverError::Transport(e) => LinkError::new(Status::Disconnected, e),
            DriverError::Device(e) | DriverError::Point(e) => {
                LinkError::new(Status::NotAvailable, e)
            }
        });
    }
    let Some(snap) = &t.good else {
        return Err(LinkError::new(Status::NotAvailable, "no scrape yet"));
    };
    let s = &snap.scrape;
    let mut total = 0u64;
    let mut rows = Vec::new();
    for x in s.series.iter().filter(|x| sel.matches(x)) {
        total += 1;
        if rows.len() < limit {
            let labels = x
                .labels
                .iter()
                .map(|(k, v)| (k.clone(), Value::Str(v.clone())))
                .collect();
            let value = if x.value.is_finite() {
                Value::Float(x.value)
            } else {
                Value::Str(
                    match x.value {
                        v if v.is_nan() => "NaN",
                        v if v > 0.0 => "+Inf",
                        _ => "-Inf",
                    }
                    .into(),
                )
            };
            rows.push(Value::Map(BTreeMap::from([
                ("name".into(), Value::Str(x.name.clone())),
                ("type".into(), Value::Str(s.type_of(&x.name).name().into())),
                ("labels".into(), Value::Map(labels)),
                ("value".into(), value),
            ])));
        }
    }
    Ok(Value::Map(BTreeMap::from([
        ("total".into(), Value::UInt(total)),
        ("truncated".into(), Value::Bool(total as usize > rows.len())),
        ("bad_lines".into(), Value::UInt(s.bad_lines as u64)),
        (
            "age_ms".into(),
            Value::UInt(snap.at.elapsed().as_millis().min(u64::MAX as u128) as u64),
        ),
        ("series".into(), Value::Array(rows)),
    ])))
}
