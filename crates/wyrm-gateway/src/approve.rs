//! Approvals of an agent task for a logged-in user (ADR 0049).
//!
//! `approve` on `downstream/<agent>/tasks/<id>` takes one human `ptok` per step (ADR 0005).
//! A user of the gateway holds no key, so the gateway signs those tokens with the user's
//! rights, as it signs flow deploy proofs (ADR 0008). The rule, in the order it is checked:
//!
//! 1. the plan is the one the agent link stores: the gateway reads `tasks/<id>/~state` itself
//!    with the user's own token; the client names steps by request key and nothing else of a
//!    step comes from the client;
//! 2. the task is `awaiting_approval`, and the hash of the plan the gateway read (made here
//!    from its steps, not taken from the record) is the hash the client made from the plan
//!    the user saw (`args.plan`); the link checks the hash against its own plan again when
//!    it takes the approval;
//! 3. every named step is a step of that plan that needs a human, named once;
//! 4. the user's grants give every named step at least the level it needs; if one does not,
//!    the whole call is refused, the answer names those steps, and no token is made;
//! 5. one token per named step: subject the user, the single grant exactly the step's request
//!    key, `max` the level the step needs (never the user's whole level), `args` the SHA-256 of
//!    the step's request body, a fresh `jti`, `exp` in [`APPROVAL_TTL`];
//! 6. the steps of the plan that need a human and were not named go to the link as `skip`.

use crate::Refusal;
use sha2::{Digest, Sha256};
use std::collections::BTreeMap;
use std::time::Duration;
use wyrm_core::{Perm, Status, Value};

/// Lifetime of an approval token: the run must send the step within it.
pub const APPROVAL_TTL: Duration = Duration::from_secs(300);
/// Largest document the `doc` op returns, and the largest task record `approve` reads.
pub const MAX_DOC: usize = 1024 * 1024;
/// Steps one `approve` may name (the agent link keeps at most 50 in a plan).
pub const MAX_STEPS: usize = 64;

/// One step of the stored plan, as far as an approval needs it.
#[derive(Debug, Clone, PartialEq)]
pub(crate) struct Step {
    /// The request key: `<node>/~set` or `<node>/~act/<action>`.
    pub key: String,
    pub level: Perm,
    /// Does the step need a human (the link's bar of now)?
    pub approval: bool,
    /// SHA-256 of the request body the run will send.
    pub body: [u8; 32],
}

/// The task record, as far as an approval needs it.
#[derive(Debug, Clone, PartialEq)]
pub(crate) struct Plan {
    pub state: String,
    pub hash: String,
    pub steps: Vec<Step>,
}

/// What the client asks for: `args {steps: [<request key>, …], plan: <plan_hash>}`.
#[derive(Debug, Clone, PartialEq)]
pub(crate) struct Ask {
    pub steps: Vec<String>,
    pub plan: String,
}

fn bad(m: impl Into<String>) -> Refusal {
    Refusal::new(Status::InvalidParameter, m)
}

fn text<'a>(m: &'a BTreeMap<String, Value>, k: &str) -> Option<&'a str> {
    match m.get(k) {
        Some(Value::Str(s)) => Some(s),
        _ => None,
    }
}

impl Ask {
    pub fn parse(args: Option<&Value>) -> Result<Self, Refusal> {
        let Some(Value::Map(m)) = args else {
            return Err(bad("args: {steps, plan} required"));
        };
        if let Some(k) = m.keys().find(|k| !matches!(k.as_str(), "steps" | "plan")) {
            // `approvals` above all: a token never comes from the client
            return Err(bad(format!("args.{k}: only steps and plan are taken")));
        }
        let Some(Value::Array(items)) = m.get("steps") else {
            return Err(bad("args.steps: an array of request keys required"));
        };
        if items.is_empty() {
            return Err(bad(
                "args.steps: no step is approved (reject the plan instead)",
            ));
        }
        if items.len() > MAX_STEPS {
            return Err(bad(format!("args.steps: at most {MAX_STEPS}")));
        }
        let mut steps: Vec<String> = Vec::with_capacity(items.len());
        for i in items {
            match i {
                Value::Str(k) if !steps.contains(k) => steps.push(k.clone()),
                Value::Str(k) => return Err(bad(format!("args.steps: {k} is named twice"))),
                _ => return Err(bad("args.steps: an array of request keys required")),
            }
        }
        let plan = text(m, "plan")
            .filter(|h| !h.is_empty())
            .ok_or_else(|| bad("args.plan: the plan_hash of the plan you read is required"))?;
        Ok(Self {
            steps,
            plan: plan.to_owned(),
        })
    }
}

fn level_of(name: &str) -> Option<Perm> {
    Perm::ALL
        .iter()
        .copied()
        .find(|p| p.name() == name)
        .filter(|p| *p >= Perm::Write)
}

