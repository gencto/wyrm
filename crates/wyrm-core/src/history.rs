//! A history read as spec 01 writes it on a `~val` selector: `history=<from>..<to>` (or
//! `since=<from>`), `agg`, `window`, `limit`. One typed value, [`HistoryQuery`], that a
//! requester builds from parsed input and encodes with [`HistoryQuery::params`], and that the
//! historian parses back with [`HistoryQuery::parse`]. No request text reaches a selector:
//! before this type a `from` of `…Z..&limit=100000&x=` added its own `limit` to the gateway's
//! selector (typing audit 2026-11-15, S2).

use crate::status::Status;
use crate::time::{iso_us_exact, parse_interval, parse_iso, US_PER_S};
use crate::Value;
use std::collections::BTreeMap;
use std::num::{NonZeroU64, NonZeroUsize};

/// Microseconds since the Unix epoch, UTC.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub struct TimeUs(pub u64);

impl TimeUs {
    /// An RFC 3339 timestamp or a date (its midnight UTC); `None` for any other text.
    pub fn parse(s: &str) -> Option<Self> {
        parse_iso(s).map(Self)
    }
}

/// How the samples of one window become one value (spec 01 `agg`; names as DSA's rollups).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum Rollup {
    None,
    And,
    Or,
    Avg,
    Min,
    Max,
    Sum,
    First,
    Last,
    Count,
    Delta,
}

impl Rollup {
    pub const ALL: [Rollup; 11] = [
        Rollup::None,
        Rollup::And,
        Rollup::Or,
        Rollup::Avg,
        Rollup::Min,
        Rollup::Max,
        Rollup::Sum,
        Rollup::First,
        Rollup::Last,
        Rollup::Count,
        Rollup::Delta,
    ];

    pub fn name(self) -> &'static str {
        match self {
            Rollup::None => "none",
            Rollup::And => "and",
            Rollup::Or => "or",
            Rollup::Avg => "avg",
            Rollup::Min => "min",
            Rollup::Max => "max",
            Rollup::Sum => "sum",
            Rollup::First => "first",
            Rollup::Last => "last",
            Rollup::Count => "count",
            Rollup::Delta => "delta",
        }
    }

    /// A name of [`Self::ALL`]; empty text is [`Rollup::None`].
    pub fn parse(s: &str) -> Option<Self> {
        let s = s.trim();
        if s.is_empty() {
            return Some(Rollup::None);
        }
        Self::ALL.into_iter().find(|r| r.name() == s)
    }
}

/// A rollup window (spec 01 `window`): whole seconds, at least one.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub struct Window(NonZeroU64);

impl Window {
    /// `None` when the window in microseconds does not fit a `u64`.
    pub fn from_secs(secs: NonZeroU64) -> Option<Self> {
        secs.get().checked_mul(US_PER_S).map(|_| Self(secs))
    }

    /// `<n>s|m|h|d|w` (`5m`, `1h`); empty or `none` is no window.
    pub fn parse(s: &str) -> Result<Option<Self>, HistoryParamError> {
        let us = parse_interval(s).map_err(|_| HistoryParamError::Window)?;
        Ok(us
            .and_then(|us| NonZeroU64::new(us / US_PER_S))
            .and_then(Self::from_secs))
    }

    pub fn secs(self) -> u64 {
        self.0.get()
    }

    /// The window in microseconds (fits: checked when it was made).
    pub fn us(self) -> u64 {
        self.0.get().saturating_mul(US_PER_S)
    }
}

