//! Checks done before anything is sent: value and argument validation (the
//! same rules as the responder SDK, `wyrm-link-sdk/src/runtime.rs`), the
//! permission level a request needs, and a readable pre-check of a human
//! approval token. The link still makes the real decision.

use std::cmp::Ordering;
use std::collections::BTreeMap;
use std::time::{SystemTime, UNIX_EPOCH};
use wyrm_core::meta::ParamMeta;
use wyrm_core::ptok::{self, PtokClaims};
use wyrm_core::{NodeMeta, Perm, TypeCode, Value, Writable};

/// `wy/<site>/sys` and everything under it is the control plane.
pub fn is_control_plane(site: &str, key: &str) -> bool {
    let root = format!("wy/{site}/sys");
    key == root || key.starts_with(&format!("{root}/"))
}

/// Level a `~set` on a node with this meta needs (`Err` = not writable).
pub fn set_level(meta: &NodeMeta) -> Result<Perm, String> {
    if meta.ty.is_none() {
        return Err("containers have no value".into());
    }
    match meta.writable.unwrap_or_default() {
        Writable::Never => Err("node is not writable".into()),
        Writable::Config => Ok(Perm::Config),
        Writable::Write => Ok(Perm::Write),
    }
}

/// Level an action needs: `actions.<a>.level`, else the node's `invokable`.
pub fn action_level(meta: &NodeMeta, action: &str) -> Result<Perm, String> {
    let act = meta
        .actions
        .as_ref()
        .and_then(|a| a.get(action))
        .ok_or_else(|| format!("no action {action:?} on this node"))?;
    act.level
        .or(meta.invokable)
        .filter(|p| *p != Perm::None)
        .ok_or_else(|| format!("action {action:?} is not invokable"))
}

/// An enum given by name (`"manual"`) → its index; anything else unchanged.
pub fn coerce_enum(ty: Option<TypeCode>, names: Option<&[String]>, v: Value) -> Value {
    match (ty, names, &v) {
        (Some(TypeCode::Enum), Some(names), Value::Str(s)) => names
            .iter()
            .position(|n| n == s)
            .map(|i| Value::UInt(i as u64))
            .unwrap_or(v),
        _ => v,
    }
}

/// Numeric order: exact for integer pairs, `f64` otherwise; `None` for NaN.
fn num_cmp(a: &Value, b: &Value) -> Option<Ordering> {
    let int = |v: &Value| match v {
        Value::Int(i) => Some(*i as i128),
        Value::UInt(u) => Some(*u as i128),
        _ => None,
    };
    match (int(a), int(b)) {
        (Some(x), Some(y)) => Some(x.cmp(&y)),
        _ => a.as_f64()?.partial_cmp(&b.as_f64()?),
    }
}

fn num_str(v: &Value) -> String {
    match v {
        Value::Int(i) => i.to_string(),
        Value::UInt(u) => u.to_string(),
        other => other.as_f64().map(|f| f.to_string()).unwrap_or_default(),
    }
}

/// Type, `enum` and `cfg.min/max` (same rules as the responder SDK).
pub fn validate_value(meta: &NodeMeta, v: &Value) -> Result<(), String> {
    let ok = match meta.ty {
        Some(TypeCode::Number) => {
            let x = v.as_f64().ok_or("expected number")?;
            if !x.is_finite() {
                return Err("value must be finite".into());
            }
            if let Some(min) = meta.cfg_value("min").filter(|m| m.as_f64().is_some()) {
                if num_cmp(v, min).is_none_or(|o| o == Ordering::Less) {
                    return Err(format!("value {} < min {}", num_str(v), num_str(min)));
                }
            }
            if let Some(max) = meta.cfg_value("max").filter(|m| m.as_f64().is_some()) {
                if num_cmp(v, max).is_none_or(|o| o == Ordering::Greater) {
                    return Err(format!("value {} > max {}", num_str(v), num_str(max)));
                }
            }
            true
        }
        Some(TypeCode::Enum) => {
            let Value::UInt(i) = v else {
                return Err(match &meta.enum_values {
                    Some(n) => format!("expected one of {n:?} or its index"),
                    None => "expected enum index".into(),
                });
            };
            if let Some(values) = &meta.enum_values {
                if *i as usize >= values.len() {
                    return Err("enum index out of range".into());
                }
            }
            true
        }
        Some(TypeCode::String) => matches!(v, Value::Str(_)),
        Some(TypeCode::Bool) => matches!(v, Value::Bool(_)),
        Some(TypeCode::Binary) => matches!(v, Value::Bytes(_)),
        Some(TypeCode::Map) => matches!(v, Value::Map(_)),
        Some(TypeCode::Array) => matches!(v, Value::Array(_)),
        Some(TypeCode::Null) => matches!(v, Value::Null),
        Some(TypeCode::Dynamic) | None => true,
    };
    if ok {
        Ok(())
    } else {
        Err(format!(
            "value type does not match ~meta.type ({})",
            meta.ty.map(|t| t.name()).unwrap_or("?")
        ))
    }
}