/// Is `key` the request key of a `set` or `invoke` on a plain node key of `site`? No
/// wildcard and no other `~` segment: the key becomes a token's grant.
fn request_key_ok(site: &str, op: &str, key: &str) -> bool {
    let node = match op {
        "set" => key.strip_suffix("/~set"),
        "invoke" => key.rsplit_once("/~act/").and_then(|(node, action)| {
            wyrm_core::keyspace::validate_segment(action)
                .is_ok()
                .then_some(node)
        }),
        _ => None,
    };
    node.is_some_and(|n| crate::ws::check_key(site, n, false).is_ok())
}

/// The hash of a plan (`links/agent` `tools::plan_hash`): SHA-256, in hex, of the canonical
/// CBOR of `[[op, key, args, level], …]` in plan order. The link, the gateway and the client
/// each make it from the plan they hold; an approval goes through only when all three agree.
fn plan_hash(steps: &Value) -> Option<String> {
    let bytes = wyrm_core::codec::to_vec(steps).ok()?;
    Some(
        Sha256::digest(&bytes)
            .iter()
            .map(|b| format!("{b:02x}"))
            .collect(),
    )
}

impl Plan {
    /// Read a task's `~state` document (`links/agent`). `site` is the site of the task: every
    /// step must be a request on a node of it.
    pub fn parse(doc: &Value, site: &str) -> Result<Self, Refusal> {
        let old = || {
            Refusal::new(
                Status::NotSupported,
                "this node is not a task of an agent link that takes approvals from the gateway",
            )
        };
        let Value::Map(m) = doc else {
            return Err(old());
        };
        let state = text(m, "state").ok_or_else(old)?.to_owned();
        // absent on an agent link older than partial approvals: it could not take `skip`
        let claimed = text(m, "plan_hash").ok_or_else(old)?;
        let Some(Value::Array(items)) = m.get("plan") else {
            return Err(old());
        };
        let mut steps: Vec<Step> = Vec::with_capacity(items.len());
        let mut hashed = Vec::with_capacity(items.len());
        for (i, s) in items.iter().enumerate() {
            let broken = |what: &str| {
                Refusal::new(
                    Status::InternalError,
                    format!("plan step {}: {what}", i + 1),
                )
            };
            let Value::Map(s) = s else {
                return Err(broken("not a map"));
            };
            let op = text(s, "op").ok_or_else(|| broken("no op"))?;
            let key = text(s, "key").ok_or_else(|| broken("no key"))?;
            if !request_key_ok(site, op, key) {
                return Err(broken("its key is not a request on a node of this site"));
            }
            let level = text(s, "level")
                .and_then(level_of)
                .ok_or_else(|| broken("no level of write or config"))?;
            if steps.iter().any(|s| s.key == key) {
                return Err(broken("a second step on one key"));
            }
            let args = s.get("args").cloned().unwrap_or(Value::Null);
            hashed.push(Value::Array(vec![
                Value::from(op),
                Value::from(key),
                args.clone(),
                Value::from(level.name()),
            ]));
            let body = match op {
                "set" => wyrm_client::set_payload(args),
                _ => wyrm_client::invoke_payload(&args),
            }
            .map_err(|_| broken("its arguments do not encode"))?;
            steps.push(Step {
                key: key.to_owned(),
                level,
                approval: matches!(s.get("approval"), Some(Value::Bool(true))),
                body: Sha256::digest(&body).into(),
            });
        }
        // The hash is made here from the plan as read, never taken from the record: the
        // approval is for these very requests, whatever the link says its hash is.
        let hash = plan_hash(&Value::Array(hashed))
            .ok_or_else(|| Refusal::new(Status::InternalError, "the plan does not encode"))?;
        if hash != claimed {
            return Err(Refusal::new(
                Status::InternalError,
                "the task's plan_hash is not the hash of its plan",
            ));
        }
        Ok(Self { state, hash, steps })
    }

