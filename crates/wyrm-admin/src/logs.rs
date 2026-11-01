//! Broker logs in `sys` (as a DSA broker's log): a ring of the last log
//! events of this process, and a log level that changes at runtime.
//!
//! [`install`] sets the process's tracing subscriber once: a reloadable
//! `EnvFilter`, a [`LinkFilter`], the usual text output on stdout and a
//! [`Ring`]. Events of an embedded link run inside its `link{id=…}` span
//! (the link SDK instruments its tasks), so the ring knows their link and
//! the link filter applies that link's level. The `EnvFilter` opens the
//! most verbose level any link or the broker asks for; the link filter
//! narrows each event to its own. (`EnvFilter` span directives cannot do
//! this: a reloaded filter does not know the spans created before it.)
//! Tasks a driver spawns on its own without `in_current_span()` lose the
//! span: their events count as the broker's.
//!
//! Process links log to their own output; the supervisor keeps their last
//! lines in a [`Ring`] of their own.

use std::collections::{HashMap, VecDeque};
use std::fmt::Write as _;
use std::sync::{Arc, Mutex, OnceLock, RwLock};
use tracing::field::{Field, Visit};
use tracing::{Event, Level, Subscriber};
use tracing_subscriber::layer::Context;
use tracing_subscriber::registry::LookupSpan;
use tracing_subscriber::Layer;

/// Level names, lowest first; the only values a level may take.
pub const LEVELS: [&str; 5] = ["error", "warn", "info", "debug", "trace"];

/// One line of a log.
#[derive(Debug, Clone, PartialEq)]
pub struct LogLine {
    /// Unix milliseconds.
    pub t: u64,
    pub level: Level,
    pub target: String,
    /// The embedded link the event belongs to, if any.
    pub link: Option<String>,
    pub message: String,
}

/// Longest message kept; longer ones are cut.
const MAX_LINE: usize = 4096;

/// The last log lines, bounded by count and by bytes.
#[derive(Debug)]
pub struct Ring {
    lines: VecDeque<LogLine>,
    bytes: usize,
    max_lines: usize,
    max_bytes: usize,
}

fn cut(mut s: String) -> String {
    if s.len() > MAX_LINE {
        let mut end = MAX_LINE;
        while !s.is_char_boundary(end) {
            end -= 1;
        }
        s.truncate(end);
        s.push('…');
    }
    s
}

/// `ESC [ … letter` sequences (terminal colours) removed.
pub fn strip_ansi(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    let mut it = s.chars().peekable();
    while let Some(c) = it.next() {
        if c == '\u{1b}' && it.peek() == Some(&'[') {
            it.next();
            for d in it.by_ref() {
                if d.is_ascii_alphabetic() {
                    break;
                }
            }
            continue;
        }
        out.push(c);
    }
    out
}

/// The level name of a level.
pub fn level_name(l: Level) -> &'static str {
    match l {
        Level::ERROR => "error",
        Level::WARN => "warn",
        Level::INFO => "info",
        Level::DEBUG => "debug",
        Level::TRACE => "trace",
    }
}

/// A level from its name (one of [`LEVELS`]).
pub fn parse_level(s: &str) -> Option<Level> {
    Some(match s {
        "error" => Level::ERROR,
        "warn" => Level::WARN,
        "info" => Level::INFO,
        "debug" => Level::DEBUG,
        "trace" => Level::TRACE,
        _ => return None,
    })
}

impl Ring {
    pub fn new(max_lines: usize, max_bytes: usize) -> Self {
        Self {
            lines: VecDeque::new(),
            bytes: 0,
            max_lines,
            max_bytes,
        }
    }

    pub fn push(&mut self, mut line: LogLine) {
        line.message = cut(line.message);
        self.bytes += line.message.len() + line.target.len();
        self.lines.push_back(line);
        while self.lines.len() > self.max_lines || self.bytes > self.max_bytes {
            match self.lines.pop_front() {
                Some(old) => self.bytes -= old.message.len() + old.target.len(),
                None => break,
            }
        }
    }