/// Why a history read was refused: `invalid_parameter` (spec 01).
#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
pub enum HistoryParamError {
    #[error("history: from is required")]
    NoFrom,
    #[error("history: {0} is no RFC 3339 time or date")]
    Time(&'static str),
    #[error("history: from is after to (an empty to is now)")]
    Backwards,
    #[error("history: agg is one of none, avg, min, max, sum, count, first, last, delta, and, or")]
    Agg,
    #[error("history: window is <n>s, m, h, d or w, more than zero")]
    Window,
    #[error("history: limit is a whole number from 1")]
    Limit,
    #[error("history: {0} must be text")]
    Text(&'static str),
    #[error("history: the arguments are a map")]
    Args,
    #[error("history: {0} is given more than once")]
    Duplicate(&'static str),
    #[error("history: history and since together; give one")]
    Both,
    #[error("history: {0:?} is no history parameter (history, since, agg, window, limit)")]
    Unknown(String),
}

impl HistoryParamError {
    /// The status of the refusal.
    pub fn status(&self) -> Status {
        Status::InvalidParameter
    }
}

/// One history read of a point (spec 01, spec 03).
#[derive(Debug, Clone, PartialEq)]
pub struct HistoryQuery {
    pub from: TimeUs,
    /// `None`: up to now, on the historian's clock.
    pub to: Option<TimeUs>,
    pub rollup: Rollup,
    pub window: Option<Window>,
    /// `None`: the historian's default; it caps every value.
    pub limit: Option<NonZeroUsize>,
}

/// The parameters of a history selector, in [`HistoryQuery::parse`] slot order.
const KEYS: [&str; 5] = ["history", "since", "agg", "window", "limit"];

impl HistoryQuery {
    /// Raw rows from `from` to now.
    pub fn since(from: TimeUs) -> Self {
        Self {
            from,
            to: None,
            rollup: Rollup::None,
            window: None,
            limit: None,
        }
    }

    /// From texts as a person writes them: `from` and `to` in RFC 3339 or as dates (`to`
    /// empty = now), `agg` a rollup name, `window` `<n>s|m|h|d|w`.
    pub fn from_text(
        from: &str,
        to: &str,
        agg: Option<&str>,
        window: Option<&str>,
        limit: Option<usize>,
    ) -> Result<Self, HistoryParamError> {
        let from = from.trim();
        if from.is_empty() {
            return Err(HistoryParamError::NoFrom);
        }
        let from = TimeUs::parse(from).ok_or(HistoryParamError::Time("from"))?;
        let to = match to.trim() {
            "" => None,
            t => Some(TimeUs::parse(t).ok_or(HistoryParamError::Time("to"))?),
        };
        if to.is_some_and(|to| from > to) {
            return Err(HistoryParamError::Backwards);
        }
        let rollup = match agg {
            None => Rollup::None,
            Some(a) => Rollup::parse(a).ok_or(HistoryParamError::Agg)?,
        };
        let window = Window::parse(window.unwrap_or(""))?;
        let limit = match limit {
            None => None,
            Some(n) => Some(NonZeroUsize::new(n).ok_or(HistoryParamError::Limit)?),
        };
        Ok(Self {
            from,
            to,
            rollup,
            window,
            limit,
        })
    }

    /// From the frame args of the gateway and the FFI: `{from, to?, agg?, window?, limit?}`,
    /// texts as [`Self::from_text`], `limit` a whole number. Other keys are not read.
    pub fn from_args(args: Option<&Value>) -> Result<Self, HistoryParamError> {
        let empty = BTreeMap::new();
        let m = match args {
            None | Some(Value::Null) => &empty,
            Some(Value::Map(m)) => m,
            Some(_) => return Err(HistoryParamError::Args),
        };
        let text = |k: &'static str| match m.get(k) {
            None | Some(Value::Null) => Ok(None),
            Some(Value::Str(s)) if s.trim().is_empty() => Ok(None),
            Some(Value::Str(s)) => Ok(Some(s.as_str())),
            Some(_) => Err(HistoryParamError::Text(k)),
        };
        let limit = match m.get("limit") {
            None | Some(Value::Null) => None,
            Some(Value::UInt(n)) => Some(usize::try_from(*n).unwrap_or(usize::MAX)),
            Some(Value::Int(n)) => Some(usize::try_from(*n).map_err(|_| HistoryParamError::Limit)?),
            // a whole number of at least 1 (a JSON client's `20.0`); `as` saturates above
            // `usize::MAX`, where the cap applies anyway
            Some(Value::Float(f)) if f.is_finite() && f.fract() == 0.0 && *f >= 1.0 => {
                Some(*f as usize)
            }
            Some(_) => return Err(HistoryParamError::Limit),
        };
        Self::from_text(
            text("from")?.unwrap_or_default(),
            text("to")?.unwrap_or_default(),
            text("agg")?,
            text("window")?,
            limit,
        )
    }

    /// The selector parameters, `&`-separated as spec 01 writes them. Only typed values go in:
    /// times as RFC 3339 with microseconds, the rollup's name, the window in seconds, a number.
    pub fn params(&self) -> String {
        let mut p = format!("history={}..", iso_us_exact(self.from.0));
        if let Some(to) = self.to {
            p.push_str(&iso_us_exact(to.0));
        }
        if self.rollup != Rollup::None {
            p.push_str("&agg=");
            p.push_str(self.rollup.name());
        }
        if let Some(w) = self.window {
            p.push_str(&format!("&window={}s", w.secs()));
        }
        if let Some(l) = self.limit {
            p.push_str(&format!("&limit={l}"));
        }
        p
    }

    /// The parameters of a `~val` selector (spec 01, split on `&` and `;`). `None` when it
    /// asks for no history (neither `history` nor `since`): the storage answers it. A history
    /// read names each of `history` | `since`, `agg`, `window`, `limit` at most once and no
    /// other parameter; names that start with `_` are Zenoh's own and are not read.
    pub fn parse(params: &str) -> Result<Option<Self>, HistoryParamError> {
        let pairs = || {
            params
                .split(['&', ';'])
                .filter(|kv| !kv.is_empty())
                .map(|kv| kv.split_once('=').unwrap_or((kv, "")))
        };
        if !pairs().any(|(k, _)| k == "history" || k == "since") {
            return Ok(None);
        }
        let mut seen: [Option<&str>; 5] = [None; 5];
        for (k, v) in pairs() {
            if k.starts_with('_') {
                continue;
            }
            let i = KEYS
                .iter()
                .position(|n| *n == k)
                .ok_or_else(|| HistoryParamError::Unknown(k.chars().take(32).collect()))?;
            if seen[i].replace(v).is_some() {
                return Err(HistoryParamError::Duplicate(KEYS[i]));
            }
        }
        let [history, since, agg, window, limit] = seen;
        let (from, to) = match (history, since) {
            (Some(_), Some(_)) => return Err(HistoryParamError::Both),
            (Some(h), None) => h
                .split_once("..")
                .or_else(|| h.split_once('/'))
                .ok_or(HistoryParamError::Time("history"))?,
            (None, Some(s)) => (s, ""),
            (None, None) => return Ok(None),
        };
        let limit = match limit {
            None => None,
            Some(l) => Some(
                l.parse::<usize>()
                    .ok()
                    .and_then(NonZeroUsize::new)
                    .ok_or(HistoryParamError::Limit)?,
            ),
        };
        Self::from_text(from, to, agg, window, limit.map(NonZeroUsize::get)).map(Some)
    }

    /// `(from, to)` in microseconds at `now` (an open end is now); refused when `from` is
    /// after `to`, as a `since` in the future.
    pub fn range(&self, now: u64) -> Result<(u64, u64), HistoryParamError> {
        let to = self.to.map_or(now, |t| t.0);
        if self.from.0 > to {
            return Err(HistoryParamError::Backwards);
        }
        Ok((self.from.0, to))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn t(s: &str) -> TimeUs {
        TimeUs::parse(s).unwrap()
    }

    #[test]
    fn encodes_and_parses_back() {
        let q = HistoryQuery {
            from: TimeUs(t("2026-10-22T11:00:00Z").0 + 7),
            to: Some(t("2026-10-22T12:00:00Z")),
            rollup: Rollup::Avg,
            window: Window::from_secs(NonZeroU64::new(300).unwrap()),
            limit: NonZeroUsize::new(42),
        };
        assert_eq!(
            q.params(),
            "history=2026-10-22T11:00:00.000007Z..2026-10-22T12:00:00.000000Z&agg=avg&window=300s&limit=42"
        );
        assert_eq!(HistoryQuery::parse(&q.params()), Ok(Some(q.clone())));
        let open = HistoryQuery::since(t("2026-10-22"));
        assert_eq!(open.params(), "history=2026-10-22T00:00:00.000000Z..");
        assert_eq!(HistoryQuery::parse(&open.params()), Ok(Some(open)));
    }

    /// Review S2: a `from` that carries its own `&limit=` is refused before any selector is
    /// made, and a selector with a second `limit` is refused by the historian's parser.
    #[test]
    fn injected_parameters_are_refused() {
        let injected = "2026-01-01T00:00:00Z..&limit=100000&x=";
        let args = Value::Map(BTreeMap::from([("from".to_owned(), Value::from(injected))]));
        assert_eq!(
            HistoryQuery::from_args(Some(&args)),
            Err(HistoryParamError::Time("from"))
        );
        for (field, text) in [
            ("to", injected),
            ("agg", "avg&limit=100000"),
            ("window", "5m&limit=9"),
        ] {
            let args = Value::Map(BTreeMap::from([
                ("from".to_owned(), Value::from("2026-01-01")),
                (field.to_owned(), Value::from(text)),
            ]));
            assert!(HistoryQuery::from_args(Some(&args)).is_err(), "{field}");
        }
        // what the old builder sent for that `from`, with the gateway's cap behind it
        let sel = "history=2026-01-01T00:00:00Z..&limit=100000&x=..&limit=10000";
        assert_eq!(
            HistoryQuery::parse(sel),
            Err(HistoryParamError::Unknown("x".into()))
        );
        assert_eq!(
            HistoryQuery::parse("history=2026-01-01..&limit=100000&limit=10000"),
            Err(HistoryParamError::Duplicate("limit"))
        );
        assert_eq!(
            HistoryQuery::parse("history=2026-01-01..;limit=5;limit=6"),
            Err(HistoryParamError::Duplicate("limit"))
        );
        assert_eq!(
            HistoryQuery::parse("since=2026-01-01&history=2026-01-01.."),
            Err(HistoryParamError::Both)
        );
        assert_eq!(
            HistoryQuery::parse("history=2026-01-01..&history=2025-01-01.."),
            Err(HistoryParamError::Duplicate("history"))
        );
    }

    #[test]
    fn selectors() {
        assert_eq!(HistoryQuery::parse(""), Ok(None));
        assert_eq!(HistoryQuery::parse("view=full"), Ok(None));
        assert_eq!(
            HistoryQuery::parse("limit=1&limit=2"),
            Ok(None),
            "no history read"
        );
        let q = HistoryQuery::parse("history=2026-10-22T11:00:00Z..&agg=avg&window=5m&_anyke")
            .unwrap()
            .unwrap();
        assert_eq!(q.from, t("2026-10-22T11:00:00Z"));
        assert_eq!((q.to, q.rollup), (None, Rollup::Avg));
        assert_eq!(q.window.map(Window::us), Some(300 * US_PER_S));
        let q = HistoryQuery::parse("since=2026-10-22T11:59:00Z&limit=999999")
            .unwrap()
            .unwrap();
        assert_eq!(q.limit, NonZeroUsize::new(999_999));
        let now = t("2026-10-22T12:00:00Z").0;
        assert_eq!(q.range(now), Ok((now - 60 * US_PER_S, now)));
        assert_eq!(
            HistoryQuery::parse("history=2026-10-22/2026-10-23")
                .unwrap()
                .unwrap()
                .to,
            Some(t("2026-10-23"))
        );
        assert_eq!(
            HistoryQuery::since(t("2027-01-01")).range(now),
            Err(HistoryParamError::Backwards)
        );
        for bad in [
            "history=yesterday..",
            "history=..",
            "history",
            "history=2026-10-23..2026-10-22",
            "history=2026-10-22..&agg=median",
            "history=2026-10-22..&window=1M",
            "history=2026-10-22..&window=0s",
            "history=2026-10-22..&limit=0",
            "history=2026-10-22..&limit=",
            "history=2026-10-22..&limit=-1",
            "history=2026-10-22..&view=full",
        ] {
            assert!(HistoryQuery::parse(bad).is_err(), "{bad}");
        }
    }

    #[test]
    fn args() {
        let m = |kv: &[(&str, Value)]| {
            Value::Map(
                kv.iter()
                    .map(|(k, v)| ((*k).to_owned(), v.clone()))
                    .collect(),
            )
        };
        let q = HistoryQuery::from_args(Some(&m(&[
            ("from", Value::from("2026-10-22")),
            ("to", Value::from("")),
            ("agg", Value::from("count")),
            ("limit", Value::UInt(5)),
            ("other", Value::Bool(true)),
        ])))
        .unwrap();
        assert_eq!(q.rollup, Rollup::Count);
        assert_eq!((q.to, q.limit), (None, NonZeroUsize::new(5)));
        assert_eq!(
            HistoryQuery::from_args(Some(&m(&[
                ("from", Value::from("2026-10-22")),
                ("limit", Value::Float(20.0))
            ])))
            .unwrap()
            .limit,
            NonZeroUsize::new(20)
        );
        assert_eq!(
            HistoryQuery::from_args(None),
            Err(HistoryParamError::NoFrom)
        );
        assert_eq!(
            HistoryQuery::from_args(Some(&Value::UInt(1))),
            Err(HistoryParamError::Args)
        );
        for (k, v) in [
            ("from", Value::UInt(1)),
            ("limit", Value::Float(0.5)),
            ("limit", Value::Int(-3)),
            ("limit", Value::UInt(0)),
            ("limit", Value::from("10")),
        ] {
            let mut kv = vec![("from", Value::from("2026-10-22"))];
            kv.push((k, v));
            assert!(HistoryQuery::from_args(Some(&m(&kv))).is_err(), "{kv:?}");
        }
    }
}
