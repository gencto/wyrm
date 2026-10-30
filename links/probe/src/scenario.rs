//! Scenarios: JSON of steps, run in order against a broker through its
//! gateway.
//!
//! ```json
//! { "name": "history", "description": "…", "steps": [
//!   { "watch": "wy/{site}/sys/history" },
//!   { "invoke": "wy/{site}/sys/history", "action": "add_watch_group",
//!     "args": { "name": "p{run}" } },
//!   { "added": "wy/{site}/sys/history", "name": "p{run}" },
//!   { "invoke": "wy/{site}/sys/history/p{run}", "action": "remove", "cleanup": true }
//! ] }
//! ```
//!
//! Steps (one kind each; `cleanup: true` runs even after a failure):
//! * `watch` / `unwatch` key: a `list` stream, opened before the actions
//!   whose callbacks the later steps expect;
//! * `sub` pattern: a `subscribe` stream;
//! * `invoke` key, `action`, `args`; `set` key, `value`: `expect` `"ok"`
//!   (default) or `"error"` with an optional `error` substring; `save_as`
//!   keeps a text result as a variable (with `field`, that text field of a
//!   map result, as `export`'s `json`);
//! * `added` / `changed` / `removed` parent, `name` (`"*"`: any; `save_as`
//!   keeps the name): a callback on a watched parent after the last action,
//!   within `within_ms` (default 5000);
//! * `value` key, optional `equals`: a sample on a subscription after the
//!   last action;
//! * `meta` key with `has_action`, `lacks_action`, `has_child`,
//!   `lacks_child`, `type`; `children` key with `contains`, `lacks`;
//! * `sleep_ms`;
//! * `require` key: the scenario applies only where that node exists; when
//!   it does not, every later step is skipped and nothing fails. A key of a
//!   link that is down answers `disconnected` and fails: require the link's
//!   `sys/links/<id>` first to skip sites that do not have the link.
//!
//! A step that still names a variable nobody saved (a cleanup after the
//! step that saves it failed) is skipped.
//!
//! `{site}`, `{run}` (unique per run) and saved variables are replaced in
//! every text of a step just before it runs.

use serde_json::Value as Json;
use std::collections::BTreeMap;
use std::time::Duration;
use wyrm_core::Value;

/// Step kinds, in the order they are looked for.
pub const KINDS: [&str; 13] = [
    "require", "watch", "unwatch", "sub", "invoke", "set", "added", "changed", "removed", "value",
    "meta", "children", "sleep_ms",
];

pub struct Scenario {
    pub name: String,
    pub description: String,
    pub steps: Vec<Json>,
}

impl Scenario {
    pub fn parse(text: &str) -> Result<Self, String> {
        let j: Json = serde_json::from_str(text).map_err(|e| format!("scenario: {e}"))?;
        let Json::Object(mut m) = j else {
            return Err("scenario: a JSON object".into());
        };
        let text = |m: &mut serde_json::Map<String, Json>, k: &str| match m.remove(k) {
            Some(Json::String(s)) => s,
            _ => String::new(),
        };
        let name = text(&mut m, "name");
        let description = text(&mut m, "description");
        let Some(Json::Array(steps)) = m.remove("steps") else {
            return Err("scenario: steps (an array) required".into());
        };
        if steps.is_empty() || steps.len() > 500 {
            return Err("scenario: 1 to 500 steps".into());
        }
        for (i, s) in steps.iter().enumerate() {
            kind_of(s).ok_or_else(|| format!("step {}: one of {KINDS:?}", i + 1))?;
        }
        Ok(Self {
            name,
            description,
            steps,
        })
    }
}

/// The kind of a step object.
pub fn kind_of(step: &Json) -> Option<&'static str> {
    let m = step.as_object()?;
    KINDS.iter().copied().find(|k| m.contains_key(*k))
}