    /// The last `n` lines at `min` or more severe, whose target or message
    /// contains `contains`, of `link` (when given), oldest first.
    pub fn tail(&self, n: usize, min: Level, contains: &str, link: Option<&str>) -> Vec<LogLine> {
        let mut out: Vec<LogLine> = self
            .lines
            .iter()
            .rev()
            .filter(|l| l.level <= min)
            .filter(|l| link.is_none_or(|id| l.link.as_deref() == Some(id)))
            .filter(|l| {
                contains.is_empty() || l.message.contains(contains) || l.target.contains(contains)
            })
            .take(n)
            .cloned()
            .collect();
        out.reverse();
        out
    }
}

pub fn now_ms() -> u64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_millis() as u64)
        .unwrap_or(0)
}

/// The `id` of a `link` span, kept in the span's extensions.
struct LinkId(String);

#[derive(Default)]
struct Fields {
    message: String,
    rest: String,
    id: Option<String>,
}

impl Visit for Fields {
    fn record_str(&mut self, f: &Field, v: &str) {
        match f.name() {
            "message" => self.message.push_str(v),
            "id" => self.id = Some(v.to_owned()),
            n => {
                let _ = write!(self.rest, " {n}={v}");
            }
        }
    }

    fn record_debug(&mut self, f: &Field, v: &dyn std::fmt::Debug) {
        match f.name() {
            "message" => {
                let _ = write!(self.message, "{v:?}");
            }
            "id" => self.id = Some(format!("{v:?}")),
            n => {
                let _ = write!(self.rest, " {n}={v:?}");
            }
        }
    }
}

/// The link of the innermost `link` span around `event`.
fn link_of<S>(event: &Event<'_>, ctx: &Context<'_, S>) -> Option<String>
where
    S: Subscriber + for<'a> LookupSpan<'a>,
{
    ctx.event_scope(event).and_then(|scope| {
        scope
            .from_root()
            .filter_map(|s| s.extensions().get::<LinkId>().map(|l| l.0.clone()))
            .last()
    })
}

/// The broker's level and each embedded link's.
#[derive(Debug, Clone)]
pub struct Levels {
    pub broker: Level,
    pub links: HashMap<String, Level>,
}

/// Marks `link` spans with their id and lets an event through only at its
/// link's level (or the broker's).
pub struct LinkFilter(pub Arc<RwLock<Levels>>);

impl<S> Layer<S> for LinkFilter
where
    S: Subscriber + for<'a> LookupSpan<'a>,
{
    fn on_new_span(
        &self,
        attrs: &tracing::span::Attributes<'_>,
        id: &tracing::span::Id,
        ctx: Context<'_, S>,
    ) {
        if attrs.metadata().name() != "link" {
            return;
        }
        let mut f = Fields::default();
        attrs.record(&mut f);
        if let (Some(link), Some(span)) = (f.id, ctx.span(id)) {
            span.extensions_mut().insert(LinkId(link));
        }
    }

    fn event_enabled(&self, event: &Event<'_>, ctx: Context<'_, S>) -> bool {
        let levels = self.0.read().unwrap_or_else(|p| p.into_inner());
        let max = link_of(event, &ctx)
            .and_then(|id| levels.links.get(&id).copied())
            .unwrap_or(levels.broker);
        *event.metadata().level() <= max
    }
}

/// A tracing layer that keeps events in a [`Ring`].
pub struct RingLayer(pub Arc<Mutex<Ring>>);

impl<S> Layer<S> for RingLayer
where
    S: Subscriber + for<'a> LookupSpan<'a>,
{
    fn on_event(&self, event: &Event<'_>, ctx: Context<'_, S>) {
        let mut f = Fields::default();
        event.record(&mut f);
        let link = link_of(event, &ctx);
        let meta = event.metadata();
        let line = LogLine {
            t: now_ms(),
            level: *meta.level(),
            target: meta.target().to_owned(),
            link,
            message: strip_ansi(&(f.message + &f.rest)),
        };
        self.0.lock().unwrap_or_else(|p| p.into_inner()).push(line);
    }
}

type Reload = Box<dyn Fn(&str) -> Result<(), String> + Send + Sync>;

/// The broker's log: its ring and its levels.
pub struct LogControl {
    ring: Arc<Mutex<Ring>>,
    reload: Reload,
    levels: Arc<RwLock<Levels>>,
}

static GLOBAL: OnceLock<Arc<LogControl>> = OnceLock::new();

/// The log control of this process, when [`install`] ran.
pub fn global() -> Option<Arc<LogControl>> {
    GLOBAL.get().cloned()
}

