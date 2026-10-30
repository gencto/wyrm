//! Parser of the Prometheus text exposition format 0.0.4 and OpenMetrics
//! 1.0 text.
//!
//! One pass over the body: `# TYPE`, `# UNIT` and `# HELP` comments, other
//! comments, samples `name{label="value",…} value [timestamp]`, OpenMetrics
//! exemplars (` # {…} value [ts]` after the sample) and `# EOF`. Label
//! values take the escapes `\\`, `\"` and `\n`; values `NaN`, `+Inf`,
//! `-Inf` (and `Inf`). Timestamps are checked and then ignored (the
//! framework stamps a sample when it is published).
//!
//! A line that does not parse is skipped and counted in
//! [`Scrape::bad_lines`]: one broken line of a sloppy exporter does not
//! hide the series of every other line. More series than the bound is an
//! error ([`ParseError::TooManySeries`]).

use std::collections::HashMap;

/// The type a `# TYPE` line gives a metric family.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum MetricType {
    Counter,
    Gauge,
    Histogram,
    GaugeHistogram,
    Summary,
    Info,
    StateSet,
    Unknown,
}

impl MetricType {
    fn parse(s: &str) -> Self {
        match s {
            "counter" => Self::Counter,
            "gauge" => Self::Gauge,
            "histogram" => Self::Histogram,
            "gaugehistogram" => Self::GaugeHistogram,
            "summary" => Self::Summary,
            "info" => Self::Info,
            "stateset" => Self::StateSet,
            _ => Self::Unknown,
        }
    }

    pub fn name(self) -> &'static str {
        match self {
            Self::Counter => "counter",
            Self::Gauge => "gauge",
            Self::Histogram => "histogram",
            Self::GaugeHistogram => "gaugehistogram",
            Self::Summary => "summary",
            Self::Info => "info",
            Self::StateSet => "stateset",
            Self::Unknown => "unknown",
        }
    }
}

/// One sample of the exposition.
#[derive(Debug, Clone, PartialEq)]
pub struct Series {
    /// The exposed name (`http_requests_total`, `latency_seconds_bucket`).
    pub name: String,
    /// Label pairs sorted by name; no duplicates.
    pub labels: Vec<(String, String)>,
    pub value: f64,
}

impl Series {
    pub fn label(&self, name: &str) -> Option<&str> {
        self.labels
            .binary_search_by(|(k, _)| k.as_str().cmp(name))
            .ok()
            .map(|i| self.labels[i].1.as_str())
    }

    /// The label set without `skip` as one comparable key.
    pub fn key_without(&self, skip: &str) -> String {
        let mut k = String::new();
        for (n, v) in &self.labels {
            if n != skip {
                k.push_str(n);
                k.push('\u{0}');
                k.push_str(v);
                k.push('\u{0}');
            }
        }
        k
    }
}

/// A parsed exposition.
#[derive(Debug, Clone, Default)]
pub struct Scrape {
    pub series: Vec<Series>,
    /// Indexes into `series` by exposed name.
    pub by_name: HashMap<String, Vec<usize>>,
    /// `# TYPE` per family name.
    pub types: HashMap<String, MetricType>,
    /// `# UNIT` per family name (OpenMetrics).
    pub units: HashMap<String, String>,
    /// Lines skipped because they did not parse.
    pub bad_lines: usize,
    /// The first skipped line's number and reason (for the logs and
    /// `list_series`; never its content, which may carry values).
    pub first_bad: Option<(usize, &'static str)>,
}

impl Scrape {
    pub fn named(&self, name: &str) -> impl Iterator<Item = &Series> {
        self.by_name
            .get(name)
            .into_iter()
            .flatten()
            .map(|i| &self.series[*i])
    }

    /// The family type of an exposed series name (`foo_total` → `foo`,
    /// `foo_bucket` → `foo`, …).
    pub fn type_of(&self, name: &str) -> MetricType {
        if let Some(t) = self.types.get(name) {
            return *t;
        }
        for suffix in [
            "_total", "_created", "_bucket", "_sum", "_count", "_gcount", "_gsum", "_info",
        ] {
            if let Some(base) = name.strip_suffix(suffix) {
                if let Some(t) = self.types.get(base) {
                    return *t;
                }
            }
        }
        MetricType::Unknown
    }
}

#[derive(Debug, Clone, PartialEq)]
pub enum ParseError {
    /// More samples than `max_series`.
    TooManySeries(usize),
    /// The parsed exposition needs more than this many bytes.
    TooLarge(usize),
}

impl std::fmt::Display for ParseError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            ParseError::TooManySeries(max) => {
                write!(f, "the exposition has more than {max} series (max_series)")
            }
            ParseError::TooLarge(max) => write!(
                f,
                "the parsed exposition needs more than {} MiB of memory \
                 ({MEMORY_FACTOR} × max_body_mib)",
                max >> 20
            ),
        }
    }
}