/// Coerce enum names, then check: no unknown names, every `required`
/// present, each value checked like a `~set` value against its `ParamMeta`.
pub fn prepare_args(
    params: &BTreeMap<String, ParamMeta>,
    given: BTreeMap<String, Value>,
) -> Result<BTreeMap<String, Value>, String> {
    let mut out = BTreeMap::new();
    for (name, v) in given {
        let p = params
            .get(&name)
            .ok_or_else(|| format!("unknown param {name}"))?;
        let v = coerce_enum(p.ty, p.enum_values.as_deref(), v);
        let as_meta = NodeMeta {
            ty: p.ty,
            enum_values: p.enum_values.clone(),
            ..Default::default()
        };
        validate_value(&as_meta, &v).map_err(|e| format!("{name}: {e}"))?;
        out.insert(name, v);
    }
    for (name, p) in params {
        if p.required == Some(true) && !out.contains_key(name) {
            return Err(format!("missing {name}"));
        }
    }
    Ok(out)
}

/// What the server could read from an approval token without its keys.
#[derive(Debug, Clone)]
pub struct ApprovalInfo {
    pub sub: String,
    pub perm: Perm,
    pub expires_in_s: u64,
}

/// The subject of a token, without verifying it (for `origin` marking).
pub fn token_subject(tok: &[u8]) -> Option<String> {
    let parts = ptok::split(tok)?;
    wyrm_core::codec::from_slice::<PtokClaims>(parts.claims)
        .ok()
        .map(|c| c.sub)
}

/// Decode a base64 `ptok` (standard or URL-safe alphabet, padding optional).
pub fn decode_token(b64: &str) -> Result<Vec<u8>, String> {
    use base64::Engine as _;
    let s = b64.trim();
    base64::engine::general_purpose::STANDARD
        .decode(s)
        .or_else(|_| base64::engine::general_purpose::STANDARD_NO_PAD.decode(s))
        .or_else(|_| base64::engine::general_purpose::URL_SAFE.decode(s))
        .or_else(|_| base64::engine::general_purpose::URL_SAFE_NO_PAD.decode(s))
        .map_err(|_| "approval is not base64".to_owned())
}

/// Readable pre-check of a human approval for exactly `key` at `need`:
/// every grant is exactly `key`, the site matches, it has not expired, the
/// effective level reaches `need`, and the subject is not an AI (`ai:*`).
/// The signature is NOT checked here; the responder does that.
pub fn precheck_approval(
    tok: &[u8],
    key: &str,
    site: &str,
    need: Perm,
) -> Result<ApprovalInfo, String> {
    let parts = ptok::split(tok).ok_or("approval is not a ptok v1")?;
    let c: PtokClaims = wyrm_core::codec::from_slice(parts.claims)
        .map_err(|_| "approval claims do not decode".to_owned())?;
    if c.sub.starts_with("ai:") {
        return Err(format!(
            "approval subject {:?} is an AI agent; a human operator must sign it",
            c.sub
        ));
    }
    if c.site != site {
        return Err(format!("approval is for site {:?}, not {site:?}", c.site));
    }
    if c.grants.is_empty() || c.grants.iter().any(|g| g.k != key) {
        return Err(format!(
            "approval must grant exactly {key} (it grants {:?})",
            c.grants.iter().map(|g| g.k.as_str()).collect::<Vec<_>>()
        ));
    }
    let now = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0);
    if c.exp <= now {
        return Err("approval has expired".into());
    }
    let perm = c.grants[0].p.min(c.max);
    if perm < need {
        return Err(format!(
            "approval gives {} on {key}; {} is needed",
            perm.name(),
            need.name()
        ));
    }
    Ok(ApprovalInfo {
        sub: c.sub,
        perm,
        expires_in_s: c.exp - now,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use wyrm_core::meta::ActionMeta;

    #[test]
    fn levels() {
        let n = NodeMeta::number().writable(Writable::Config);
        assert_eq!(set_level(&n), Ok(Perm::Config));
        assert!(set_level(&NodeMeta::number()).is_err());
        assert!(set_level(&NodeMeta::folder()).is_err());
        let mut m = NodeMeta::folder();
        m.actions = Some(BTreeMap::from([
            ("a".into(), ActionMeta::new().level(Perm::Config)),
            ("b".into(), ActionMeta::new()),
        ]));
        assert_eq!(action_level(&m, "a"), Ok(Perm::Config));
        assert!(action_level(&m, "b").is_err());
        m.invokable = Some(Perm::Write);
        assert_eq!(action_level(&m, "b"), Ok(Perm::Write));
        assert!(action_level(&m, "c").is_err());
        assert!(is_control_plane("s", "wy/s/sys/links/x"));
        assert!(is_control_plane("s", "wy/s/sys"));
        assert!(!is_control_plane("s", "wy/s/system"));
    }

    #[test]
    fn values_and_enums() {
        let m = NodeMeta::number().cfg("min", 0.0).cfg("max", 100.0);
        assert!(validate_value(&m, &Value::UInt(5)).is_ok());
        assert!(validate_value(&m, &Value::UInt(500)).is_err());
        assert!(validate_value(&m, &Value::Str("x".into())).is_err());
        let names = vec!["auto".to_owned(), "manual".to_owned()];
        let v = coerce_enum(Some(TypeCode::Enum), Some(&names), Value::from("manual"));
        assert_eq!(v, Value::UInt(1));
        let params = BTreeMap::from([(
            "n".to_owned(),
            ParamMeta::of(TypeCode::Number).required(true),
        )]);
        assert!(prepare_args(&params, BTreeMap::new()).is_err());
        assert!(prepare_args(&params, BTreeMap::from([("x".into(), Value::UInt(1))])).is_err());
        assert!(prepare_args(&params, BTreeMap::from([("n".into(), Value::UInt(1))])).is_ok());
    }
}
