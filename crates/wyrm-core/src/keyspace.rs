//! Key-space grammar and helpers. Spec: 01-keyspace.

pub const ROOT: &str = "wy";
pub const SUFFIX_META: &str = "~meta";
pub const SUFFIX_VAL: &str = "~val";
pub const SUFFIX_SET: &str = "~set";
pub const SUFFIX_ACT: &str = "~act";
pub const SUFFIX_STATE: &str = "~state";
pub const SUFFIX_DEF: &str = "~def";

#[derive(Debug, thiserror::Error, PartialEq, Eq)]
pub enum KeyError {
    #[error("empty segment")]
    Empty,
    #[error("segment starts with '~' (reserved): {0}")]
    Reserved(String),
    #[error("illegal character {1:?} in segment {0}")]
    IllegalChar(String, char),
}

/// Validate one path segment: `[A-Za-z0-9_.-]+`, not starting with `~`.
pub fn validate_segment(seg: &str) -> Result<(), KeyError> {
    if seg.is_empty() {
        return Err(KeyError::Empty);
    }
    if seg.starts_with('~') {
        return Err(KeyError::Reserved(seg.to_owned()));
    }
    if let Some(c) = seg
        .chars()
        .find(|c| !(c.is_ascii_alphanumeric() || matches!(c, '_' | '-' | '.')))
    {
        return Err(KeyError::IllegalChar(seg.to_owned(), c));
    }
    Ok(())
}

/// Validate a node path (segments separated by `/`), e.g. `ahu1/supply_temp`.
pub fn validate_path(path: &str) -> Result<(), KeyError> {
    path.split('/').try_for_each(validate_segment)
}

/// Build `wy/<site>/downstream/<link>/<path>/<suffix>`.
pub fn down_key(site: &str, link: &str, path: &str, suffix: &str) -> String {
    if path.is_empty() {
        format!("{ROOT}/{site}/downstream/{link}/{suffix}")
    } else {
        format!("{ROOT}/{site}/downstream/{link}/{path}/{suffix}")
    }
}

/// Site sections before spec 0.2.0 and their names since.
const RENAMED: [(&str, &str); 3] = [
    ("down", "downstream"),
    ("up", "upstream"),
    ("flows", "dataflows"),
];

/// A key or grant pattern stored before spec 0.2.0 (`wy/<site>/down/…`,
/// `…/up/…`, `…/flows/…`) under its section's new name; other keys as they
/// are. `<site>` may be `{site}` or a wildcard.
pub fn renamed(key: &str) -> std::borrow::Cow<'_, str> {
    let mut segs = key.splitn(4, '/');
    let (Some(ROOT), Some(site), Some(section)) = (segs.next(), segs.next(), segs.next()) else {
        return key.into();
    };
    match RENAMED.iter().find(|(old, _)| *old == section) {
        Some((_, new)) => match segs.next() {
            Some(rest) => format!("{ROOT}/{site}/{new}/{rest}").into(),
            None => format!("{ROOT}/{site}/{new}").into(),
        },
        None => key.into(),
    }
}

/// The key of a tree route, as an explorer shows and copies it (DSA's Copy
/// Path): `wy/central/downstream/edge/downstream/plant/x` → `wy/plant/x`.
/// A `downstream/<s>` or `upstream/<s>` step where `is_site(s)` is a peer
/// broker node, so the route goes on in that site's own keys. Other keys
/// come back as they are.
pub fn route_key(route: &str, is_site: impl Fn(&str) -> bool) -> String {
    let segs: Vec<&str> = route.split('/').collect();
    if segs.len() < 2 || segs[0] != ROOT {
        return route.to_owned();
    }
    let mut site = segs[1];
    let mut start = 2;
    let mut i = 2;
    while i + 1 < segs.len() {
        if matches!(segs[i], "downstream" | "upstream") && is_site(segs[i + 1]) {
            site = segs[i + 1];
            start = i + 2;
            i += 2;
        } else {
            i += 1;
        }
    }
    let rest = segs[start..].join("/");
    if rest.is_empty() {
        format!("{ROOT}/{site}")
    } else {
        format!("{ROOT}/{site}/{rest}")
    }
}

/// Split a full key into `(base, suffix)` at the first `/~` boundary.
/// For `.../~act/<name>` the suffix is `~act/<name>`. `None` if no suffix.
pub fn split_suffix(key: &str) -> Option<(&str, &str)> {
    let idx = key.find("/~")?;
    Some((&key[..idx], &key[idx + 1..]))
}