/// A line longer than this is skipped before it is parsed.
pub const MAX_LINE: usize = 1 << 20;
/// Labels of one sample (as Prometheus `label_limit`).
pub const MAX_LABELS: usize = 128;
/// Length of a metric or label name.
pub const MAX_NAME: usize = 1024;
/// Length of a label value (after unescaping).
pub const MAX_LABEL_VALUE: usize = 16 * 1024;
/// The memory budget of one parse, per byte of `max_body`: a realistic
/// exposition takes 3 to 6 times its size, a hostile one of short labels
/// 10 to 20 times; [`parse`] stops at this factor.
pub const MEMORY_FACTOR: usize = 16;

/// Estimated heap of one label pair, one sample and one map entry.
const PAIR: usize = std::mem::size_of::<(String, String)>();
const SAMPLE: usize = std::mem::size_of::<Series>() + std::mem::size_of::<usize>();
const ENTRY: usize = 48;

fn cost(x: &Series) -> usize {
    SAMPLE
        + x.name.len()
        + x.labels
            .iter()
            .map(|(k, v)| PAIR + k.len() + v.len())
            .sum::<usize>()
}

/// Parse `body` (UTF-8 text). `max_series` bounds the samples kept and the
/// `# TYPE` / `# UNIT` entries; `max_bytes` the estimated memory of the
/// result. Every line is bounded too ([`MAX_LINE`], [`MAX_LABELS`],
/// [`MAX_NAME`], [`MAX_LABEL_VALUE`]): a line over a bound is skipped and
/// counted, before it allocates more than the bound.
pub fn parse(body: &str, max_series: usize, max_bytes: usize) -> Result<Scrape, ParseError> {
    let mut s = Scrape::default();
    let mut used = 0usize;
    for (n, line) in body.split('\n').enumerate() {
        let line = line.strip_suffix('\r').unwrap_or(line);
        let r = if line.len() > MAX_LINE {
            Err(Bad("line too long"))
        } else if let Some(c) = line.strip_prefix('#') {
            comment(&mut s, c, max_series, &mut used)
        } else if line.trim().is_empty() {
            Ok(())
        } else {
            match sample(line) {
                Ok(x) => {
                    if s.series.len() >= max_series {
                        return Err(ParseError::TooManySeries(max_series));
                    }
                    used = used.saturating_add(cost(&x));
                    let entry = s.by_name.entry(x.name.clone()).or_insert_with(|| {
                        used = used.saturating_add(ENTRY + x.name.len());
                        Vec::new()
                    });
                    entry.push(s.series.len());
                    s.series.push(x);
                    Ok(())
                }
                Err(e) => Err(e),
            }
        };
        if used > max_bytes {
            return Err(ParseError::TooLarge(max_bytes));
        }
        match r {
            Ok(()) => {}
            Err(e) if e == EOF => break,
            Err(e) => {
                s.bad_lines += 1;
                if s.first_bad.is_none() {
                    s.first_bad = Some((n + 1, e.0));
                }
            }
        }
    }
    Ok(s)
}

