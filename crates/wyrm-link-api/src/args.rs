//! Reading action arguments the way the SDK delivers them.

use wyrm_core::Value;

/// A typed enum argument (spec 02, `TypeCode::Enum`): the SDK checks it as an
/// index into the list the action's meta declares ([names], in that order),
/// so through an action it arrives as that index; a stored map, an import or
/// a hand-written plan may carry the name. `Ok(None)` when absent or null;
/// `Err` names the choices when the index is out of range or the name unknown.
///
/// One reading for every portable link (ADR 0023): a link that read only the
/// name refused every form Studio or the MCP connector sent (messenger
/// `format`, 2026-11-13; the scheduler's `confirm`, 2026-10-29).
pub fn enum_name<'a>(v: Option<&Value>, names: &[&'a str]) -> Result<Option<&'a str>, String> {
    let bad = || format!("one of {}", names.join(", "));
    let at = |i: u64| {
        usize::try_from(i)
            .ok()
            .and_then(|i| names.get(i).copied())
            .ok_or_else(bad)
    };
    match v {
        None | Some(Value::Null) => Ok(None),
        Some(Value::UInt(i)) => at(*i).map(Some),
        Some(Value::Int(i)) => u64::try_from(*i).map_err(|_| bad()).and_then(at).map(Some),
        Some(Value::Float(f)) if f.fract() == 0.0 && *f >= 0.0 && *f < 1e15 => {
            at(*f as u64).map(Some)
        }
        Some(Value::Str(s)) if s.trim().is_empty() => Ok(None),
        Some(Value::Str(s)) => names
            .iter()
            .copied()
            .find(|n| *n == s.trim())
            .map(Some)
            .ok_or_else(bad),
        Some(_) => Err(bad()),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn index_or_name() {
        let n = ["html", "markdown", "plain"];
        assert_eq!(enum_name(Some(&Value::UInt(0)), &n), Ok(Some("html")));
        assert_eq!(enum_name(Some(&Value::Int(2)), &n), Ok(Some("plain")));
        assert_eq!(
            enum_name(Some(&Value::Float(1.0)), &n),
            Ok(Some("markdown"))
        );
        assert_eq!(
            enum_name(Some(&Value::Str("plain".into())), &n),
            Ok(Some("plain"))
        );
        assert_eq!(enum_name(None, &n), Ok(None));
        assert_eq!(enum_name(Some(&Value::Str(" ".into())), &n), Ok(None));
        let bad = Err("one of html, markdown, plain".to_owned());
        assert_eq!(enum_name(Some(&Value::UInt(3)), &n), bad);
        assert_eq!(enum_name(Some(&Value::Int(-1)), &n), bad);
        assert_eq!(enum_name(Some(&Value::Str("rich".into())), &n), bad);
        assert_eq!(enum_name(Some(&Value::Bool(true)), &n), bad);
    }
}