/// Encode a list of keys with prefix compression (spec 02-meta, `view=keys`):
/// an element ending in `/` pushes a prefix, an empty element pops it.
pub fn compress_keys<I: IntoIterator<Item = S>, S: AsRef<str>>(keys: I) -> Vec<String> {
    let mut out = Vec::new();
    let mut stack: Vec<String> = Vec::new();
    for k in keys {
        let k = k.as_ref();
        // pop while k does not start with current prefix
        while let Some(top) = stack.last() {
            if k.starts_with(top.as_str()) {
                break;
            }
            stack.pop();
            out.push(String::new());
        }
        let prefix: String = stack.iter().map(String::as_str).collect();
        let rel = &k[prefix.len()..];
        match rel.rfind('/') {
            Some(i) => {
                let dir = &rel[..=i];
                stack.push(dir.to_owned());
                out.push(dir.to_owned());
                out.push(rel[i + 1..].to_owned());
            }
            None => out.push(rel.to_owned()),
        }
    }
    for _ in stack {
        out.push(String::new());
    }
    out
}

/// Inverse of [`compress_keys`].
pub fn expand_keys<I: IntoIterator<Item = S>, S: AsRef<str>>(items: I) -> Vec<String> {
    let mut out = Vec::new();
    let mut stack: Vec<String> = Vec::new();
    for it in items {
        let it = it.as_ref();
        if it.is_empty() {
            stack.pop();
        } else if it.ends_with('/') {
            stack.push(it.to_owned());
        } else {
            let mut k: String = stack.iter().map(String::as_str).collect();
            k.push_str(it);
            out.push(k);
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn tree_routes_become_keys() {
        let sites = |s: &str| matches!(s, "edge" | "plant" | "central");
        assert_eq!(
            route_key(
                "wy/central/downstream/edge/downstream/plant/downstream/line/g0/p0",
                sites
            ),
            "wy/plant/downstream/line/g0/p0"
        );
        assert_eq!(
            route_key("wy/central/downstream/edge/sys/history", sites),
            "wy/edge/sys/history"
        );
        assert_eq!(route_key("wy/edge/upstream/central", sites), "wy/central");
        // a link named like no site, and plain keys, stay
        assert_eq!(
            route_key("wy/central/downstream/mock/g0/p0", sites),
            "wy/central/downstream/mock/g0/p0"
        );
        assert_eq!(route_key("downstream/edge/x", sites), "downstream/edge/x");
    }

    #[test]
    fn sections_renamed_by_spec_0_2() {
        for (old, new) in [
            ("wy/s/down/mock/p0", "wy/s/downstream/mock/p0"),
            ("wy/{site}/down", "wy/{site}/downstream"),
            ("wy/*/up/central", "wy/*/upstream/central"),
            ("wy/s/flows/f1/~def", "wy/s/dataflows/f1/~def"),
            ("wy/s/downstream/mock", "wy/s/downstream/mock"),
            ("wy/s/sys/links/down", "wy/s/sys/links/down"),
            ("wy/**", "wy/**"),
            ("down/mock", "down/mock"),
        ] {
            assert_eq!(renamed(old), new, "{old}");
        }
    }

    #[test]
    fn segments() {
        assert!(validate_segment("ahu1").is_ok());
        assert!(validate_segment("supply_temp.v2").is_ok());
        assert_eq!(
            validate_segment("~meta"),
            Err(KeyError::Reserved("~meta".into()))
        );
        assert!(matches!(
            validate_segment("a b"),
            Err(KeyError::IllegalChar(_, ' '))
        ));
        assert!(matches!(
            validate_segment("a*"),
            Err(KeyError::IllegalChar(_, '*'))
        ));
    }

    #[test]
    fn keys_roundtrip() {
        let keys = [
            "ahu1/supply_temp",
            "ahu1/return_temp",
            "ahu1/fan",
            "ahu2/supply_temp",
        ];
        let c = compress_keys(keys);
        assert_eq!(
            c,
            vec![
                "ahu1/",
                "supply_temp",
                "return_temp",
                "fan",
                "",
                "ahu2/",
                "supply_temp",
                ""
            ]
        );
        assert_eq!(
            expand_keys(&c),
            keys.iter().map(|s| s.to_string()).collect::<Vec<_>>()
        );
    }
}