/// Why a line was skipped (static text, never the line).
#[derive(Debug, Clone, Copy, PartialEq)]
pub(crate) struct Bad(pub(crate) &'static str);

/// `# EOF`: the end of an OpenMetrics exposition.
const EOF: Bad = Bad("eof");

fn comment(s: &mut Scrape, c: &str, max: usize, used: &mut usize) -> Result<(), Bad> {
    let c = c.strip_prefix(' ').unwrap_or(c);
    if c.trim_end() == "EOF" {
        return Err(EOF);
    }
    let mut it = c.splitn(3, ' ');
    let (kw, name, rest) = (it.next(), it.next(), it.next());
    let rest = rest.unwrap_or("").trim();
    match (kw, name) {
        (Some("TYPE"), Some(name)) => {
            check_metric_name(name)?;
            if !s.types.contains_key(name) {
                if s.types.len() >= max {
                    return Err(Bad("more # TYPE lines than max_series"));
                }
                *used = used.saturating_add(ENTRY + name.len());
            }
            s.types.insert(name.to_owned(), MetricType::parse(rest));
            Ok(())
        }
        (Some("UNIT"), Some(name)) => {
            check_metric_name(name)?;
            if !s.units.contains_key(name) {
                if s.units.len() >= max {
                    return Err(Bad("more # UNIT lines than max_series"));
                }
                *used = used.saturating_add(ENTRY + name.len() + rest.len());
            }
            s.units.insert(name.to_owned(), rest.to_owned());
            Ok(())
        }
        // HELP and free comments are not needed.
        _ => Ok(()),
    }
}

fn check_metric_name(name: &str) -> Result<(), Bad> {
    if name.len() > MAX_NAME {
        Err(Bad("metric name too long"))
    } else if !is_metric_name(name) {
        Err(Bad("bad metric name"))
    } else {
        Ok(())
    }
}

pub fn is_metric_name(n: &str) -> bool {
    let mut b = n.bytes();
    matches!(b.next(), Some(c) if c.is_ascii_alphabetic() || c == b'_' || c == b':')
        && b.all(|c| c.is_ascii_alphanumeric() || c == b'_' || c == b':')
}

pub fn is_label_name(n: &str) -> bool {
    let mut b = n.bytes();
    matches!(b.next(), Some(c) if c.is_ascii_alphabetic() || c == b'_')
        && b.all(|c| c.is_ascii_alphanumeric() || c == b'_')
}

/// A sample value: a float, `NaN`, `+Inf`, `-Inf`, `Inf`.
pub fn parse_value(s: &str) -> Option<f64> {
    match s {
        "NaN" | "nan" => Some(f64::NAN),
        "+Inf" | "Inf" | "+inf" | "inf" => Some(f64::INFINITY),
        "-Inf" | "-inf" => Some(f64::NEG_INFINITY),
        _ => {
            // Rust also takes "infinity" and "nan" in any case; the formats
            // do not: only digits, signs, dots and exponents here.
            if s.is_empty()
                || !s
                    .bytes()
                    .all(|c| c.is_ascii_digit() || matches!(c, b'+' | b'-' | b'.' | b'e' | b'E'))
            {
                return None;
            }
            s.parse().ok()
        }
    }
}

fn sample(line: &str) -> Result<Series, Bad> {
    let line = line.trim_start();
    let name_end = line.find(['{', ' ', '\t']).unwrap_or(line.len());
    let name = &line[..name_end];
    check_metric_name(name)?;
    let mut rest = &line[name_end..];
    let mut labels = Vec::new();
    if let Some(r) = rest.strip_prefix('{') {
        let (l, after) = label_set(r)?;
        labels = l;
        rest = after;
    }
    // Value, optional timestamp, optional OpenMetrics exemplar.
    let rest = match rest.find(" # ") {
        Some(i) => &rest[..i],
        None => rest,
    };
    let mut parts = rest.split_ascii_whitespace();
    let value = parts
        .next()
        .and_then(parse_value)
        .ok_or(Bad("bad sample value"))?;
    if let Some(ts) = parts.next() {
        // Prometheus: integer milliseconds; OpenMetrics: float seconds.
        if ts.parse::<f64>().map_or(true, |t| !t.is_finite()) {
            return Err(Bad("bad timestamp"));
        }
    }
    if parts.next().is_some() {
        return Err(Bad("text after the timestamp"));
    }
    labels.sort_by(|a: &(String, String), b| a.0.cmp(&b.0));
    if labels.windows(2).any(|w| w[0].0 == w[1].0) {
        return Err(Bad("duplicate label"));
    }
    Ok(Series {
        name: name.to_owned(),
        labels,
        value,
    })
}

/// Label pairs of one sample.
type Labels = Vec<(String, String)>;

/// `name="value",…}` (after the `{`) → labels and the text after `}`.
fn label_set(mut r: &str) -> Result<(Labels, &str), Bad> {
    let mut labels = Vec::new();
    loop {
        r = r.trim_start();
        if let Some(after) = r.strip_prefix('}') {
            return Ok((labels, after));
        }
        let eq = r.find('=').ok_or(Bad("label without ="))?;
        let lname = r[..eq].trim();
        if lname.len() > MAX_NAME {
            return Err(Bad("label name too long"));
        }
        if !is_label_name(lname) {
            return Err(Bad("bad label name"));
        }
        if labels.len() >= MAX_LABELS {
            return Err(Bad("too many labels"));
        }
        let (value, after) = quoted(r[eq + 1..].trim_start())?;
        labels.push((lname.to_owned(), value));
        r = after.trim_start();
        if let Some(a) = r.strip_prefix(',') {
            r = a;
        } else if !r.starts_with('}') {
            return Err(Bad("expected , or } after a label"));
        }
    }
}

/// A `"…"` string with the escapes `\\`, `\"`, `\n` → the value and the
/// text after the closing quote.
pub(crate) fn quoted(r: &str) -> Result<(String, &str), Bad> {
    let body = r.strip_prefix('"').ok_or(Bad("label value not quoted"))?;
    let mut out = String::new();
    let mut chars = body.char_indices();
    while let Some((i, c)) = chars.next() {
        if out.len() > MAX_LABEL_VALUE {
            return Err(Bad("label value too long"));
        }
        match c {
            '"' => return Ok((out, &body[i + 1..])),
            '\\' => match chars.next() {
                Some((_, '\\')) => out.push('\\'),
                Some((_, '"')) => out.push('"'),
                Some((_, 'n')) => out.push('\n'),
                Some((_, other)) => {
                    // 0.0.4 keeps unknown escapes as they are.
                    out.push('\\');
                    out.push(other);
                }
                None => return Err(Bad("unterminated label value")),
            },
            c => out.push(c),
        }
    }
    Err(Bad("unterminated label value"))
}

#[cfg(test)]
mod tests {
    use super::*;

    const BODY: &str = r#"# HELP http_requests_total Requests.
# TYPE http_requests_total counter
http_requests_total{method="get",code="200"} 1027 1395066363000
http_requests_total{method="post",code="200"} 3 1395066363000
# a free comment
msdos_file_access_time_seconds{path="C:\\DIR\\FILE.TXT",error="Cannot find file:\n\"FILE.TXT\""} 1.458255915e9
metric_without_timestamp_and_labels 12.47
something_weird{problem="division by zero"} +Inf -3982045
nan_metric NaN
neg_inf -Inf
# TYPE latency_seconds histogram
latency_seconds_bucket{le="0.05"} 24054
latency_seconds_bucket{le="+Inf"} 144320
latency_seconds_sum 53423
latency_seconds_count 144320
"#;

    #[test]
    fn text_format_0_0_4() {
        let s = parse(BODY, 100, usize::MAX).unwrap();
        assert_eq!(s.bad_lines, 0, "{:?}", s.first_bad);
        assert_eq!(s.series.len(), 11);
        let r: Vec<_> = s.named("http_requests_total").collect();
        assert_eq!(r.len(), 2);
        assert_eq!(r[0].label("method"), Some("get"));
        assert_eq!(r[0].label("code"), Some("200"));
        assert_eq!(r[0].value, 1027.0);
        let f = s.named("msdos_file_access_time_seconds").next().unwrap();
        assert_eq!(f.label("path"), Some(r"C:\DIR\FILE.TXT"));
        assert_eq!(f.label("error"), Some("Cannot find file:\n\"FILE.TXT\""));
        assert_eq!(
            s.named("something_weird").next().unwrap().value,
            f64::INFINITY
        );
        assert!(s.named("nan_metric").next().unwrap().value.is_nan());
        assert_eq!(s.named("neg_inf").next().unwrap().value, f64::NEG_INFINITY);
        assert_eq!(s.type_of("http_requests_total"), MetricType::Counter);
        assert_eq!(s.type_of("latency_seconds_bucket"), MetricType::Histogram);
        assert_eq!(s.type_of("latency_seconds_sum"), MetricType::Histogram);
        assert_eq!(s.type_of("nan_metric"), MetricType::Unknown);
    }

    #[test]
    fn openmetrics_1_0() {
        let body = "# TYPE foo counter\n# UNIT foo seconds\n# HELP foo Foo.\n\
                    foo_total{a=\"1\"} 17.0 1520879607.789 # {trace_id=\"KOO5S4vxi0o\"} 0.67\n\
                    foo_created{a=\"1\"} 1520872607.123\n\
                    # EOF\n\
                    after_eof 1\n";
        let s = parse(body, 100, usize::MAX).unwrap();
        assert_eq!(s.bad_lines, 0, "{:?}", s.first_bad);
        assert_eq!(s.series.len(), 2, "nothing after # EOF");
        assert_eq!(s.named("foo_total").next().unwrap().value, 17.0);
        assert_eq!(s.type_of("foo_total"), MetricType::Counter);
        assert_eq!(s.units.get("foo").map(String::as_str), Some("seconds"));
    }

    #[test]
    fn malformed_lines_are_skipped_and_counted() {
        let body = "good 1\n9bad 1\nno_value\nbad_value abc\nbad{l=\"x} 1\n\
                    bad{l=\"x\",l=\"y\"} 1\nbad{1l=\"x\"} 1\nbad 1 2 3\nbad 1 ts\n\
                    also_good{a=\"b\",} 2\r\n";
        let s = parse(body, 100, usize::MAX).unwrap();
        assert_eq!(s.series.len(), 2);
        assert_eq!(s.bad_lines, 8);
        assert_eq!(s.first_bad.map(|b| b.0), Some(2));
        assert_eq!(s.named("also_good").next().unwrap().label("a"), Some("b"));
        assert_eq!(parse_value("infinity"), None);
        assert_eq!(parse_value("0x10"), None);
        assert_eq!(parse_value("-1.5e3"), Some(-1500.0));
    }

    #[test]
    fn series_bound() {
        let body = "a 1\nb 2\nc 3\n";
        assert!(parse(body, 3, usize::MAX).is_ok());
        assert_eq!(
            parse(body, 2, usize::MAX).unwrap_err(),
            ParseError::TooManySeries(2)
        );
    }

    /// `x{a0="",a1="",…}` with `n` labels.
    fn wide(n: usize) -> String {
        let labels: Vec<String> = (0..n).map(|i| format!("a{i}=\"\"")).collect();
        format!("x{{{}}} 1\n", labels.join(","))
    }

    #[test]
    fn per_line_caps() {
        // labels per sample
        let s = parse(&wide(MAX_LABELS), 10, usize::MAX).unwrap();
        assert_eq!((s.series.len(), s.bad_lines), (1, 0));
        let s = parse(&wide(MAX_LABELS + 1), 10, usize::MAX).unwrap();
        assert_eq!((s.series.len(), s.bad_lines), (0, 1));
        assert_eq!(s.first_bad, Some((1, "too many labels")));
        // label name and value length
        let long_name = format!("x{{{}=\"v\"}} 1\n", "n".repeat(MAX_NAME + 1));
        let s = parse(&long_name, 10, usize::MAX).unwrap();
        assert_eq!(s.first_bad, Some((1, "label name too long")));
        let long_value = format!("x{{l=\"{}\"}} 1\n", "v".repeat(MAX_LABEL_VALUE + 1));
        let s = parse(&long_value, 10, usize::MAX).unwrap();
        assert_eq!(s.first_bad, Some((1, "label value too long")));
        let ok_value = format!("x{{l=\"{}\"}} 1\n", "v".repeat(MAX_LABEL_VALUE));
        assert_eq!(parse(&ok_value, 10, usize::MAX).unwrap().bad_lines, 0);
        // metric name length
        let long_metric = format!("{} 1\n", "m".repeat(MAX_NAME + 1));
        let s = parse(&long_metric, 10, usize::MAX).unwrap();
        assert_eq!(s.first_bad, Some((1, "metric name too long")));
        // line length: refused before it is parsed
        let long_line = format!(
            "# HELP x {}\nx{{l=\"{}\"}} 1\ny 2\n",
            "h".repeat(MAX_LINE),
            "v".repeat(MAX_LINE)
        );
        let s = parse(&long_line, 10, usize::MAX).unwrap();
        assert_eq!((s.series.len(), s.bad_lines), (1, 2));
        assert_eq!(s.first_bad, Some((1, "line too long")));
    }

    #[test]
    fn type_and_unit_entries_are_bounded() {
        let mut body = String::new();
        for i in 0..50 {
            body.push_str(&format!("# TYPE m{i} gauge\n# UNIT m{i} seconds\n"));
        }
        let s = parse(&body, 10, usize::MAX).unwrap();
        assert_eq!(s.types.len(), 10);
        assert_eq!(s.units.len(), 10);
        assert_eq!(s.bad_lines, 80);
    }

    /// Many lines under the per-line caps still add up: the whole parse
    /// has a memory budget.
    #[test]
    fn memory_budget_of_one_scrape() {
        let line = wide(MAX_LABELS);
        let body: String = (0..2_000)
            .map(|i| line.replacen("x{", &format!("x{i}{{"), 1))
            .collect();
        // ~1.2 MB on the wire, ~256 000 label pairs
        let budget = 16 * body.len();
        assert!(matches!(
            parse(&body, 1_000_000, 4 * body.len()),
            Err(ParseError::TooLarge(_))
        ));
        let s = parse(&body, 1_000_000, budget).unwrap();
        assert_eq!(s.series.len(), 2_000);
        // a realistic exposition fits in the budget of its size
        let real = BODY.repeat(200);
        assert!(parse(&real, 1_000_000, 4 * real.len()).is_ok());
    }
}
