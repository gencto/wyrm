//! Key patterns of `list` and `sublist`: Zenoh key-expression wildcards over full keys
//! (`wy/<site>/…`). `*` is one segment, `**` any number of segments (at least one at the end).
//! A pattern without a wildcard lists the children of that node (DSA `list /x`).

use wyrm_core::keyspace;

/// One segment of a pattern.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Seg {
    Lit(String),
    /// `*`: one segment.
    Star,
    /// `**`: zero or more segments (rows are always strictly below the pattern's top).
    DStar,
}

/// A pattern anchored at its top: the longest fixed prefix, the node whose children are listed
/// first. Rows match `segs` relative to `top`.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Pattern {
    pub top: String,
    pub segs: Vec<Seg>,
}

fn seg_of(s: &str) -> Result<Seg, String> {
    match s {
        "*" => Ok(Seg::Star),
        "**" => Ok(Seg::DStar),
        _ => {
            keyspace::validate_segment(s).map_err(|e| format!("{s:?}: {e:?}"))?;
            Ok(Seg::Lit(s.to_owned()))
        }
    }
}

/// A full node key: `wy/<site>/<section>…`, plain segments.
pub fn check_key(key: &str) -> Result<(), String> {
    let parts: Vec<&str> = key.split('/').collect();
    if parts.len() < 3 || parts[0] != keyspace::ROOT {
        return Err(format!(
            "{key}: a full key wy/<site>/… (at least a section)"
        ));
    }
    for p in &parts {
        keyspace::validate_segment(p).map_err(|e| format!("{key}: {p:?} {e:?}"))?;
    }
    Ok(())
}

impl Pattern {
    /// A full pattern: `wy/<site>/<section>[/…]` with `*`/`**` after the site and section.
    pub fn parse(text: &str) -> Result<Self, String> {
        let text = text.trim().trim_end_matches('/');
        let parts: Vec<&str> = text.split('/').collect();
        if parts.len() < 3 || parts[0] != keyspace::ROOT {
            return Err(format!(
                "{text:?}: a full key pattern wy/<site>/<section>/… (wildcards * and **)"
            ));
        }
        let segs = parts
            .iter()
            .map(|p| seg_of(p))
            .collect::<Result<Vec<_>, _>>()
            .map_err(|e| format!("{text:?}: {e}"))?;
        if segs[..3].iter().any(|s| !matches!(s, Seg::Lit(_))) {
            return Err(format!(
                "{text:?}: the site and the section are fixed (no wildcard before wy/<site>/<section>)"
            ));
        }
        Ok(Self::anchored(segs))
    }

    /// A pattern relative to a row (`sublist`): `./*`, `**`, `a/*`, `a/b`.
    pub fn relative(text: &str) -> Result<Vec<Seg>, String> {
        let text = text.trim().trim_start_matches("./").trim_end_matches('/');
        if text.is_empty() || text == "." {
            return Err("a relative pattern below the row (./*, ./**, a/*)".into());
        }
        text.split('/')
            .map(|p| {
                if p == ".." || p == "." {
                    Err(format!("{text:?}: a sublist stays below the row"))
                } else {
                    seg_of(p)
                }
            })
            .collect()
    }

    /// `segs` (a relative pattern) below `base`.
    pub fn below(base: &str, segs: &[Seg]) -> Self {
        let mut all: Vec<Seg> = base.split('/').map(|s| Seg::Lit(s.to_owned())).collect();
        all.extend(segs.iter().cloned());
        Self::anchored(all)
    }

    fn anchored(all: Vec<Seg>) -> Self {
        let fixed = all.iter().take_while(|s| matches!(s, Seg::Lit(_))).count();
        let (top, mut segs) = if fixed == all.len() {
            // no wildcard: the node's children
            (all, vec![Seg::Star])
        } else {
            let rest = all[fixed..].to_vec();
            (all[..fixed].to_vec(), rest)
        };
        let top = top
            .iter()
            .map(|s| match s {
                Seg::Lit(l) => l.as_str(),
                _ => unreachable!("top is literal"),
            })
            .collect::<Vec<_>>()
            .join("/");
        // `**/**` is `**`
        segs.dedup_by(|a, b| *a == Seg::DStar && *b == Seg::DStar);
        Self { top, segs }
    }

    /// `rel`: the segments of a key below `top`.
    pub fn matches(&self, rel: &[&str]) -> bool {
        !rel.is_empty() && full(&self.segs, rel)
    }

    /// Some key below `rel` (one or more segments more) could match: list `rel`'s children.
    pub fn may_descend(&self, rel: &[&str]) -> bool {
        prefix(&self.segs, rel)
    }

