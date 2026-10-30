//! Pure evaluation of a point over its matching series: aggregates, the
//! reset-aware counter increase, and `histogram_quantile` as PromQL
//! computes it (linear interpolation inside the bucket of the rank).

use wyrm_link_sdk::ParamEnum;

/// How the values of several matching series become one.
#[derive(Debug, Clone, Copy, PartialEq, Eq, ParamEnum)]
pub enum Aggregate {
    /// Exactly one series must match.
    None,
    Sum,
    Max,
    Min,
    Avg,
    /// The number of matching series (0 when none match).
    Count,
}

/// The raw value or the per-second increase between two scrapes.
#[derive(Debug, Clone, Copy, PartialEq, Eq, ParamEnum)]
pub enum Mode {
    Raw,
    #[param(name = "rate_per_s")]
    RatePerS,
}

/// What a point computes from its series.
#[derive(Debug, Clone, Copy, PartialEq, Eq, ParamEnum)]
pub enum Function {
    /// The (aggregated) series value.
    Value,
    /// The `q` quantile from the `_bucket` series of a histogram.
    HistogramQuantile,
}

/// Aggregate `values` (one per matching series).
pub fn aggregate(a: Aggregate, values: &[f64]) -> Result<f64, String> {
    if a == Aggregate::Count {
        return Ok(values.len() as f64);
    }
    if values.is_empty() {
        return Err("no series matches the selector".into());
    }
    Ok(match a {
        Aggregate::None => {
            if values.len() > 1 {
                return Err(format!(
                    "{} series match the selector; narrow it or set aggregate",
                    values.len()
                ));
            }
            values[0]
        }
        Aggregate::Sum => values.iter().sum(),
        Aggregate::Max => values.iter().copied().fold(f64::NEG_INFINITY, f64::max),
        Aggregate::Min => values.iter().copied().fold(f64::INFINITY, f64::min),
        Aggregate::Avg => values.iter().sum::<f64>() / values.len() as f64,
        Aggregate::Count => unreachable!("handled above"),
    })
}

/// A counter's increase from `prev` to `cur`: after a reset (`cur < prev`)
/// the counter started again from 0, so the increase is `cur`.
pub fn increase(prev: f64, cur: f64) -> f64 {
    if cur >= prev {
        cur - prev
    } else {
        cur
    }
}

/// The `q` quantile (0…1) of a histogram given as `(le, cumulative count)`
/// buckets, as PromQL `histogram_quantile`: buckets sorted by `le`, equal
/// bounds merged, counts made monotonic, a `+Inf` bucket required.
pub fn histogram_quantile(q: f64, buckets: &[(f64, f64)]) -> Result<f64, String> {
    let mut b: Vec<(f64, f64)> = buckets
        .iter()
        .copied()
        .filter(|(le, c)| !le.is_nan() && !c.is_nan())
        .collect();
    b.sort_by(|x, y| x.0.total_cmp(&y.0));
    let mut merged: Vec<(f64, f64)> = Vec::with_capacity(b.len());
    for (le, c) in b {
        match merged.last_mut() {
            Some(last) if last.0 == le => last.1 += c,
            _ => merged.push((le, c)),
        }
    }
    let b = merged;
    if b.last().map(|x| x.0) != Some(f64::INFINITY) {
        return Err("the histogram has no le=\"+Inf\" bucket".into());
    }
    if b.len() < 2 {
        return Err("the histogram needs at least two buckets".into());
    }
    let mut counts: Vec<f64> = b.iter().map(|x| x.1).collect();
    for i in 1..counts.len() {
        if counts[i] < counts[i - 1] {
            counts[i] = counts[i - 1];
        }
    }
    let n = counts.len();
    let total = counts[n - 1];
    if total <= 0.0 {
        return Err("the histogram has no observations".into());
    }
    let rank = q.clamp(0.0, 1.0) * total;
    let i = counts.iter().position(|c| *c >= rank).unwrap_or(n - 1);
    if i == n - 1 {
        // In the +Inf bucket: the highest finite bound.
        return Ok(b[n - 2].0);
    }
    if i == 0 && b[0].0 <= 0.0 {
        return Ok(b[0].0);
    }
    let (start, count_start) = if i == 0 {
        (0.0, 0.0)
    } else {
        (b[i - 1].0, counts[i - 1])
    };
    let end = b[i].0;
    let in_bucket = counts[i] - count_start;
    if in_bucket <= 0.0 {
        return Ok(start);
    }
    Ok(start + (end - start) * ((rank - count_start) / in_bucket))
}