/// `step` with `{var}` replaced in every text.
pub fn render(step: &Json, vars: &BTreeMap<String, String>) -> Json {
    match step {
        Json::String(s) => {
            let mut s = s.clone();
            for (k, v) in vars {
                s = s.replace(&format!("{{{k}}}"), v);
            }
            Json::String(s)
        }
        Json::Array(a) => Json::Array(a.iter().map(|x| render(x, vars)).collect()),
        Json::Object(m) => Json::Object(
            m.iter()
                .map(|(k, v)| (k.clone(), render(v, vars)))
                .collect(),
        ),
        other => other.clone(),
    }
}

/// A `{name}` left in a text of `step` for a name in `saved` (a variable
/// some step saves).
pub fn unset(step: &Json, saved: &[String]) -> Option<String> {
    match step {
        Json::String(s) => saved
            .iter()
            .find(|n| s.contains(&format!("{{{n}}}")))
            .cloned(),
        Json::Array(a) => a.iter().find_map(|x| unset(x, saved)),
        Json::Object(m) => m.values().find_map(|x| unset(x, saved)),
        _ => None,
    }
}

/// JSON as a WYRM value.
pub fn to_value(j: &Json) -> Value {
    match j {
        Json::Null => Value::Null,
        Json::Bool(b) => Value::Bool(*b),
        Json::Number(n) => match (n.as_u64(), n.as_i64(), n.as_f64()) {
            (Some(u), _, _) => Value::UInt(u),
            (_, Some(i), _) => Value::Int(i),
            (_, _, Some(f)) => Value::Float(f),
            _ => Value::Null,
        },
        Json::String(s) => Value::Str(s.clone()),
        Json::Array(a) => Value::Array(a.iter().map(to_value).collect()),
        Json::Object(m) => Value::Map(m.iter().map(|(k, v)| (k.clone(), to_value(v))).collect()),
    }
}

/// Two values equal as a scenario means it: numbers by value.
pub fn same(a: &Value, b: &Value) -> bool {
    match (a.as_f64(), b.as_f64()) {
        (Some(x), Some(y)) => x == y,
        _ => a == b,
    }
}

pub fn text<'a>(step: &'a Json, k: &str) -> Option<&'a str> {
    step.get(k).and_then(Json::as_str)
}

pub fn texts(step: &Json, k: &str) -> Vec<String> {
    match step.get(k) {
        Some(Json::String(s)) => vec![s.clone()],
        Some(Json::Array(a)) => a
            .iter()
            .filter_map(|x| x.as_str().map(str::to_owned))
            .collect(),
        _ => Vec::new(),
    }
}

pub fn within(step: &Json) -> Duration {
    Duration::from_millis(
        step.get("within_ms")
            .and_then(Json::as_u64)
            .unwrap_or(5000)
            .min(60_000),
    )
}

/// Built-in scenarios, by name.
pub const BUILTIN: [(&str, &str); 6] = [
    ("history", include_str!("../scenarios/history.json")),
    ("storage", include_str!("../scenarios/storage.json")),
    ("tokens", include_str!("../scenarios/tokens.json")),
    ("dataflows", include_str!("../scenarios/dataflows.json")),
    ("scheduler", include_str!("../scenarios/scheduler.json")),
    ("modbus", include_str!("../scenarios/modbus.json")),
];

pub fn builtin(name: &str) -> Option<&'static str> {
    BUILTIN.iter().find(|(n, _)| *n == name).map(|(_, s)| *s)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn builtins_parse_and_render() {
        for (name, text) in BUILTIN {
            let s = Scenario::parse(text).unwrap_or_else(|e| panic!("{name}: {e}"));
            assert_eq!(s.name, name);
        }
        let vars = BTreeMap::from([("site".to_owned(), "edge".to_owned())]);
        let j: Json = serde_json::json!({"watch": "wy/{site}/sys", "x": ["{site}", 1]});
        assert_eq!(
            render(&j, &vars),
            serde_json::json!({"watch": "wy/edge/sys", "x": ["edge", 1]})
        );
        assert!(Scenario::parse(r#"{"steps": [{"nothing": 1}]}"#).is_err());
        assert!(same(&Value::UInt(2), &Value::Float(2.0)));
    }
}