    /// Rules 2–4 and 6 of the module: the steps to sign and the request keys to skip.
    /// `may(key)` is the user's level on a request key.
    pub fn select(
        &self,
        ask: &Ask,
        may: impl Fn(&str) -> Perm,
    ) -> Result<(Vec<&Step>, Vec<String>), Refusal> {
        if self.state != "awaiting_approval" {
            return Err(bad(format!(
                "task is {}, not awaiting_approval",
                self.state
            )));
        }
        if self.hash != ask.plan {
            return Err(bad(
                "plan: the plan is not the one this approval was made for; read it again",
            ));
        }
        let mut sign = Vec::with_capacity(ask.steps.len());
        for k in &ask.steps {
            match self.steps.iter().find(|s| &s.key == k) {
                Some(s) if s.approval => sign.push(s),
                Some(_) => {
                    return Err(bad(format!(
                        "{k} needs no approval: the agent runs it with its own key"
                    )))
                }
                None => return Err(bad(format!("{k} is not a step of the plan"))),
            }
        }
        let denied: Vec<String> = sign
            .iter()
            .filter(|s| may(&s.key) < s.level)
            .map(|s| format!("{} (needs {})", s.key, s.level.name()))
            .collect();
        if !denied.is_empty() {
            return Err(Refusal::new(
                Status::PermissionDenied,
                format!("you may not approve: {}", denied.join(", ")),
            ));
        }
        let skip = self
            .steps
            .iter()
            .filter(|s| s.approval && !ask.steps.contains(&s.key))
            .map(|s| s.key.clone())
            .collect();
        Ok((sign, skip))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn map<const N: usize>(f: [(&str, Value); N]) -> Value {
        Value::Map(f.into_iter().map(|(k, v)| (k.to_owned(), v)).collect())
    }

    fn step(op: &str, key: &str, level: &str, approval: bool) -> Value {
        map([
            ("op", Value::from(op)),
            ("key", Value::from(key)),
            ("args", Value::Float(1.0)),
            ("level", Value::from(level)),
            ("approval", Value::Bool(approval)),
        ])
    }

    /// A record whose `plan_hash` is the hash of its steps, as an honest link writes it.
    fn record(state: &str, steps: Vec<Value>) -> Value {
        let field = |s: &Value, k: &str| match s {
            Value::Map(m) => m.get(k).cloned().unwrap_or(Value::Null),
            _ => Value::Null,
        };
        let hashed = steps
            .iter()
            .map(|s| Value::Array(["op", "key", "args", "level"].map(|k| field(s, k)).into()))
            .collect();
        map([
            ("state", Value::from(state)),
            (
                "plan_hash",
                Value::from(plan_hash(&Value::Array(hashed)).unwrap()),
            ),
            ("plan", Value::Array(steps)),
        ])
    }

    /// The link's word is not taken for the hash: a record that shows one plan under the
    /// hash of another is refused, as is a plan with two steps on one key.
    #[test]
    fn the_hash_is_made_from_the_plan_as_read() {
        let honest = record("awaiting_approval", vec![step("set", A, "write", true)]);
        let p = Plan::parse(&honest, "s").unwrap();
        assert_eq!(p.hash.len(), 64);
        let Value::Map(mut m) = honest else {
            unreachable!()
        };
        // other arguments under the old hash
        let mut other = step("set", A, "write", true);
        if let Value::Map(s) = &mut other {
            s.insert("args".into(), Value::Float(9999.0));
        }
        m.insert("plan".into(), Value::Array(vec![other]));
        let e = Plan::parse(&Value::Map(m), "s").unwrap_err();
        assert_eq!(e.status, Status::InternalError);
        assert!(e.message.contains("plan_hash"), "{}", e.message);
        // the model's words and the run's results are not part of it
        let mut reworded = step("set", A, "write", true);
        if let Value::Map(s) = &mut reworded {
            s.insert("reason".into(), Value::from("because"));
            s.insert("result".into(), map([("status", Value::from("ok"))]));
        }
        let q = Plan::parse(&record("done", vec![reworded]), "s").unwrap();
        assert_eq!(q.hash, p.hash);
        let twice = record(
            "awaiting_approval",
            vec![step("set", A, "write", true), step("set", A, "write", true)],
        );
        assert!(Plan::parse(&twice, "s").is_err());
    }

    const A: &str = "wy/s/downstream/m/a/~set";
    const B: &str = "wy/s/downstream/m/b/~act/go";
    const C: &str = "wy/s/downstream/m/c/~set";

    fn plan() -> Plan {
        Plan::parse(
            &record(
                "awaiting_approval",
                vec![
                    step("set", A, "write", true),
                    step("invoke", B, "config", true),
                    step("set", C, "write", false),
                ],
            ),
            "s",
        )
        .unwrap()
    }

    fn ask(steps: &[&str], plan: &str) -> Ask {
        Ask {
            steps: steps.iter().map(|s| (*s).to_owned()).collect(),
            plan: plan.to_owned(),
        }
    }

    #[test]
    fn the_client_names_steps_and_nothing_else() {
        let ok = map([
            ("steps", Value::Array(vec![Value::from(A)])),
            ("plan", Value::from("h1")),
        ]);
        assert_eq!(Ask::parse(Some(&ok)).unwrap(), ask(&[A], "h1"));
        for bad in [
            Value::Null,
            map([("steps", Value::Array(vec![Value::from(A)]))]),
            map([
                ("steps", Value::Array(Vec::new())),
                ("plan", Value::from("h1")),
            ]),
            map([
                ("steps", Value::Array(vec![Value::from(A), Value::from(A)])),
                ("plan", Value::from("h1")),
            ]),
            map([
                ("steps", Value::Array(vec![Value::UInt(0)])),
                ("plan", Value::from("h1")),
            ]),
            // a token of the client's own making
            map([
                ("steps", Value::Array(vec![Value::from(A)])),
                ("plan", Value::from("h1")),
                ("approvals", map([(A, Value::Bytes(vec![1]))])),
            ]),
        ] {
            let e = Ask::parse(Some(&bad)).unwrap_err();
            assert_eq!(e.status, Status::InvalidParameter, "{bad:?}");
        }
        assert!(Ask::parse(None).is_err());
    }

    #[test]
    fn a_stored_step_is_a_request_on_a_node_of_the_site() {
        let p = plan();
        assert_eq!(p.steps.len(), 3);
        assert_eq!(
            (p.steps[1].level, p.steps[1].approval),
            (Perm::Config, true)
        );
        // the body is what the run sends: a `~set` wraps its value, an action does not
        assert_ne!(p.steps[0].body, p.steps[1].body);
        assert_eq!(p.steps[0].body, p.steps[2].body);
        for (op, key, level) in [
            ("set", "wy/other/downstream/m/a/~set", "write"),
            ("set", "wy/s/downstream/*/a/~set", "write"),
            ("set", "wy/s/downstream/**/~set", "write"),
            ("set", "wy/s/downstream/m/a", "write"),
            ("set", "wy/s/downstream/m/a/~act/go", "write"),
            ("invoke", "wy/s/downstream/m/a/~set", "write"),
            ("invoke", "wy/s/downstream/m/~act/x/~act/go", "write"),
            ("invoke", "wy/s/downstream/m/a/~act/*", "write"),
            ("deploy", A, "write"),
            ("set", A, "read"),
            ("set", A, "admin"),
        ] {
            let doc = record("awaiting_approval", vec![step(op, key, level, true)]);
            let e = Plan::parse(&doc, "s").unwrap_err();
            assert_eq!(e.status, Status::InternalError, "{op} {key} {level}");
        }
        // not a task of a link that knows `skip` and `plan`
        let old = map([
            ("state", Value::from("awaiting_approval")),
            ("plan", Value::Array(Vec::new())),
        ]);
        assert_eq!(
            Plan::parse(&old, "s").unwrap_err().status,
            Status::NotSupported
        );
        assert_eq!(
            Plan::parse(&Value::Null, "s").unwrap_err().status,
            Status::NotSupported
        );
    }

    #[test]
    fn only_ticked_steps_within_the_users_rights_are_signed() {
        let mut p = plan();
        p.hash = "h1".into();
        let config = |_: &str| Perm::Config;
        let write = |_: &str| Perm::Write;

        let (sign, skip) = p.select(&ask(&[A, B], "h1"), config).unwrap();
        assert_eq!(
            sign.iter().map(|s| s.key.as_str()).collect::<Vec<_>>(),
            [A, B]
        );
        assert!(skip.is_empty());
        // the step left out goes to the link as skipped; the one that needs no human is neither
        let (sign, skip) = p.select(&ask(&[A], "h1"), write).unwrap();
        assert_eq!(sign.len(), 1);
        assert_eq!(skip, [B]);

        // a `config` step for a user with `write`: refused whole, the step named
        let e = p.select(&ask(&[A, B], "h1"), write).unwrap_err();
        assert_eq!(e.status, Status::PermissionDenied);
        assert!(
            e.message.contains(B) && e.message.contains("config"),
            "{}",
            e.message
        );
        assert!(!e.message.contains(A), "{}", e.message);
        // a step outside the user's grants
        let only_b = |k: &str| if k == B { Perm::Config } else { Perm::Read };
        let e = p.select(&ask(&[A, B], "h1"), only_b).unwrap_err();
        assert_eq!(e.status, Status::PermissionDenied);
        assert!(e.message.contains(A), "{}", e.message);

        // an unknown step, a step that needs no human, a changed plan, a task not waiting
        for (a, want) in [
            (ask(&["wy/s/downstream/m/x/~set"], "h1"), "not a step"),
            (ask(&[C], "h1"), "needs no approval"),
            (ask(&[A], "h2"), "read it again"),
        ] {
            let e = p.select(&a, config).unwrap_err();
            assert_eq!(e.status, Status::InvalidParameter);
            assert!(e.message.contains(want), "{}", e.message);
        }
        let mut done = p.clone();
        done.state = "running".into();
        let e = done.select(&ask(&[A], "h1"), config).unwrap_err();
        assert_eq!(e.status, Status::InvalidParameter);
    }
}