#[cfg(test)]
mod tests {
    use super::*;
    use wyrm_link_sdk::driver::ParamEnum as _;

    #[test]
    fn aggregates() {
        let v = [1.0, 4.0, 2.5];
        assert_eq!(aggregate(Aggregate::Sum, &v), Ok(7.5));
        assert_eq!(aggregate(Aggregate::Max, &v), Ok(4.0));
        assert_eq!(aggregate(Aggregate::Min, &v), Ok(1.0));
        assert_eq!(aggregate(Aggregate::Avg, &v), Ok(2.5));
        assert_eq!(aggregate(Aggregate::Count, &v), Ok(3.0));
        assert_eq!(aggregate(Aggregate::Count, &[]), Ok(0.0));
        assert!(aggregate(Aggregate::None, &v)
            .unwrap_err()
            .contains("3 series"));
        assert_eq!(aggregate(Aggregate::None, &[9.0]), Ok(9.0));
        for a in [
            Aggregate::None,
            Aggregate::Sum,
            Aggregate::Max,
            Aggregate::Min,
            Aggregate::Avg,
        ] {
            assert!(aggregate(a, &[]).is_err(), "{a:?}");
        }
        assert_eq!(Mode::NAMES, ["raw", "rate_per_s"]);
        assert_eq!(Function::NAMES, ["value", "histogram_quantile"]);
        assert_eq!(Aggregate::NAMES[0], "none");
    }

    #[test]
    fn counter_resets() {
        assert_eq!(increase(10.0, 15.0), 5.0);
        assert_eq!(increase(10.0, 10.0), 0.0);
        assert_eq!(increase(100.0, 7.0), 7.0, "reset: counted from 0");
    }

    #[test]
    fn quantiles() {
        // 10 in (0, 0.1], 10 in (0.1, 0.5], 0 in (0.5, 1], none above
        let b = [(0.1, 10.0), (0.5, 20.0), (1.0, 20.0), (f64::INFINITY, 20.0)];
        let q = |x| histogram_quantile(x, &b).unwrap();
        assert!((q(0.25) - 0.05).abs() < 1e-12);
        assert!((q(0.5) - 0.1).abs() < 1e-12);
        assert!((q(0.75) - 0.3).abs() < 1e-12);
        assert!((q(1.0) - 0.5).abs() < 1e-12);
        // the rank in +Inf: the highest finite bound
        let b = [(0.1, 1.0), (f64::INFINITY, 10.0)];
        assert_eq!(histogram_quantile(0.9, &b), Ok(0.1));
        // unsorted, split over two series (merged), non-monotonic counts
        let b = [
            (f64::INFINITY, 4.0),
            (0.5, 2.0),
            (f64::INFINITY, 4.0),
            (0.5, 2.0),
            (1.0, 3.0),
            (1.0, 3.0),
        ];
        assert!((histogram_quantile(0.5, &b).unwrap() - 0.5).abs() < 1e-12);
        assert!(histogram_quantile(0.5, &[(1.0, 2.0)]).is_err(), "no +Inf");
        assert!(histogram_quantile(0.5, &[(f64::INFINITY, 2.0)]).is_err());
        assert!(histogram_quantile(0.5, &[(1.0, 0.0), (f64::INFINITY, 0.0)])
            .unwrap_err()
            .contains("no observations"));
        // a first bound <= 0
        let b = [(-1.0, 5.0), (0.0, 6.0), (f64::INFINITY, 10.0)];
        assert_eq!(histogram_quantile(0.1, &b), Ok(-1.0));
    }
}