/// Lines and bytes the broker's ring keeps.
const BROKER_LINES: usize = 5000;
const BROKER_BYTES: usize = 2 << 20;

/// Set the process's tracing subscriber: `RUST_LOG` (or `info`) as the
/// first filter, text on stdout, and the ring. Once per process.
pub fn install() -> Arc<LogControl> {
    install_inner(true)
}

/// [`install`] without the text output (tests read the ring only).
pub fn install_quiet() -> Arc<LogControl> {
    install_inner(false)
}

fn install_inner(stdout: bool) -> Arc<LogControl> {
    // One builder at a time: a second subscriber loses `try_init`, and its
    // reload handle then points at a dropped subscriber.
    GLOBAL.get_or_init(|| build(stdout)).clone()
}

fn build(stdout: bool) -> Arc<LogControl> {
    use tracing_subscriber::layer::SubscriberExt;
    use tracing_subscriber::util::SubscriberInitExt;
    use tracing_subscriber::{reload, EnvFilter};
    let initial = std::env::var("RUST_LOG").unwrap_or_else(|_| "info,zenoh=warn".into());
    let filter = EnvFilter::try_new(&initial).unwrap_or_else(|_| EnvFilter::new("info,zenoh=warn"));
    let (filter, handle) = reload::Layer::new(filter);
    let ring = Arc::new(Mutex::new(Ring::new(BROKER_LINES, BROKER_BYTES)));
    // RUST_LOG's own level (its first bare level), or trace for a filter of
    // targets only: RUST_LOG then decides alone until a level is set here.
    let broker = initial
        .split(',')
        .find_map(|d| parse_level(d.trim()))
        .unwrap_or(Level::TRACE);
    let levels = Arc::new(RwLock::new(Levels {
        broker,
        links: HashMap::new(),
    }));
    let text = stdout.then(tracing_subscriber::fmt::layer);
    let _ = tracing_subscriber::registry()
        .with(filter)
        .with(LinkFilter(levels.clone()))
        .with(text)
        .with(RingLayer(ring.clone()))
        .try_init();
    Arc::new(LogControl {
        ring,
        reload: Box::new(move |d| {
            let f = EnvFilter::try_new(d).map_err(|e| e.to_string())?;
            handle.reload(f).map_err(|e| e.to_string())
        }),
        levels,
    })
}

/// Crates kept at `warn` unless the level is `trace`: zenoh, and the WASM compiler, which logs
/// every compilation pass at `debug` (thousands of lines per component: they pushed the
/// broker's own lines out of the log ring).
const QUIET: &[&str] = &[
    "zenoh",
    "cranelift_codegen",
    "cranelift_frontend",
    "wasmtime_internal_cranelift",
    "wasmtime",
    "regalloc2",
];

/// An `EnvFilter` for `level`: [`QUIET`] crates stay at `warn` unless it is `trace`.
/// Also the `RUST_LOG` of a process link.
pub fn env_directive(level: &str) -> String {
    if level == "trace" {
        level.to_owned()
    } else {
        let mut d = level.to_owned();
        for c in QUIET {
            d.push_str(&format!(",{c}=warn"));
        }
        d
    }
}

impl LogControl {
    /// The broker's level (one of [`LEVELS`]).
    pub fn level(&self) -> String {
        level_name(self.levels.read().unwrap_or_else(|p| p.into_inner()).broker).to_owned()
    }

    /// Set the broker's level; replaces the directives `RUST_LOG` gave.
    pub fn set_level(&self, level: &str) -> Result<(), String> {
        let l = parse_level(level).ok_or_else(|| format!("level {level:?}: one of {LEVELS:?}"))?;
        self.levels
            .write()
            .unwrap_or_else(|p| p.into_inner())
            .broker = l;
        self.apply()
    }

    /// Set (or, with `None`, clear) the level of one embedded link.
    pub fn set_link_level(&self, link: &str, level: Option<&str>) -> Result<(), String> {
        {
            let mut levels = self.levels.write().unwrap_or_else(|p| p.into_inner());
            match level {
                Some(l) => {
                    let l =
                        parse_level(l).ok_or_else(|| format!("level {l:?}: one of {LEVELS:?}"))?;
                    levels.links.insert(link.to_owned(), l);
                }
                None => {
                    levels.links.remove(link);
                }
            }
        }
        self.apply()
    }

