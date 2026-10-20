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

/// Build `wy/<site>/down/<link>/<path>/<suffix>`.
pub fn down_key(site: &str, link: &str, path: &str, suffix: &str) -> String {
    if path.is_empty() {
        format!("{ROOT}/{site}/down/{link}/{suffix}")
    } else {
        format!("{ROOT}/{site}/down/{link}/{path}/{suffix}")
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