    /// The segments of `key` below `top`; `None` when `key` is not below it.
    pub fn rel<'a>(&self, key: &'a str) -> Option<Vec<&'a str>> {
        let rest = key.strip_prefix(&self.top)?;
        if rest.is_empty() {
            return Some(Vec::new());
        }
        let rest = rest.strip_prefix('/')?;
        Some(rest.split('/').collect())
    }

    /// The deepest level a match can have below `top`; `None` with `**`.
    pub fn depth(&self) -> Option<usize> {
        (!self.segs.contains(&Seg::DStar)).then_some(self.segs.len())
    }
}

fn full(p: &[Seg], r: &[&str]) -> bool {
    match p.first() {
        None => r.is_empty(),
        Some(Seg::DStar) => full(&p[1..], r) || (!r.is_empty() && full(p, &r[1..])),
        Some(_) if r.is_empty() => false,
        Some(Seg::Star) => full(&p[1..], &r[1..]),
        Some(Seg::Lit(l)) => l == r[0] && full(&p[1..], &r[1..]),
    }
}

/// `p` matches `r` followed by one or more segments.
fn prefix(p: &[Seg], r: &[&str]) -> bool {
    match p.first() {
        None => false,
        Some(_) if r.is_empty() => true,
        Some(Seg::DStar) => prefix(&p[1..], r) || prefix(p, &r[1..]),
        Some(Seg::Star) => prefix(&p[1..], &r[1..]),
        Some(Seg::Lit(l)) => l == r[0] && prefix(&p[1..], &r[1..]),
    }
}

/// A node named relative to a row: a full key (`wy/…`) as it is, else `.`, `..` and plain
/// segments from `row`. The result stays a full key of the same site.
pub fn resolve(row: &str, target: &str) -> Result<String, String> {
    let target = target.trim();
    if target.starts_with("wy/") {
        check_key(target)?;
        return Ok(target.to_owned());
    }
    let mut parts: Vec<&str> = row.split('/').collect();
    for p in target.split('/') {
        match p {
            "" | "." => {}
            ".." => {
                parts.pop();
            }
            _ => parts.push(p),
        }
    }
    let key = parts.join("/");
    if key.split('/').count() < 3 || !key.starts_with("wy/") {
        return Err(format!("{target:?} from {row}: leaves the site"));
    }
    check_key(&key).map_err(|e| format!("{target:?} from {row}: {e}"))?;
    Ok(key)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn rel(s: &str) -> Vec<&str> {
        s.split('/').collect()
    }

    #[test]
    fn tops_and_matches() {
        let p = Pattern::parse("wy/s/downstream/plc/**").unwrap();
        assert_eq!(p.top, "wy/s/downstream/plc");
        assert!(p.matches(&rel("a")) && p.matches(&rel("a/b/c")));
        assert!(!p.matches(&[]));
        assert!(p.may_descend(&rel("a/b")));

        let p = Pattern::parse("wy/s/downstream/plc").unwrap();
        assert_eq!(p.segs, vec![Seg::Star]);
        assert!(p.matches(&rel("a")) && !p.matches(&rel("a/b")));
        assert!(p.may_descend(&[]) && !p.may_descend(&rel("a")));

        let p = Pattern::parse("wy/s/downstream/*/line1/*/fan").unwrap();
        assert_eq!(p.top, "wy/s/downstream");
        assert!(p.matches(&rel("plc1/line1/ahu1/fan")));
        assert!(!p.matches(&rel("plc1/line2/ahu1/fan")));
        assert!(p.may_descend(&rel("plc1/line1")));
        assert!(!p.may_descend(&rel("plc1/line2")));
        assert!(!p.may_descend(&rel("plc1/line1/ahu1/fan")));
        assert_eq!(p.depth(), Some(4));

        let p = Pattern::parse("wy/s/downstream/**/temp").unwrap();
        assert!(p.matches(&rel("temp")) && p.matches(&rel("a/b/temp")));
        assert!(!p.matches(&rel("a/temp/x")));
        assert!(p.may_descend(&rel("a/temp")));

        for bad in [
            "downstream/x",
            "wy/*/downstream",
            "wy/s/**",
            "wy/s/a b",
            "wy/s",
        ] {
            assert!(Pattern::parse(bad).is_err(), "{bad}");
        }
    }

    #[test]
    fn relative_patterns_and_keys() {
        let p = Pattern::below("wy/s/downstream/plc", &Pattern::relative("./*").unwrap());
        assert_eq!(p.top, "wy/s/downstream/plc");
        assert!(p.matches(&rel("x")));
        assert!(Pattern::relative("../x").is_err());
        assert!(resolve("wy/s/downstream/plc/p1", "./~x").is_err());
        assert_eq!(
            resolve("wy/s/downstream/plc/p1", "../sp").unwrap(),
            "wy/s/downstream/plc/sp"
        );
        assert_eq!(
            resolve("wy/s/downstream/p", ".").unwrap(),
            "wy/s/downstream/p"
        );
        assert_eq!(
            resolve("wy/s/downstream/p", "wy/t/storage/x").unwrap(),
            "wy/t/storage/x"
        );
        assert!(resolve("wy/s/downstream", "../..").is_err());
    }
}