    /// The `EnvFilter` opens the most verbose level wanted; [`LinkFilter`]
    /// narrows each event.
    fn apply(&self) -> Result<(), String> {
        let most = {
            let l = self.levels.read().unwrap_or_else(|p| p.into_inner());
            l.links.values().copied().fold(l.broker, std::cmp::max)
        };
        (self.reload)(&env_directive(level_name(most)))
    }

    pub fn tail(&self, n: usize, min: Level, contains: &str, link: Option<&str>) -> Vec<LogLine> {
        self.ring
            .lock()
            .unwrap_or_else(|p| p.into_inner())
            .tail(n, min, contains, link)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn line(level: Level, msg: &str, link: Option<&str>) -> LogLine {
        LogLine {
            t: 0,
            level,
            target: "t".into(),
            link: link.map(str::to_owned),
            message: msg.into(),
        }
    }

    #[test]
    fn ring_bounds_and_filters() {
        let mut r = Ring::new(3, 1 << 20);
        for i in 0..5 {
            r.push(line(Level::INFO, &format!("m{i}"), None));
        }
        let all = r.tail(10, Level::TRACE, "", None);
        assert_eq!(
            all.iter().map(|l| l.message.as_str()).collect::<Vec<_>>(),
            ["m2", "m3", "m4"]
        );
        r.push(line(Level::WARN, "w", Some("plc1")));
        assert_eq!(r.tail(10, Level::WARN, "", None).len(), 1);
        assert_eq!(r.tail(10, Level::TRACE, "", Some("plc1"))[0].message, "w");
        assert_eq!(r.tail(10, Level::TRACE, "m3", None).len(), 1);
        // bytes bound and the line cap
        let mut r = Ring::new(100, 10_000);
        for _ in 0..10 {
            r.push(line(Level::INFO, &"x".repeat(5000), None));
        }
        assert!(r.tail(100, Level::TRACE, "", None).len() <= 3);
        assert!(r.lines.iter().all(|l| l.message.len() <= MAX_LINE + 3));
    }

    #[test]
    fn ansi_and_directives() {
        assert_eq!(
            strip_ansi("\u{1b}[2m2026\u{1b}[0m \u{1b}[32m INFO\u{1b}[0m x"),
            "2026  INFO x"
        );
        assert!(env_directive("warn").starts_with("warn,zenoh=warn,cranelift_codegen=warn"));
        assert_eq!(env_directive("trace"), "trace");
    }

    #[test]
    fn link_levels_apply_to_spans_created_before() {
        use tracing_subscriber::layer::SubscriberExt;
        let ring = Arc::new(Mutex::new(Ring::new(100, 1 << 20)));
        let levels = Arc::new(RwLock::new(Levels {
            broker: Level::INFO,
            links: HashMap::new(),
        }));
        // the EnvFilter lets debug through; the link filter decides
        let sub = tracing_subscriber::registry()
            .with(tracing_subscriber::EnvFilter::new("debug"))
            .with(LinkFilter(levels.clone()))
            .with(RingLayer(ring.clone()));
        tracing::subscriber::with_default(sub, || {
            // spans exist before the link's level is set (as in the broker)
            let plc1 = tracing::error_span!("link", id = %"plc1");
            let plc2 = tracing::error_span!("link", id = %"plc2");
            tracing::debug!("broker debug: dropped");
            plc1.in_scope(|| tracing::debug!(reg = 5, "dropped before"));
            levels
                .write()
                .unwrap()
                .links
                .insert("plc1".into(), Level::DEBUG);
            plc1.in_scope(|| tracing::debug!(reg = 5, "read"));
            plc2.in_scope(|| {
                tracing::debug!("dropped");
                tracing::info!("kept");
            });
        });
        let got: Vec<(String, Option<String>)> = ring
            .lock()
            .unwrap()
            .tail(10, Level::TRACE, "", None)
            .into_iter()
            .map(|l| (l.message, l.link))
            .collect();
        assert_eq!(
            got,
            [
                ("read reg=5".to_owned(), Some("plc1".to_owned())),
                ("kept".to_owned(), Some("plc2".to_owned()))
            ]
        );
    }
}
