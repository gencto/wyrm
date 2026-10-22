//! History queries: raw rows, or one value per interval (DSA `Get History`
//! Interval and Rollup; spec 01 `agg` and `window`).

use crate::store::Row;
use wyrm_core::{Quality, Value};

/// How the samples of one interval become one value (names as DSA and
/// spec 01 `agg`).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
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

    pub fn parse(s: &str) -> Option<Self> {
        let s = s.trim();
        if s.is_empty() {
            return Some(Rollup::None);
        }
        Self::ALL.into_iter().find(|r| r.name() == s)
    }
}

fn number(v: &Value) -> Option<f64> {
    match v {
        Value::Bool(b) => Some(f64::from(u8::from(*b))),
        v => v.as_f64(),
    }
}

fn truthy(v: &Value) -> Option<bool> {
    match v {
        Value::Bool(b) => Some(*b),
        v => v.as_f64().map(|f| f != 0.0),
    }
}

/// The samples of one interval, folded as they arrive.
#[derive(Default)]
struct Acc {
    first: Option<Value>,
    last: Option<Value>,
    first_n: Option<f64>,
    last_n: Option<f64>,
    min: Option<f64>,
    max: Option<f64>,
    sum: f64,
    nums: u64,
    count: u64,
    and: Option<bool>,
    or: Option<bool>,
}

impl Acc {
    fn add(&mut self, v: &Value) {
        self.count += 1;
        if self.first.is_none() {
            self.first = Some(v.clone());
        }
        self.last = Some(v.clone());
        if let Some(n) = number(v) {
            if self.first_n.is_none() {
                self.first_n = Some(n);
            }
            self.last_n = Some(n);
            self.min = Some(self.min.map_or(n, |m| m.min(n)));
            self.max = Some(self.max.map_or(n, |m| m.max(n)));
            self.sum += n;
            self.nums += 1;
        }
        if let Some(b) = truthy(v) {
            self.and = Some(self.and.unwrap_or(true) && b);
            self.or = Some(self.or.unwrap_or(false) || b);
        }
    }

    fn value(self, r: Rollup) -> Option<Value> {
        let f = |x: Option<f64>| x.map(Value::Float);
        match r {
            Rollup::None | Rollup::First => self.first,
            Rollup::Last => self.last,
            Rollup::Count => Some(Value::UInt(self.count)),
            Rollup::Sum => (self.nums > 0).then_some(Value::Float(self.sum)),
            Rollup::Avg => (self.nums > 0).then(|| Value::Float(self.sum / self.nums as f64)),
            Rollup::Min => f(self.min),
            Rollup::Max => f(self.max),
            Rollup::Delta => f(self.last_n.zip(self.first_n).map(|(l, f)| l - f)),
            Rollup::And => self.and.map(Value::Bool),
            Rollup::Or => self.or.map(Value::Bool),
        }
    }
}

/// One output row: `(t, v, q)`; rolled-up rows carry the interval start
/// and `good`.
pub type Out = (u64, Value, Quality);

/// Fold rows (oldest first) into the answer of a query from `from`:
/// - no interval, no rollup: the rows themselves (bad ones too);
/// - an interval: one row per interval `[from + k·i, from + (k+1)·i)` that
///   has samples, by `rollup` (`none` = the first sample, as DSA);
/// - a rollup without an interval: one row for the whole range.
///
/// Rollups skip `bad` samples. At most `limit` rows.
pub struct Folder {
    from: u64,
    interval: Option<u64>,
    rollup: Rollup,
    limit: usize,
    window: Option<(u64, Acc)>,
    pub out: Vec<Out>,
}

impl Folder {
    pub fn new(from: u64, interval: Option<u64>, rollup: Rollup, limit: usize) -> Self {
        Self {
            from,
            interval,
            rollup,
            limit,
            window: None,
            out: Vec::new(),
        }
    }

    fn raw(&self) -> bool {
        self.interval.is_none() && self.rollup == Rollup::None
    }

    /// Add one row; `false` when the answer is full.
    pub fn push(&mut self, r: Row) -> bool {
        if self.raw() {
            self.out.push((r.t, r.v, r.q));
            return self.out.len() < self.limit;
        }
        if r.q == Quality::Bad {
            return true;
        }
        let start = match self.interval {
            Some(i) => self.from + (r.t.saturating_sub(self.from) / i) * i,
            None => self.from,
        };
        if self.window.as_ref().is_some_and(|(s, _)| *s != start) {
            self.close();
            if self.out.len() >= self.limit {
                return false;
            }
        }
        self.window
            .get_or_insert_with(|| (start, Acc::default()))
            .1
            .add(&r.v);
        true
    }

    fn close(&mut self) {
        if let Some((start, acc)) = self.window.take() {
            if let Some(v) = acc.value(self.rollup) {
                self.out.push((start, v, Quality::Good));
            }
        }
    }

    pub fn finish(mut self) -> Vec<Out> {
        if self.out.len() < self.limit {
            self.close();
        }
        self.out.truncate(self.limit);
        self.out
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn rows(vals: &[(u64, f64, Quality)]) -> Vec<Row> {
        vals.iter()
            .map(|(t, v, q)| Row {
                t: *t,
                v: Value::Float(*v),
                q: *q,
            })
            .collect()
    }

    fn fold(rs: &[Row], from: u64, i: Option<u64>, r: Rollup) -> Vec<(u64, Value)> {
        let mut f = Folder::new(from, i, r, 100);
        for row in rs {
            if !f.push(row.clone()) {
                break;
            }
        }
        f.finish().into_iter().map(|(t, v, _)| (t, v)).collect()
    }

    #[test]
    fn rollups_per_interval() {
        use Quality::*;
        let rs = rows(&[
            (10, 1.0, Good),
            (15, 3.0, Good),
            (18, 100.0, Bad),
            (25, 5.0, Uncertain),
            (47, 2.0, Good),
        ]);
        assert_eq!(
            fold(&rs, 10, None, Rollup::None).len(),
            5,
            "raw keeps bad rows"
        );
        let f = |t, v| (t, Value::Float(v));
        assert_eq!(
            fold(&rs, 10, Some(10), Rollup::Avg),
            [f(10, 2.0), f(20, 5.0), f(40, 2.0)]
        );
        assert_eq!(fold(&rs, 10, Some(10), Rollup::Max)[0], f(10, 3.0));
        assert_eq!(fold(&rs, 10, Some(10), Rollup::None)[0], f(10, 1.0));
        assert_eq!(fold(&rs, 10, Some(10), Rollup::Delta)[0], f(10, 2.0));
        assert_eq!(
            fold(&rs, 10, None, Rollup::Count),
            [(10, Value::UInt(4))],
            "bad skipped"
        );
        assert_eq!(fold(&rs, 10, None, Rollup::Sum), [f(10, 11.0)]);
        assert_eq!(fold(&rs, 10, None, Rollup::Last), [f(10, 2.0)]);
        assert_eq!(fold(&rs, 10, None, Rollup::And), [(10, Value::Bool(true))]);
        let mut capped = Folder::new(10, Some(10), Rollup::Avg, 2);
        for r in &rs {
            if !capped.push(r.clone()) {
                break;
            }
        }
        assert_eq!(capped.finish().len(), 2);
        assert_eq!(Rollup::parse("avg"), Some(Rollup::Avg));
        assert_eq!(Rollup::parse(""), Some(Rollup::None));
        assert_eq!(Rollup::parse("median"), None);
    }
}
